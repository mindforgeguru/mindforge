import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../auth/providers/auth_provider.dart';
import 'admin_bottom_nav.dart';

/// Responsive scaffold for admin screens.
/// On wide screens (≥ 900 px) shows the dark top nav and hides the bottom nav.
/// On mobile shows the existing bottom nav — no change to mobile behaviour.
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

  const AdminScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.showMobileBottomNav = true,
    this.resizeToAvoidBottomInset,
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
    // capped at 600 px and centred so they don't stretch on desktop.
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Column(
        children: [
          AdminTopNav(auth: auth),
          Expanded(
            child: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: body,
                ),
              ),
              backgroundColor: backgroundColor ?? const Color(0xFFF0F4F8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Admin top navigation bar ────────────────────────────────────────────────

class AdminTopNav extends ConsumerWidget {
  final AuthState auth;
  const AdminTopNav({super.key, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
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
            const SizedBox(width: 32),
            // Nav links
            ..._navItems(context, currentPath),
            const Spacer(),
            // Profile avatar
            GestureDetector(
              onTap: () => context.go('${RouteNames.adminDashboard}/profile'),
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    (auth.username ?? 'A').substring(0, 1).toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Logout
            Tooltip(
              message: 'Logout',
              child: IconButton(
                onPressed: () => confirmLogout(context, ref),
                icon: Icon(Icons.logout_rounded, size: 18, color: Colors.white.withOpacity(0.65)),
                splashRadius: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _navItems(BuildContext context, String currentPath) {
    final items = [
      ('Home',          RouteNames.adminDashboard,                       RouteNames.adminDashboard),
      ('Users',         '${RouteNames.adminDashboard}/users',            '/users'),
      ('Fees',          '${RouteNames.adminDashboard}/fees',             '/fees'),
      ('Reports',       '${RouteNames.adminDashboard}/reports',          '/reports'),
      ('Feedback',      '${RouteNames.adminDashboard}/feedback',         '/feedback'),
      ('Timetable',     '${RouteNames.adminDashboard}/timetable',        '/timetable'),
      ('Academic Year', '${RouteNames.adminDashboard}/academic-year',    '/academic-year'),
    ];

    return items.map((item) {
      final label = item.$1;
      final route = item.$2;
      final match = item.$3;
      final isActive = label == 'Home'
          ? (currentPath == RouteNames.adminDashboard)
          : currentPath.contains(match);

      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: TextButton(
          onPressed: () => context.go(route),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            backgroundColor: isActive ? Colors.white.withOpacity(0.15) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.65),
            ),
          ),
        ),
      );
    }).toList();
  }
}
