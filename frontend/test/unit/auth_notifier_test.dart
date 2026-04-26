import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:mindforge/core/utils/constants.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

// onUnauthorized is a plain field; override it directly so the Mock base class
// does not try to route the setter through noSuchMethod.
class MockApiClient extends Mock implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

class MockWebSocketClient extends Mock implements WebSocketClient {}

// Manual in-memory fake — simpler than stubbing every async call with mocktail.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final _store = <String, String>{};
  bool deleteAllCalled = false;

  void seed(String key, String value) => _store[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteAllCalled = true;
    _store.clear();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _loginResponse({String role = 'student'}) => {
      'access_token': 'tok-abc',
      'refresh_token': 'ref-xyz',
      'role': role,
      'user_id': 42,
      'username': 'alice',
    };

DioException _dioError(int statusCode, {String? detail}) => DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/auth/login'),
        statusCode: statusCode,
        data: detail != null ? {'detail': detail} : null,
      ),
    );

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      type: DioExceptionType.connectionError,
    );

// FakeSecureStorage whose deleteAll() always throws — simulates a locked
// Keychain or unavailable secure enclave.
class _BrokenDeleteStorage extends FakeSecureStorage {
  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('Keychain unavailable');
  }
}

// ─── Test suite ───────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockApiClient api;
  late MockWebSocketClient ws;
  late FakeSecureStorage storage;

  AuthNotifier _make() => AuthNotifier(api, ws, storage);

  setUp(() {
    api = MockApiClient();
    ws = MockWebSocketClient();
    storage = FakeSecureStorage();

    // Default stub: logout is fire-and-forget; token methods are synchronous.
    when(() => api.logoutOnServer()).thenAnswer((_) async {});
    when(() => api.clearCachedTokens()).thenReturn(null);
    when(() => api.setCachedTokens(
          token: any(named: 'token'),
          refreshToken: any(named: 'refreshToken'),
        )).thenReturn(null);
    when(() => api.updateFcmToken(any())).thenAnswer((_) async {});
    when(() => ws.disconnect()).thenReturn(null);
  });

  // ── login() ──────────────────────────────────────────────────────────────────

  group('login()', () {
    test('success — sets token, role, userId, username in state', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');

      expect(n.state.isLoggedIn, isTrue);
      expect(n.state.token, 'tok-abc');
      expect(n.state.role, 'student');
      expect(n.state.userId, 42);
      expect(n.state.username, 'alice');
      expect(n.state.isLoading, isFalse);
      expect(n.state.error, isNull);
    });

    test('success — persists token and refresh token to storage', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');

      expect(storage.read(key: AppConstants.tokenStorageKey),
          completion('tok-abc'));
      expect(storage.read(key: AppConstants.refreshTokenStorageKey),
          completion('ref-xyz'));
      expect(storage.read(key: AppConstants.roleStorageKey),
          completion('student'));
      expect(storage.read(key: AppConstants.userIdStorageKey),
          completion('42'));
    });

    test('success — calls setCachedTokens with both tokens', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');

      verify(() => api.setCachedTokens(
            token: 'tok-abc',
            refreshToken: 'ref-xyz',
          )).called(greaterThanOrEqualTo(1));
    });

    test('admin login — calls getMe to fetch profile pic', () async {
      when(() => api.login('admin', '111111'))
          .thenAnswer((_) async => _loginResponse(role: 'admin'));
      when(() => api.getMe()).thenAnswer((_) async =>
          {'profile_pic_url': 'https://cdn.example.com/pic.jpg'});

      final n = _make();
      await n.login('admin', '111111');

      expect(n.state.profilePicUrl, 'https://cdn.example.com/pic.jpg');
      verify(() => api.getMe()).called(1);
    });

    test('teacher login — calls getMe to fetch profile pic', () async {
      when(() => api.login('bob', '222222'))
          .thenAnswer((_) async => _loginResponse(role: 'teacher'));
      when(() => api.getMe()).thenAnswer((_) async => {'profile_pic_url': null});

      final n = _make();
      await n.login('bob', '222222');

      verify(() => api.getMe()).called(1);
    });

    test('student login — does NOT call getMe', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse(role: 'student'));

      final n = _make();
      await n.login('alice', '123456');

      verifyNever(() => api.getMe());
    });

    test('401 error — sets "Invalid username or MPIN" message', () async {
      when(() => api.login(any(), any())).thenThrow(_dioError(401));

      final n = _make();
      await n.login('alice', 'wrong');

      expect(n.state.isLoggedIn, isFalse);
      expect(n.state.isLoading, isFalse);
      expect(n.state.error, 'Invalid username or MPIN.');
    });

    test('403 error — sets pending-approval message', () async {
      when(() => api.login(any(), any())).thenThrow(_dioError(403));

      final n = _make();
      await n.login('alice', '123456');

      expect(n.state.error, 'Your account is pending admin approval.');
    });

    test('server detail string is surfaced as error', () async {
      when(() => api.login(any(), any()))
          .thenThrow(_dioError(422, detail: 'Custom server message'));

      final n = _make();
      await n.login('alice', '123456');

      expect(n.state.error, 'Custom server message');
    });

    test('connection error — sets connectivity message', () async {
      when(() => api.login(any(), any())).thenThrow(_connectionError());

      final n = _make();
      await n.login('alice', '123456');

      expect(n.state.error,
          contains('Unable to connect to the server'));
    });

    test('isLoading is false after failed login', () async {
      when(() => api.login(any(), any())).thenThrow(_dioError(401));

      final n = _make();
      await n.login('alice', 'bad');

      expect(n.state.isLoading, isFalse);
    });

    test('state is not logged-in after failed login', () async {
      when(() => api.login(any(), any())).thenThrow(_dioError(401));

      final n = _make();
      await n.login('alice', 'bad');

      expect(n.state.isLoggedIn, isFalse);
      expect(n.state.token, isNull);
    });
  });

  // ── logout() ─────────────────────────────────────────────────────────────────

  group('logout()', () {
    Future<void> _loginFirst(AuthNotifier n) async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());
      await n.login('alice', '123456');
      expect(n.state.isLoggedIn, isTrue);
    }

    test('resets state to empty AuthState', () async {
      final n = _make();
      await _loginFirst(n);

      await n.logout();

      expect(n.state.isLoggedIn, isFalse);
      expect(n.state.token, isNull);
      expect(n.state.role, isNull);
      expect(n.state.userId, isNull);
      expect(n.state.username, isNull);
    });

    test('calls logoutOnServer to revoke the access token', () async {
      final n = _make();
      await _loginFirst(n);

      await n.logout();

      verify(() => api.logoutOnServer()).called(1);
    });

    test('calls clearCachedTokens to wipe in-memory tokens', () async {
      final n = _make();
      await _loginFirst(n);

      await n.logout();

      verify(() => api.clearCachedTokens()).called(1);
    });

    test('calls ws.disconnect()', () async {
      final n = _make();
      await _loginFirst(n);

      await n.logout();

      verify(() => ws.disconnect()).called(1);
    });

    test('calls storage.deleteAll() to clear persisted session', () async {
      final n = _make();
      await _loginFirst(n);

      await n.logout();

      expect(storage.deleteAllCalled, isTrue);
    });

    test('resets state even when storage.deleteAll() throws', () async {
      // Simulate a locked Keychain / unavailable secure enclave.
      final brokenStorage = _BrokenDeleteStorage();
      final n = AuthNotifier(api, ws, brokenStorage);
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());
      await n.login('alice', '123456');
      expect(n.state.isLoggedIn, isTrue);

      // Should not throw — deleteAll failure is caught internally.
      await expectLater(n.logout(), completes);
      expect(n.state.isLoggedIn, isFalse);
    });

    test('still calls clearCachedTokens when storage.deleteAll() throws',
        () async {
      final brokenStorage = _BrokenDeleteStorage();
      final n = AuthNotifier(api, ws, brokenStorage);
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());
      await n.login('alice', '123456');

      await n.logout();

      verify(() => api.clearCachedTokens()).called(greaterThanOrEqualTo(1));
    });

    test('can be called while already logged out without error', () async {
      final n = _make();
      // Not logged in — logout should still succeed.
      await expectLater(n.logout(), completes);
      expect(n.state.isLoggedIn, isFalse);
    });
  });

  // ── register() ───────────────────────────────────────────────────────────────

  group('register()', () {
    test('returns true and resets isLoading on success', () async {
      when(() => api.register(any(), any(), any()))
          .thenAnswer((_) async => {'id': 1, 'username': 'alice'});

      final n = _make();
      final result = await n.register('alice', '123456', 'student');

      expect(result, isTrue);
      expect(n.state.isLoading, isFalse);
      expect(n.state.error, isNull);
    });

    test('returns false and sets error on failure', () async {
      when(() => api.register(any(), any(), any()))
          .thenThrow(_dioError(409, detail: 'Username already taken.'));

      final n = _make();
      final result = await n.register('alice', '123456', 'student');

      expect(result, isFalse);
      expect(n.state.isLoading, isFalse);
      expect(n.state.error, 'Username already taken.');
    });

    test('passes optional fields to api.register', () async {
      when(() => api.register(
            any(),
            any(),
            any(),
            phone: any(named: 'phone'),
            grade: any(named: 'grade'),
          )).thenAnswer((_) async => {'id': 2, 'username': 'bob'});

      final n = _make();
      await n.register('bob', '654321', 'student',
          phone: '+91 99999 99999', grade: 9);

      verify(() => api.register(
            'bob',
            '654321',
            'student',
            phone: '+91 99999 99999',
            grade: 9,
          )).called(1);
    });

    test('does not modify login state on success', () async {
      when(() => api.register(any(), any(), any()))
          .thenAnswer((_) async => {'id': 1});

      final n = _make();
      await n.register('alice', '123456', 'student');

      // Register does not log the user in.
      expect(n.state.isLoggedIn, isFalse);
    });

    test('connection error — returns false with connectivity message', () async {
      when(() => api.register(any(), any(), any()))
          .thenThrow(_connectionError());

      final n = _make();
      final result = await n.register('alice', '123456', 'student');

      expect(result, isFalse);
      expect(n.state.error, contains('Unable to connect'));
    });
  });

  // ── _restoreSession() (called by constructor) ─────────────────────────────

  group('_restoreSession()', () {
    test('restores state from storage when all keys present', () async {
      storage
        ..seed(AppConstants.tokenStorageKey, 'saved-tok')
        ..seed(AppConstants.roleStorageKey, 'teacher')
        ..seed(AppConstants.userIdStorageKey, '7')
        ..seed(AppConstants.usernameStorageKey, 'carol')
        ..seed(AppConstants.profilePicUrlStorageKey, 'https://cdn.example.com/p.jpg')
        ..seed(AppConstants.refreshTokenStorageKey, 'saved-ref');

      final n = _make();
      // _restoreSession is async and fire-and-forget — pump the microtask queue.
      await Future<void>.delayed(Duration.zero);

      expect(n.state.token, 'saved-tok');
      expect(n.state.role, 'teacher');
      expect(n.state.userId, 7);
      expect(n.state.username, 'carol');
      expect(n.state.profilePicUrl, 'https://cdn.example.com/p.jpg');
    });

    test('calls setCachedTokens with restored tokens', () async {
      storage
        ..seed(AppConstants.tokenStorageKey, 'saved-tok')
        ..seed(AppConstants.roleStorageKey, 'student')
        ..seed(AppConstants.refreshTokenStorageKey, 'saved-ref');

      _make();
      await Future<void>.delayed(Duration.zero);

      verify(() => api.setCachedTokens(
            token: 'saved-tok',
            refreshToken: 'saved-ref',
          )).called(greaterThanOrEqualTo(1));
    });

    test('stays logged out when storage is empty', () async {
      final n = _make();
      await Future<void>.delayed(Duration.zero);

      expect(n.state.isLoggedIn, isFalse);
    });

    test('stays logged out when only token is present but role is missing',
        () async {
      storage.seed(AppConstants.tokenStorageKey, 'saved-tok');
      // No role stored.

      final n = _make();
      await Future<void>.delayed(Duration.zero);

      expect(n.state.isLoggedIn, isFalse);
    });
  });

  // ── onUnauthorized callback ───────────────────────────────────────────────

  group('onUnauthorized callback', () {
    test('clears state when api fires onUnauthorized', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');
      expect(n.state.isLoggedIn, isTrue);

      // Simulate a 401 from the interceptor.
      api.onUnauthorized?.call();

      expect(n.state.isLoggedIn, isFalse);
      expect(n.state.token, isNull);
    });
  });

  // ── updateProfilePicUrl() / updateUsername() ──────────────────────────────

  group('profile helpers', () {
    test('updateProfilePicUrl updates state and persists to storage', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');
      await n.updateProfilePicUrl('https://cdn.example.com/new.jpg');

      expect(n.state.profilePicUrl, 'https://cdn.example.com/new.jpg');
      expect(
        storage.read(key: AppConstants.profilePicUrlStorageKey),
        completion('https://cdn.example.com/new.jpg'),
      );
    });

    test('updateUsername updates state and persists to storage', () async {
      when(() => api.login('alice', '123456'))
          .thenAnswer((_) async => _loginResponse());

      final n = _make();
      await n.login('alice', '123456');
      await n.updateUsername('alice_new');

      expect(n.state.username, 'alice_new');
      expect(
        storage.read(key: AppConstants.usernameStorageKey),
        completion('alice_new'),
      );
    });
  });
}
