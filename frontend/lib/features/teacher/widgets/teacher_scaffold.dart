import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import 'teacher_bottom_nav.dart';

/// Responsive scaffold for teacher screens.
/// On wide screens (≥ 900 px) shows a left side-nav.
/// On mobile shows the existing bottom nav — no change to mobile behaviour.
class TeacherScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;

  const TeacherScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
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

    // ── Web: side nav + content ────────────────────────────────────────────
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          const _TeacherSideNav(),
          Expanded(
            // Fresh Navigator scope so inner Scaffold has no back-route
            // and therefore shows no back button in the AppBar.
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: appBar,
                  body: body,
                  floatingActionButton: floatingActionButton,
                  floatingActionButtonLocation: floatingActionButtonLocation,
                  backgroundColor: backgroundColor ?? AppColors.background,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Side navigation panel ─────────────────────────────────────────────────────

class _TeacherSideNav extends ConsumerWidget {
  const _TeacherSideNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final currentPath = GoRouterState.of(context).uri.toString();

    // Badge: grade activity
    final lastSeenGrade = ref.watch(teacherGradeBadgeNotifier);
    final gradesAsync = ref.watch(teacherGradesProvider((null, null)));
    final hasGradeBadge = gradesAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list
            .map((g) => g.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return lastSeenGrade == null || latest.isAfter(lastSeenGrade);
      },
      orElse: () => false,
    );

    // Badge: broadcasts
    final lastSeenBroadcast = ref.watch(teacherBroadcastBadgeNotifier);
    final broadcastsAsync = ref.watch(teacherBroadcastsProvider);
    final hasBroadcastBadge = broadcastsAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list
            .map((b) => b.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return lastSeenBroadcast == null || latest.isAfter(lastSeenBroadcast);
      },
      orElse: () => false,
    );

    return Container(
      width: 230,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F1F35), Color(0xFF1D3557)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 16,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Logo header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Image.asset('assets/images/logo.png',
                      fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MIND FORGE',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Teacher Portal',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // ── Nav items ─────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _SideNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  active: currentPath == RouteNames.teacherDashboard ||
                      currentPath == '${RouteNames.teacherDashboard}/',
                  onTap: () => context.go(RouteNames.teacherDashboard),
                ),
                _SideNavItem(
                  icon: Icons.grade_outlined,
                  activeIcon: Icons.grade_rounded,
                  label: 'Grades',
                  active: currentPath.contains('/grades'),
                  showBadge: hasGradeBadge,
                  onTap: () {
                    ref.read(teacherGradeBadgeNotifier.notifier).markSeen();
                    context.go('${RouteNames.teacherDashboard}/grades');
                  },
                ),
                _SideNavItem(
                  icon: Icons.quiz_outlined,
                  activeIcon: Icons.quiz_rounded,
                  label: 'Tests',
                  active: currentPath.contains('/tests'),
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/tests'),
                ),
                _SideNavItem(
                  icon: Icons.how_to_reg_outlined,
                  activeIcon: Icons.how_to_reg_rounded,
                  label: 'Attendance',
                  active: currentPath.contains('/attendance'),
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/attendance'),
                ),
                _SideNavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month_rounded,
                  label: 'Timetable',
                  active: currentPath.contains('/timetable'),
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/timetable'),
                ),
                _SideNavItem(
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment_rounded,
                  label: 'Homework',
                  active: currentPath.contains('/homework'),
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/homework'),
                ),
                _SideNavItem(
                  icon: Icons.campaign_outlined,
                  activeIcon: Icons.campaign_rounded,
                  label: 'Broadcasts',
                  active: currentPath.contains('/broadcasts'),
                  showBadge: hasBroadcastBadge,
                  onTap: () {
                    ref
                        .read(teacherBroadcastBadgeNotifier.notifier)
                        .markSeen();
                    context
                        .go('${RouteNames.teacherDashboard}/broadcasts');
                  },
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── User + profile + logout ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile link
                _SideNavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  active: currentPath.contains('/profile'),
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/profile'),
                ),
                const SizedBox(height: 8),
                // User info row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.accent.withOpacity(0.25),
                      child: Text(
                        (auth.username ?? 'T').substring(0, 1).toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentLight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        auth.username ?? 'Teacher',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Consumer(builder: (context, ref, _) {
                      return GestureDetector(
                        onTap: () => confirmLogout(context, ref),
                        child: Tooltip(
                          message: 'Logout',
                          child: Icon(Icons.logout_rounded,
                              size: 18,
                              color: Colors.white.withOpacity(0.45)),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single side nav item ──────────────────────────────────────────────────────

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final bool showBadge;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withOpacity(0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: active
                  ? Border.all(
                      color: AppColors.accent.withOpacity(0.35), width: 1)
                  : null,
            ),
            child: Row(
              children: [
                BadgeDot(
                  show: showBadge,
                  child: Icon(
                    active ? activeIcon : icon,
                    size: 19,
                    color: active
                        ? AppColors.accentLight
                        : Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w400,
                    color: active
                        ? Colors.white
                        : Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
