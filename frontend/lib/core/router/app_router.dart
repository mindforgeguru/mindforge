import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/constants.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/teacher/screens/dashboard_screen.dart' as teacher;
import '../../features/teacher/screens/attendance_screen.dart' as teacher;
import '../../features/teacher/screens/timetable_screen.dart' as teacher;
import '../../features/teacher/screens/grade_screen.dart' as teacher;
import '../../features/teacher/screens/test_screen.dart' as teacher;
import '../../features/teacher/screens/profile_screen.dart' as teacher;
import '../../features/teacher/screens/homework_screen.dart' as teacher;
import '../../features/teacher/screens/broadcast_screen.dart' as teacher;
import '../../features/student/screens/dashboard_screen.dart' as student;
import '../../features/student/screens/attendance_screen.dart' as student;
import '../../features/student/screens/timetable_screen.dart' as student;
import '../../features/student/screens/grade_screen.dart' as student;
import '../../features/student/screens/test_screen.dart' as student;
import '../../features/student/screens/test_attempt_screen.dart' as student;
import '../../features/student/screens/test_review_screen.dart' as student;
import '../../features/student/screens/profile_screen.dart' as student;
import '../../features/student/screens/homework_screen.dart' as student;
import '../../features/parent/screens/dashboard_screen.dart' as parent;
import '../../features/parent/screens/attendance_screen.dart' as parent;
import '../../features/parent/screens/timetable_screen.dart' as parent;
import '../../features/parent/screens/grade_screen.dart' as parent;
import '../../features/parent/screens/fees_screen.dart' as parent;
import '../../features/parent/screens/profile_screen.dart' as parent;
import '../../features/parent/screens/homework_screen.dart' as parent;
import '../../features/admin/screens/dashboard_screen.dart' as admin;
import '../../features/admin/screens/fees_screen.dart' as admin;
import '../../features/admin/screens/timetable_screen.dart' as admin;
import '../../features/admin/screens/users_screen.dart' as admin;
import '../../features/admin/screens/profile_screen.dart' as admin;
import '../../features/admin/screens/academic_year_screen.dart';
import '../../features/admin/screens/reports_screen.dart';

/// Shared page transition: fast fade+slide up (iOS-style feel on Android too).
CustomTransitionPage<void> _slidePage(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  transitionsBuilder: (_, animation, secondaryAnimation, child) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  },
);

// ─── RouterNotifier ───────────────────────────────────────────────────────────
// A ChangeNotifier that tells GoRouter to re-run redirect whenever auth changes.
// This keeps a single GoRouter instance alive (no more router recreation).

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authProvider);
    final isLoggedIn = authState.token != null;
    final isLoginRoute = state.matchedLocation == RouteNames.login;
    final isSplash = state.matchedLocation == RouteNames.splash;

    // Let the splash screen handle its own navigation
    if (isSplash) return null;

    if (!isLoggedIn && !isLoginRoute) return RouteNames.login;
    if (isLoggedIn && isLoginRoute) {
      switch (authState.role) {
        case 'teacher':
          return RouteNames.teacherDashboard;
        case 'student':
          return RouteNames.studentDashboard;
        case 'parent':
          return RouteNames.parentDashboard;
        case 'admin':
          return RouteNames.adminDashboard;
        default:
          return RouteNames.login;
      }
    }
    return null;
  }
}

final _routerNotifierProvider = Provider<_RouterNotifier>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // ── Splash ────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.splash,
        builder: (_, __) => const SplashScreen(),
      ),

      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.login,
        pageBuilder: (_, __) => _slidePage(const LoginScreen()),
      ),

      // ── Teacher ───────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.teacherDashboard,
        pageBuilder: (_, __) => _slidePage(const teacher.TeacherDashboardScreen()),
        routes: [
          GoRoute(
            path: 'attendance',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherAttendanceScreen()),
          ),
          GoRoute(
            path: 'timetable',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherTimetableScreen()),
          ),
          GoRoute(
            path: 'grades',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherGradeScreen()),
          ),
          GoRoute(
            path: 'tests',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherTestScreen()),
          ),
          GoRoute(
            path: 'profile',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherProfileScreen()),
          ),
          GoRoute(
            path: 'homework',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherHomeworkScreen()),
          ),
          GoRoute(
            path: 'broadcasts',
            pageBuilder: (_, __) => _slidePage(const teacher.TeacherBroadcastScreen()),
          ),
        ],
      ),

      // ── Student ───────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.studentDashboard,
        pageBuilder: (_, __) => _slidePage(const student.StudentDashboardScreen()),
        routes: [
          GoRoute(
            path: 'attendance',
            pageBuilder: (_, __) => _slidePage(const student.StudentAttendanceScreen()),
          ),
          GoRoute(
            path: 'timetable',
            pageBuilder: (_, __) => _slidePage(const student.StudentTimetableScreen()),
          ),
          GoRoute(
            path: 'grades',
            pageBuilder: (_, __) => _slidePage(const student.StudentGradeScreen()),
          ),
          GoRoute(
            path: 'tests',
            pageBuilder: (_, __) => _slidePage(const student.StudentTestScreen()),
          ),
          GoRoute(
            path: 'tests/:testId/attempt',
            pageBuilder: (_, state) {
              final testId = int.parse(state.pathParameters['testId']!);
              return _slidePage(student.TestAttemptScreen(testId: testId));
            },
          ),
          GoRoute(
            path: 'tests/:testId/review',
            pageBuilder: (_, state) {
              final testId = int.parse(state.pathParameters['testId']!);
              return _slidePage(student.TestReviewScreen(testId: testId));
            },
          ),
          GoRoute(
            path: 'profile',
            pageBuilder: (_, __) => _slidePage(const student.StudentProfileScreen()),
          ),
          GoRoute(
            path: 'homework',
            pageBuilder: (_, __) => _slidePage(const student.StudentHomeworkScreen()),
          ),
        ],
      ),

      // ── Parent ────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.parentDashboard,
        pageBuilder: (_, __) => _slidePage(const parent.ParentDashboardScreen()),
        routes: [
          GoRoute(
            path: 'attendance',
            pageBuilder: (_, __) => _slidePage(const parent.ParentAttendanceScreen()),
          ),
          GoRoute(
            path: 'timetable',
            pageBuilder: (_, __) => _slidePage(const parent.ParentTimetableScreen()),
          ),
          GoRoute(
            path: 'grades',
            pageBuilder: (_, __) => _slidePage(const parent.ParentGradeScreen()),
          ),
          GoRoute(
            path: 'fees',
            pageBuilder: (_, __) => _slidePage(const parent.ParentFeesScreen()),
          ),
          GoRoute(
            path: 'profile',
            pageBuilder: (_, __) => _slidePage(const parent.ParentProfileScreen()),
          ),
          GoRoute(
            path: 'homework',
            pageBuilder: (_, state) {
              final tab =
                  int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
              return _slidePage(parent.ParentHomeworkScreen(initialTab: tab));
            },
          ),
        ],
      ),

      // ── Admin ─────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.adminDashboard,
        pageBuilder: (_, __) => _slidePage(const admin.AdminDashboardScreen()),
        routes: [
          GoRoute(
            path: 'fees',
            pageBuilder: (_, __) => _slidePage(const admin.AdminFeesScreen()),
          ),
          GoRoute(
            path: 'timetable',
            pageBuilder: (_, __) => _slidePage(const admin.AdminTimetableScreen()),
          ),
          GoRoute(
            path: 'users',
            pageBuilder: (_, __) => _slidePage(const admin.AdminUsersScreen()),
          ),
          GoRoute(
            path: 'profile',
            pageBuilder: (_, __) => _slidePage(const admin.AdminProfileScreen()),
          ),
          GoRoute(
            path: 'academic-year',
            pageBuilder: (_, __) => _slidePage(const AdminAcademicYearScreen()),
          ),
          GoRoute(
            path: 'reports',
            pageBuilder: (_, __) => _slidePage(const AdminReportsScreen()),
          ),
        ],
      ),
    ],
  );
});
