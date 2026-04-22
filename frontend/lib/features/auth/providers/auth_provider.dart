import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/websocket_client.dart';
import '../../../core/services/notification_service.dart';
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
  final WebSocketClient _ws;
  final FlutterSecureStorage _storage;

  AuthNotifier(this._api, this._ws, this._storage) : super(const AuthState()) {
    // Wire 401 responses to immediately clear state → router redirects to login.
    _api.onUnauthorized = () => state = const AuthState();
    _restoreSession();
    // Keep the FCM token current across token rotations (e.g. new device SIM).
    NotificationService.onTokenRefresh(_registerFcmToken);
  }

  /// Fire-and-forget: send the device's FCM token to the backend so it can
  /// send push notifications to this user. Failures are swallowed — a missing
  /// FCM token only means no push notifications, not a broken session.
  Future<void> _registerFcmToken(String token) async {
    try {
      await _api.updateFcmToken(token);
    } catch (_) {}
  }

  Future<void> _restoreSession() async {
    String? token, role, userIdStr, username, profilePicUrl, refreshToken;
    try {
      token        = await _storage.read(key: AppConstants.tokenStorageKey);
      role         = await _storage.read(key: AppConstants.roleStorageKey);
      userIdStr    = await _storage.read(key: AppConstants.userIdStorageKey);
      username     = await _storage.read(key: AppConstants.usernameStorageKey);
      profilePicUrl = await _storage.read(key: AppConstants.profilePicUrlStorageKey);
      refreshToken = await _storage.read(key: AppConstants.refreshTokenStorageKey);
    } catch (_) {
      // Keychain unavailable (e.g. macOS debug without signing) — start fresh
      return;
    }

    if (token == null || role == null) return;

    // Restore from cache immediately — no network call here.
    // If the access token is expired the 401 interceptor will refresh it on
    // the first API call. The refresh mutex in ApiClient ensures concurrent
    // 401s (e.g. 5 dashboard providers firing at once) trigger only ONE
    // refresh; all others wait and retry with the new token.
    _api.setCachedTokens(token: token, refreshToken: refreshToken);

    state = AuthState(
      token: token,
      role: role,
      userId: userIdStr != null ? int.tryParse(userIdStr) : null,
      username: username,
      profilePicUrl: profilePicUrl,
    );

    // Register FCM token now that we have a valid session.
    final fcmToken = await NotificationService.getToken();
    if (fcmToken != null) unawaited(_registerFcmToken(fcmToken));
  }

  Future<void> login(String username, String mpin) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _api.login(username, mpin);
      final token = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;
      final role = data['role'] as String;
      final userId = data['user_id'] as int;
      final uname = data['username'] as String;

      try {
        await _storage.write(key: AppConstants.tokenStorageKey, value: token);
        if (refreshToken != null) {
          await _storage.write(
              key: AppConstants.refreshTokenStorageKey, value: refreshToken);
        }
        await _storage.write(key: AppConstants.roleStorageKey, value: role);
        await _storage.write(
            key: AppConstants.userIdStorageKey, value: userId.toString());
        await _storage.write(
            key: AppConstants.usernameStorageKey, value: uname);
      } catch (_) {
        // Keychain unavailable (e.g. macOS debug without signing) — session is
        // held in memory only; will not persist across app restarts.
      }
      _api.setCachedTokens(token: token, refreshToken: refreshToken);

      // Fetch profile pic for admin and teacher
      String? profilePicUrl;
      if (role == 'admin' || role == 'teacher') {
        try {
          final me = await _api.getMe();
          profilePicUrl = me['profile_pic_url'] as String?;
          if (profilePicUrl != null) {
            try {
              await _storage.write(
                  key: AppConstants.profilePicUrlStorageKey,
                  value: profilePicUrl);
            } catch (_) {}
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

      // Register FCM token after successful login.
      final fcmToken = await NotificationService.getToken();
      if (fcmToken != null) unawaited(_registerFcmToken(fcmToken));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  /// Called after a successful photo upload to update in-memory + storage.
  Future<void> updateProfilePicUrl(String url) async {
    try {
      await _storage.write(key: AppConstants.profilePicUrlStorageKey, value: url);
    } catch (_) {}
    state = state.copyWith(profilePicUrl: url);
  }

  Future<void> updateUsername(String newUsername) async {
    try {
      await _storage.write(key: AppConstants.usernameStorageKey, value: newUsername);
    } catch (_) {}
    state = state.copyWith(username: newUsername);
  }

  Future<bool> register(String username, String mpin, String role,
      {String? phone,
      String? email,
      String? parentUsername,
      int? grade,
      List<String>? additionalSubjects,
      List<String>? teachableSubjects}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.register(username, mpin, role,
          phone: phone,
          email: email,
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
    // Revoke the access token server-side before clearing local state.
    // Fire-and-forget: network failure must never block the user from logging out.
    await _api.logoutOnServer();
    _api.clearCachedTokens();
    _ws.disconnect();
    try {
      await _storage.deleteAll();
    } catch (_) {}
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
  final ws = ref.read(webSocketClientProvider);
  return AuthNotifier(
    api,
    ws,
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  );
});
