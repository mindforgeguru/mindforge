import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/constants.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class AuthState {
  final String? token;
  final String? role;
  final int? userId;
  final String? username;
  final String? profilePicUrl;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.token,
    this.role,
    this.userId,
    this.username,
    this.profilePicUrl,
    this.isLoading = false,
    this.error,
  });

  bool get isLoggedIn => token != null;

  AuthState copyWith({
    String? token,
    String? role,
    int? userId,
    String? username,
    String? profilePicUrl,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearToken = false,
    bool clearProfilePic = false,
  }) {
    return AuthState(
      token: clearToken ? null : (token ?? this.token),
      role: clearToken ? null : (role ?? this.role),
      userId: clearToken ? null : (userId ?? this.userId),
      username: clearToken ? null : (username ?? this.username),
      profilePicUrl: clearToken || clearProfilePic
          ? null
          : (profilePicUrl ?? this.profilePicUrl),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  AuthNotifier(this._api, this._storage) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _storage.read(key: AppConstants.tokenStorageKey);
    final role = await _storage.read(key: AppConstants.roleStorageKey);
    final userIdStr = await _storage.read(key: AppConstants.userIdStorageKey);
    final username = await _storage.read(key: AppConstants.usernameStorageKey);
    final profilePicUrl =
        await _storage.read(key: AppConstants.profilePicUrlStorageKey);

    if (token == null || role == null) return;

    // Restore from cache immediately so the router can navigate to the
    // dashboard without waiting for the network.
    state = AuthState(
      token: token,
      role: role,
      userId: userIdStr != null ? int.tryParse(userIdStr) : null,
      username: username,
      profilePicUrl: profilePicUrl,
    );

    // Then verify the token in the background and refresh the profile pic.
    // Only wipe credentials on a genuine 401 — network errors at startup
    // (e.g. OS not yet connected after unlock) must not log the user out.
    try {
      final me = await _api.getMe();
      final freshPicUrl = me['profile_pic_url'] as String?;
      if (freshPicUrl != null) {
        await _storage.write(
            key: AppConstants.profilePicUrlStorageKey, value: freshPicUrl);
        state = state.copyWith(profilePicUrl: freshPicUrl);
      }
    } catch (e) {
      final is401 = e is DioException && e.response?.statusCode == 401;
      if (is401) {
        await _storage.deleteAll();
        state = const AuthState();
      }
      // Any other error (no network, timeout, etc.) — stay logged in with
      // cached data; the token will be validated on the next API call.
    }
  }

  Future<void> login(String username, String mpin) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _api.login(username, mpin);
      final token = data['access_token'] as String;
      final role = data['role'] as String;
      final userId = data['user_id'] as int;
      final uname = data['username'] as String;

      await _storage.write(key: AppConstants.tokenStorageKey, value: token);
      await _storage.write(key: AppConstants.roleStorageKey, value: role);
      await _storage.write(
          key: AppConstants.userIdStorageKey, value: userId.toString());
      await _storage.write(
          key: AppConstants.usernameStorageKey, value: uname);

      // Fetch profile pic for admin and teacher
      String? profilePicUrl;
      if (role == 'admin' || role == 'teacher') {
        try {
          final me = await _api.getMe();
          profilePicUrl = me['profile_pic_url'] as String?;
          if (profilePicUrl != null) {
            await _storage.write(
                key: AppConstants.profilePicUrlStorageKey,
                value: profilePicUrl);
          }
        } catch (_) {}
      }

      state = AuthState(
        token: token,
        role: role,
        userId: userId,
        username: uname,
        profilePicUrl: profilePicUrl,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  /// Called after a successful photo upload to update in-memory + storage.
  Future<void> updateProfilePicUrl(String url) async {
    await _storage.write(
        key: AppConstants.profilePicUrlStorageKey, value: url);
    state = state.copyWith(profilePicUrl: url);
  }

  Future<void> updateUsername(String newUsername) async {
    await _storage.write(
        key: AppConstants.usernameStorageKey, value: newUsername);
    state = state.copyWith(username: newUsername);
  }

  Future<bool> register(String username, String mpin, String role,
      {String? parentUsername,
      int? grade,
      List<String>? additionalSubjects,
      List<String>? teachableSubjects}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.register(username, mpin, role,
          parentUsername: parentUsername,
          grade: grade,
          additionalSubjects: additionalSubjects,
          teachableSubjects: teachableSubjects);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AuthState();
  }

  String _parseError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return 'Unable to connect to the server. Please check your internet connection and try again.';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out. Please try again.';
      }
      final status = e.response?.statusCode;
      if (status == 403) return 'Your account is pending admin approval.';
      if (status == 401) return 'Invalid username or MPIN.';
      final detail = e.response?.data?['detail'];
      if (detail != null) return detail.toString();
    }
    return 'Something went wrong. Please try again.';
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(
    api,
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  );
});
