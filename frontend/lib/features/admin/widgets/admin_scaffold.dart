import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/side_nav.dart';
import '../../auth/providers/auth_provider.dart';
import 'admin_bottom_nav.dart';

/// Responsive scaffold for admin screens.
/// On wide screens (≥ 900 px) shows the dark left sidebar and hides the bottom
/// nav. On mobile shows the existing bottom nav — no change to mobile behaviour.
class AdminScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  /// Whether to show the bottom-nav on mobile. Leaf screens (e.g. settings
  /// pushed via back-button flow) pass false to keep their mobile look.
  final bool showMobileBottomNav;
  final bool? resizeToAvoidBottomInset;

  /// When `true`, the web branch does NOT wrap the body in
  /// `Center + ConstrainedBox(maxWidth: 600)`. Use for screens that build
  /// their own desktop-wide layout so they fill the browser width.
  final bool wideContent;

  const AdminScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.showMobileBottomNav = true,
    this.resizeToAvoidBottomInset,
    this.wideContent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (!isWide) {
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar:
            showMobileBottomNav ? const AdminBottomNav() : null,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    // Web: top nav + content area, no bottom nav. Mobile-styled bodies are
    // capped at 600 px and centred so they don't stretch on desktop. Screens
    // with their own desktop-wide layout opt out with `wideContent: true`.
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
          AdminSideNav(auth: auth),
          Expanded(
            child: Scaffold(
              appBar: appBar,
              body: innerBody,
              backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Admin left navigation sidebar ───────────────────────────────────────────

class AdminSideNav extends ConsumerWidget {
  final AuthState auth;
  const AdminSideNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    SideNavItem item(IconData icon, String label, String suffix, String match) {
      final route = suffix.isEmpty
          ? RouteNames.adminDashboard
          : '${RouteNames.adminDashboard}$suffix';
      final isActive = match.isEmpty
          ? currentPath == RouteNames.adminDashboard
          : currentPath.contains(match);
      return SideNavItem(icon: icon, label: label, route: route, isActive: isActive);
    }

    return SideNav(
      username: auth.username ?? 'A',
      profileRoute: '${RouteNames.adminDashboard}/profile',
      onLogout: () => confirmLogout(context, ref),
      items: [
        item(Icons.home_outlined, 'Home', '', ''),
        item(Icons.people_outline, 'Users', '/users', '/users'),
        item(Icons.school_outlined, 'Teachers', '/teachers', '/teachers'),
        item(Icons.receipt_long_outlined, 'Fees', '/fees', '/fees'),
        item(Icons.bar_chart_outlined, 'Reports', '/reports', '/reports'),
        item(Icons.feedback_outlined, 'Feedback', '/feedback', '/feedback'),
        item(Icons.calendar_month_outlined, 'Timetable', '/timetable', '/timetable'),
        item(Icons.event_note_outlined, 'Academic Year', '/academic-year', '/academic-year'),
      ],
    );
  }
}
