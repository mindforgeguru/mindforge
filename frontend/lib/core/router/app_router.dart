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
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Teacher ───────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.teacherDashboard,
        builder: (_, __) => const teacher.TeacherDashboardScreen(),
        routes: [
          GoRoute(
            path: 'attendance',
            builder: (_, __) => const teacher.TeacherAttendanceScreen(),
          ),
          GoRoute(
            path: 'timetable',
            builder: (_, __) => const teacher.TeacherTimetableScreen(),
          ),
          GoRoute(
            path: 'grades',
            builder: (_, __) => const teacher.TeacherGradeScreen(),
          ),
          GoRoute(
            path: 'tests',
            builder: (_, __) => const teacher.TeacherTestScreen(),
          ),
          GoRoute(
            path: 'profile',
            builder: (_, __) => const teacher.TeacherProfileScreen(),
          ),
          GoRoute(
            path: 'homework',
            builder: (_, __) => const teacher.TeacherHomeworkScreen(),
          ),
          GoRoute(
            path: 'broadcasts',
            builder: (_, __) => const teacher.TeacherBroadcastScreen(),
          ),
        ],
      ),

      // ── Student ───────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.studentDashboard,
        builder: (_, __) => const student.StudentDashboardScreen(),
        routes: [
          GoRoute(
            path: 'attendance',
            builder: (_, __) => const student.StudentAttendanceScreen(),
          ),
          GoRoute(
            path: 'timetable',
            builder: (_, __) => const student.StudentTimetableScreen(),
          ),
          GoRoute(
            path: 'grades',
            builder: (_, __) => const student.StudentGradeScreen(),
          ),
          GoRoute(
            path: 'tests',
            builder: (_, __) => const student.StudentTestScreen(),
          ),
          GoRoute(
            path: 'tests/:testId/attempt',
            builder: (context, state) {
              final testId = int.parse(state.pathParameters['testId']!);
              return student.TestAttemptScreen(testId: testId);
            },
          ),
          GoRoute(
            path: 'tests/:testId/review',
            builder: (context, state) {
              final testId = int.parse(state.pathParameters['testId']!);
              return student.TestReviewScreen(testId: testId);
            },
          ),
          GoRoute(
            path: 'profile',
            builder: (_, __) => const student.StudentProfileScreen(),
          ),
          GoRoute(
            path: 'homework',
            builder: (_, __) => const student.StudentHomeworkScreen(),
          ),
        ],
      ),

      // ── Parent ────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.parentDashboard,
        builder: (_, __) => const parent.ParentDashboardScreen(),
        routes: [
          GoRoute(
            path: 'attendance',
            builder: (_, __) => const parent.ParentAttendanceScreen(),
          ),
          GoRoute(
            path: 'timetable',
            builder: (_, __) => const parent.ParentTimetableScreen(),
          ),
          GoRoute(
            path: 'grades',
            builder: (_, __) => const parent.ParentGradeScreen(),
          ),
          GoRoute(
            path: 'fees',
            builder: (_, __) => const parent.ParentFeesScreen(),
          ),
          GoRoute(
            path: 'profile',
            builder: (_, __) => const parent.ParentProfileScreen(),
          ),
          GoRoute(
            path: 'homework',
            builder: (_, state) {
              final tab =
                  int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
              return parent.ParentHomeworkScreen(initialTab: tab);
            },
          ),
        ],
      ),

      // ── Admin ─────────────────────────────────────────────────────────────
      GoRoute(
        path: RouteNames.adminDashboard,
        builder: (_, __) => const admin.AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'fees',
            builder: (_, __) => const admin.AdminFeesScreen(),
          ),
          GoRoute(
            path: 'timetable',
            builder: (_, __) => const admin.AdminTimetableScreen(),
          ),
          GoRoute(
            path: 'users',
            builder: (_, __) => const admin.AdminUsersScreen(),
          ),
          GoRoute(
            path: 'profile',
            builder: (_, __) => const admin.AdminProfileScreen(),
          ),
          GoRoute(
            path: 'academic-year',
            builder: (_, __) => const AdminAcademicYearScreen(),
          ),
          GoRoute(
            path: 'reports',
            builder: (_, __) => const AdminReportsScreen(),
          ),
        ],
      ),
    ],
  );
});
