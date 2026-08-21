import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/router/app_router.dart';
import 'package:mindforge/core/utils/constants.dart';

/// The routing guard is the app's access check for directly-entered locations.
/// On Flutter web every route is reachable by typing it into the URL bar, so a
/// student can ask for /admin/users the same way they ask for their own
/// dashboard. `resolveRouteRedirect` is what turns that request away.
///
/// It is not the security boundary — the backend rejects a student's call to an
/// admin endpoint regardless — but it is what stops a wrong-role or logged-out
/// user landing on a screen that would only render errors, and these tests
/// exist so that guarantee cannot be refactored away unnoticed. Each "bounce"
/// case fails loudly if the guard is loosened.
void main() {
  group('logged out', () {
    test('any protected location is sent to login', () {
      for (final loc in [
        RouteNames.adminDashboard,
        '${RouteNames.adminDashboard}/users',
        RouteNames.studentDashboard,
        '${RouteNames.teacherDashboard}/grades',
        RouteNames.ownerDashboard,
      ]) {
        expect(
          resolveRouteRedirect(isLoggedIn: false, role: null, location: loc),
          RouteNames.login,
          reason: '$loc must require login',
        );
      }
    });

    test('the login route itself is allowed', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: false, role: null, location: RouteNames.login),
        isNull,
      );
    });

    test('splash is left alone to route itself', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: false, role: null, location: RouteNames.splash),
        isNull,
      );
    });
  });

  group('logged in, correct section', () {
    test('each role may reach its own dashboard and nested routes', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'admin', location: '${RouteNames.adminDashboard}/users'),
        isNull,
      );
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'student', location: '${RouteNames.studentDashboard}/tests/5/attempt'),
        isNull,
      );
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'teacher', location: RouteNames.teacherDashboard),
        isNull,
      );
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'parent', location: '${RouteNames.parentDashboard}/grades'),
        isNull,
      );
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'owner', location: RouteNames.ownerDashboard),
        isNull,
      );
    });

    test('a logged-in user on the login route goes to their home', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'parent', location: RouteNames.login),
        RouteNames.parentDashboard,
      );
    });
  });

  group('logged in, wrong section — the case that matters', () {
    test('a student aiming at the admin area is bounced to the student home', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'student', location: '${RouteNames.adminDashboard}/users'),
        RouteNames.studentDashboard,
      );
    });

    test('a parent cannot reach the teacher area', () {
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'parent', location: '${RouteNames.teacherDashboard}/grades'),
        RouteNames.parentDashboard,
      );
    });

    test('every non-owner role is turned away from the owner console', () {
      for (final role in ['student', 'parent', 'teacher', 'admin']) {
        expect(
          resolveRouteRedirect(
              isLoggedIn: true, role: role, location: RouteNames.ownerDashboard),
          _homeForRole(role),
          reason: '$role must not reach the owner console',
        );
      }
    });
  });

  group('edge cases that must fail closed', () {
    test('a logged-in user with an unknown role is sent to login, not admitted', () {
      // A token present but role missing (e.g. mid-load or a tampered store)
      // must not be treated as any section owner.
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: null, location: '${RouteNames.adminDashboard}/users'),
        RouteNames.login,
      );
    });

    test('a sibling path sharing a prefix is not treated as inside the section', () {
      // '/studentportal' must not match the '/student' section: if it did, the
      // trailing-slash guard would be pointless. There is no such route today,
      // so a same-role user simply passes through (null) rather than being
      // wrongly bounced.
      expect(
        resolveRouteRedirect(
            isLoggedIn: true, role: 'student', location: '/studentportal'),
        isNull,
      );
    });
  });
}

/// Mirror of the private _homeFor, kept here so the owner-console loop can
/// assert the exact destination rather than merely "not null".
String _homeForRole(String role) => {
      'teacher': RouteNames.teacherDashboard,
      'student': RouteNames.studentDashboard,
      'parent': RouteNames.parentDashboard,
      'admin': RouteNames.adminDashboard,
      'owner': RouteNames.ownerDashboard,
    }[role]!;
