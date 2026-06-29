import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/side_nav.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import 'teacher_bottom_nav.dart';

/// Responsive scaffold for teacher screens.
/// On wide screens (≥ 900 px) shows the dark left sidebar and hides the bottom
/// nav. On mobile shows the existing bottom nav — no change to mobile behaviour.
class TeacherScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  /// When `true`, the web branch does NOT wrap the body in
  /// `Center + ConstrainedBox(maxWidth: 600)`. Use for screens that build
  /// their own desktop-wide layout so they fill the browser width.
  final bool wideContent;

  const TeacherScaffold({
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
      // ── Mobile: identical to the old Scaffold + TeacherBottomNav ──────────
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: const TeacherBottomNav(),
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        backgroundColor: backgroundColor,
      );
    }

    // ── Web: left sidebar + content ────────────────────────────────────────
    // Mirrors ParentScaffold/StudentScaffold for visual consistency across
    // roles. Mobile-styled bodies are capped at 600 px and centred so they
    // don't stretch across the desktop. Screens that already build a
    // desktop-wide layout opt out with `wideContent: true`.
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
      backgroundColor: backgroundColor ?? AppColors.background,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Row(
        children: [
          TeacherSideNav(auth: auth),
          Expanded(
            child: Scaffold(
              appBar: appBar,
              body: innerBody,
              backgroundColor: backgroundColor ?? AppColors.background,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Teacher left navigation sidebar ──────────────────────────────────────────

class TeacherSideNav extends ConsumerWidget {
  final AuthState auth;
  const TeacherSideNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    // Badges: grades and broadcasts pulse a small dot in the sidebar when
    // there's something new since the last time the teacher viewed them.
    final lastSeenGrade = ref.watch(teacherGradeBadgeNotifier);
    final gradesAsync = ref.watch(teacherGradesProvider((null, null)));
    final hasGradeBadge = gradesAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list.map((g) => g.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return lastSeenGrade == null || latest.isAfter(lastSeenGrade);
      },
      orElse: () => false,
    );
    final lastSeenBroadcast = ref.watch(teacherBroadcastBadgeNotifier);
    final broadcastsAsync = ref.watch(teacherBroadcastsProvider);
    final hasBroadcastBadge = broadcastsAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list.map((b) => b.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return lastSeenBroadcast == null || latest.isAfter(lastSeenBroadcast);
      },
      orElse: () => false,
    );

    SideNavItem item(IconData icon, String label, String suffix, String match,
        {bool showBadge = false, VoidCallback? onTapSideEffect}) {
      final route = suffix.isEmpty
          ? RouteNames.teacherDashboard
          : '${RouteNames.teacherDashboard}$suffix';
      final isActive = match.isEmpty
          ? (currentPath == RouteNames.teacherDashboard ||
              currentPath == '${RouteNames.teacherDashboard}/')
          : currentPath.contains(match);
      return SideNavItem(
        icon: icon,
        label: label,
        route: route,
        isActive: isActive,
        showBadge: showBadge,
        onTapSideEffect: onTapSideEffect,
      );
    }

    return SideNav(
      username: auth.username ?? 'T',
      profileRoute: '${RouteNames.teacherDashboard}/profile',
      onLogout: () => confirmLogout(context, ref),
      items: [
        item(Icons.home_outlined, 'Home', '', ''),
        item(Icons.grade_outlined, 'Grades', '/grades', '/grades',
            showBadge: hasGradeBadge,
            onTapSideEffect: () => ref.read(teacherGradeBadgeNotifier.notifier).markSeen()),
        item(Icons.quiz_outlined, 'Tests', '/tests', '/tests'),
        item(Icons.how_to_reg_outlined, 'Attendance', '/attendance', '/attendance'),
        item(Icons.calendar_month_outlined, 'Timetable', '/timetable', '/timetable'),
        item(Icons.assignment_outlined, 'Homework', '/homework', '/homework'),
        item(Icons.campaign_outlined, 'Broadcasts', '/broadcasts', '/broadcasts',
            showBadge: hasBroadcastBadge,
            onTapSideEffect: () => ref.read(teacherBroadcastBadgeNotifier.notifier).markSeen()),
        item(Icons.storage_outlined, 'Database', '/database', '/database'),
        item(Icons.slideshow_outlined, 'Presentations', '/presentations', '/presentations'),
      ],
    );
  }
}

