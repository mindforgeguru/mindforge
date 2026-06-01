import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../../core/widgets/report_problem_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import 'teacher_bottom_nav.dart';

/// Responsive scaffold for teacher screens.
/// On wide screens (≥ 900 px) shows the dark top nav and hides the bottom nav.
/// On mobile shows the existing bottom nav — no change to mobile behaviour.
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

    // ── Web: top nav + content ─────────────────────────────────────────────
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
      body: Column(
        children: [
          TeacherTopNav(auth: auth),
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

// ─── Teacher top navigation bar ───────────────────────────────────────────────

class TeacherTopNav extends ConsumerWidget {
  final AuthState auth;
  const TeacherTopNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    // Badges: grades and broadcasts pulse a small dot in the top nav when
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

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1F35), Color(0xFF1D3557)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            // Hansal logo
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/hansal_logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 8),
            // MindForge logo
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            Text(
              'MIND FORGE',
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 24),
            // Nav links (horizontally scrollable in case the window is narrow)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _navItems(context, ref, currentPath,
                      hasGradeBadge: hasGradeBadge,
                      hasBroadcastBadge: hasBroadcastBadge),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Profile avatar
            GestureDetector(
              onTap: () => context.go('${RouteNames.teacherDashboard}/profile'),
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    (auth.username ?? 'T').substring(0, 1).toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Report a problem',
              child: IconButton(
                onPressed: () => showReportProblemDialog(context, ref),
                icon: Icon(Icons.bug_report_outlined, size: 18, color: Colors.white.withValues(alpha: 0.65)),
                splashRadius: 18,
              ),
            ),
            Tooltip(
              message: 'Logout',
              child: IconButton(
                onPressed: () => confirmLogout(context, ref),
                icon: Icon(Icons.logout_rounded, size: 18, color: Colors.white.withValues(alpha: 0.65)),
                splashRadius: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _navItems(BuildContext context, WidgetRef ref, String currentPath,
      {required bool hasGradeBadge, required bool hasBroadcastBadge}) {
    // (label, route, path-substring-for-active-check, optional-badge,
    //  optional-onTap-side-effect)
    final items = <(String, String, String, bool, VoidCallback?)>[
      ('Home', RouteNames.teacherDashboard, RouteNames.teacherDashboard, false, null),
      ('Grades', '${RouteNames.teacherDashboard}/grades', '/grades', hasGradeBadge,
          () => ref.read(teacherGradeBadgeNotifier.notifier).markSeen()),
      ('Tests', '${RouteNames.teacherDashboard}/tests', '/tests', false, null),
      ('Attendance', '${RouteNames.teacherDashboard}/attendance', '/attendance', false, null),
      ('Timetable', '${RouteNames.teacherDashboard}/timetable', '/timetable', false, null),
      ('Homework', '${RouteNames.teacherDashboard}/homework', '/homework', false, null),
      ('Broadcasts', '${RouteNames.teacherDashboard}/broadcasts', '/broadcasts', hasBroadcastBadge,
          () => ref.read(teacherBroadcastBadgeNotifier.notifier).markSeen()),
      ('Database', '${RouteNames.teacherDashboard}/database', '/database', false, null),
      ('Presentations', '${RouteNames.teacherDashboard}/presentations', '/presentations', false, null),
    ];

    return items.map((item) {
      final label = item.$1;
      final route = item.$2;
      final match = item.$3;
      final hasBadge = item.$4;
      final sideEffect = item.$5;
      final isActive = label == 'Home'
          ? (currentPath == RouteNames.teacherDashboard ||
              currentPath == '${RouteNames.teacherDashboard}/')
          : currentPath.contains(match);

      final btn = TextButton(
        onPressed: () {
          sideEffect?.call();
          context.go(route);
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          backgroundColor: isActive ? Colors.white.withValues(alpha: 0.15) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.65),
          ),
        ),
      );

      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            btn,
            if (hasBadge)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }
}

