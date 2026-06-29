import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/report_problem_dialog.dart';
import '../../../core/widgets/side_nav.dart';
import '../../auth/providers/auth_provider.dart';
import 'parent_bottom_nav.dart';

/// Responsive scaffold for parent screens.
/// On wide screens (≥ 900 px) shows the dark left sidebar and hides the bottom
/// nav. On mobile shows the existing bottom nav — no change to mobile behaviour.
class ParentScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  /// When `true`, the web branch does NOT wrap the body in
  /// `Center + ConstrainedBox(maxWidth: 600)`. Use for screens that build
  /// their own desktop-wide layout so they fill the browser width.
  final bool wideContent;

  const ParentScaffold({
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

    if (!isWide) {
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: const ParentBottomNav(),
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        backgroundColor: backgroundColor,
      );
    }

    // Web: top nav + content area, no bottom nav. Mobile-styled bodies are
    // capped at 600 px and centred so they don't stretch on desktop. Screens
    // that already build a desktop-wide layout opt out with `wideContent`.
    final auth = ref.watch(authProvider);
    final innerBody = wideContent
        ? body
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: body,
            ),
          );
    return Scaffold(
      backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Row(
        children: [
          ParentSideNav(auth: auth),
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

// ─── Parent left navigation sidebar ───────────────────────────────────────────

class ParentSideNav extends ConsumerWidget {
  final AuthState auth;
  const ParentSideNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    SideNavItem item(IconData icon, String label, String suffix, String match) {
      final route = suffix.isEmpty
          ? RouteNames.parentDashboard
          : '${RouteNames.parentDashboard}$suffix';
      final isActive = match.isEmpty
          ? currentPath == RouteNames.parentDashboard
          : currentPath.contains(match);
      return SideNavItem(icon: icon, label: label, route: route, isActive: isActive);
    }

    return SideNav(
      username: auth.username ?? 'P',
      profileRoute: '${RouteNames.parentDashboard}/profile',
      onLogout: () => confirmLogout(context, ref),
      onReportProblem: () => showReportProblemDialog(context, ref),
      items: [
        item(Icons.home_outlined, 'Home', '', ''),
        item(Icons.grade_outlined, 'Grades', '/grades', '/grades'),
        item(Icons.how_to_reg_outlined, 'Attendance', '/attendance', '/attendance'),
        item(Icons.calendar_month_outlined, 'Timetable', '/timetable', '/timetable'),
        item(Icons.receipt_long_outlined, 'Fees', '/fees', '/fees'),
        item(Icons.assignment_outlined, 'Homework', '/homework', '/homework'),
        item(Icons.people_outline, 'Faculty', '/faculty', '/faculty'),
      ],
    );
  }
}
