import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/report_problem_dialog.dart';
import '../../../core/widgets/side_nav.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/xp_provider.dart';
import 'student_bottom_nav.dart';

/// Responsive scaffold for student screens.
/// On wide screens (≥ 900 px) shows the dark left sidebar and hides the bottom
/// nav. On mobile shows the existing bottom nav — no change to mobile behaviour.
class StudentScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  /// When `true`, the web branch does NOT wrap the body in
  /// `Center + ConstrainedBox(maxWidth: 600)`. Use this for screens that
  /// build their own desktop-wide layout (e.g. multi-column views) so they
  /// can fill the available browser width instead of being squished into
  /// a 600 px phone-shaped centre column.
  final bool wideContent;

  const StudentScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.wideContent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    // Re-key the body when the palette switches. AppColors getters return
    // the new values immediately, but screens that read them directly (no
    // Theme.of dependency) won't auto-rebuild. Changing the KeyedSubtree
    // key forces Flutter to dispose & rebuild the body element with fresh
    // colors. Cost: scroll position / form state in the body resets on
    // theme change — acceptable since the user just asked for a visual
    // change.
    final palette = ref.watch(currentPaletteProvider);
    final keyedBody = KeyedSubtree(
      key: ValueKey('palette:${palette.id}'),
      child: body,
    );

    if (!isWide) {
      return Scaffold(
        appBar: appBar,
        body: keyedBody,
        bottomNavigationBar: const StudentBottomNav(),
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        backgroundColor: backgroundColor,
      );
    }

    // Web: left sidebar + content area, no bottom nav, no secondary AppBar.
    // Mobile-styled bodies are capped at 600 px and centred so they don't
    // stretch across a desktop browser. Screens that already build a
    // desktop-wide layout (multi-column grids, three-pane tabs, etc.) opt
    // out by passing `wideContent: true` and receive the full available
    // width instead.
    final auth = ref.watch(authProvider);
    final innerBody = wideContent
        ? keyedBody
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: keyedBody,
            ),
          );
    return Scaffold(
      backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Row(
        children: [
          StudentSideNav(auth: auth),
          Expanded(
            child: Scaffold(
              body: innerBody,
              backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared left navigation sidebar ───────────────────────────────────────────

class StudentSideNav extends ConsumerWidget {
  final AuthState auth;
  const StudentSideNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    SideNavItem item(IconData icon, String label, String suffix, String match) {
      final route = suffix.isEmpty
          ? RouteNames.studentDashboard
          : '${RouteNames.studentDashboard}$suffix';
      final isActive = match.isEmpty
          ? currentPath == RouteNames.studentDashboard
          : currentPath.contains(match);
      return SideNavItem(icon: icon, label: label, route: route, isActive: isActive);
    }

    return SideNav(
      username: auth.username ?? 'S',
      profileRoute: '${RouteNames.studentDashboard}/profile',
      onLogout: () => confirmLogout(context, ref),
      onReportProblem: () => showReportProblemDialog(context, ref),
      items: [
        item(Icons.home_outlined, 'Home', '', ''),
        item(Icons.grade_outlined, 'Grades', '/grades', '/grades'),
        item(Icons.quiz_outlined, 'Tests', '/tests', '/tests'),
        item(Icons.how_to_reg_outlined, 'Attendance', '/attendance', '/attendance'),
        item(Icons.calendar_month_outlined, 'Timetable', '/timetable', '/timetable'),
        item(Icons.assignment_outlined, 'Homework', '/homework', '/homework'),
        item(Icons.campaign_outlined, 'Broadcasts', '/broadcasts', '/broadcasts'),
        item(Icons.receipt_long_outlined, 'Fees', '/fees', '/fees'),
        item(Icons.people_outline, 'Faculty', '/faculty', '/faculty'),
        item(Icons.bolt_outlined, 'XP', '/xp', '/xp'),
        item(Icons.leaderboard_outlined, 'Leaderboard', '/xp/leaderboard', '/leaderboard'),
      ],
    );
  }
}
