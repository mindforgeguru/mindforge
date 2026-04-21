import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';

void main() {
  group('AuthState.copyWith', () {
    const base = AuthState(
      token: 'tok',
      role: 'teacher',
      userId: 42,
      username: 'alice',
      profilePicUrl: 'https://example.com/pic.jpg',
      isLoading: false,
      error: null,
    );

    test('clearToken=true clears token, role, userId, username and profilePic', () {
      final s = base.copyWith(clearToken: true);
      expect(s.token, isNull);
      expect(s.role, isNull);
      expect(s.userId, isNull);
      expect(s.username, isNull);
      expect(s.profilePicUrl, isNull);
    });

    test('clearToken=true ignores any supplied values for cleared fields', () {
      final s = base.copyWith(clearToken: true, token: 'new', role: 'admin');
      expect(s.token, isNull);
      expect(s.role, isNull);
    });

    test('clearProfilePic=true sets profilePicUrl to null without clearing token', () {
      final s = base.copyWith(clearProfilePic: true);
      expect(s.profilePicUrl, isNull);
      expect(s.token, 'tok');
      expect(s.role, 'teacher');
    });

    test('clearError=true sets error to null', () {
      final withError = base.copyWith(error: 'oops');
      expect(withError.error, 'oops');
      final cleared = withError.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('partial update preserves unchanged fields', () {
      final s = base.copyWith(isLoading: true);
      expect(s.isLoading, isTrue);
      expect(s.token, 'tok');
      expect(s.username, 'alice');
    });

    test('updating profilePicUrl works without clearToken', () {
      final s = base.copyWith(profilePicUrl: 'https://example.com/new.jpg');
      expect(s.profilePicUrl, 'https://example.com/new.jpg');
      expect(s.token, 'tok');
    });

    test('isLoggedIn is true when token is set', () {
      expect(base.isLoggedIn, isTrue);
    });

    test('isLoggedIn is false after clearToken', () {
      final s = base.copyWith(clearToken: true);
      expect(s.isLoggedIn, isFalse);
    });

    test('isLoggedIn is false on empty AuthState', () {
      expect(const AuthState().isLoggedIn, isFalse);
    });
  });
}
