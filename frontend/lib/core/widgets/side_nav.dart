import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Width of the fixed vertical sidebar shown on wide (web/desktop) layouts.
const double kSideNavWidth = 224;

/// A single entry in the [SideNav].
class SideNavItem {
  final IconData icon;
  final String label;
  final String route;
  final bool isActive;

  /// Shows a small red dot on the tile (e.g. new grades/broadcasts).
  final bool showBadge;

  /// Optional side effect to run before navigating (e.g. mark-seen).
  final VoidCallback? onTapSideEffect;

  const SideNavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.isActive,
    this.showBadge = false,
    this.onTapSideEffect,
  });
}

/// Fixed vertical navigation sidebar used on wide (web/desktop) layouts.
///
/// Replaces the old horizontal top nav: brand/logos pinned at the top, a
/// scrollable list of nav items in the middle, and the profile avatar +
/// actions (report a problem, logout) pinned at the bottom. Shared across all
/// roles — each role just builds its own [items] list.
class SideNav extends StatelessWidget {
  final List<SideNavItem> items;
  final String username;
  final String profileRoute;
  final VoidCallback onLogout;

  /// When non-null, renders a "report a problem" action in the footer.
  final VoidCallback? onReportProblem;

  const SideNav({
    super.key,
    required this.items,
    required this.username,
    required this.profileRoute,
    required this.onLogout,
    this.onReportProblem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSideNavWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1F35), Color(0xFF1D3557)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(3, 0)),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            _header(),
            const SizedBox(height: 18),
            const Divider(color: Colors.white24, height: 1, indent: 16, endIndent: 16),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [for (final item in items) _tile(context, item)],
                ),
              ),
            ),
            const Divider(color: Colors.white24, height: 1, indent: 16, endIndent: 16),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _logoBox('assets/images/hansal_logo.png', 8, 84),
          const SizedBox(height: 12),
          _logoBox('assets/images/logo.png', 10, 84),
          const SizedBox(height: 14),
          Text(
            'MIND FORGE',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBox(String asset, double pad, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      padding: EdgeInsets.all(pad),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }

  Widget _tile(BuildContext context, SideNavItem item) {
    final color = item.isActive ? Colors.white : Colors.white.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: item.isActive ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            item.onTapSideEffect?.call();
            context.go(item.route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: item.isActive ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (item.showBadge)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go(profileRoute),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  (username.isNotEmpty ? username[0] : '?').toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.go(profileRoute),
              child: Text(
                username.isNotEmpty ? username : 'Profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (onReportProblem != null)
            Tooltip(
              message: 'Report a problem',
              child: IconButton(
                onPressed: onReportProblem,
                icon: Icon(Icons.bug_report_outlined, size: 18, color: Colors.white.withValues(alpha: 0.65)),
                splashRadius: 18,
              ),
            ),
          Tooltip(
            message: 'Logout',
            child: IconButton(
              onPressed: onLogout,
              icon: Icon(Icons.logout_rounded, size: 18, color: Colors.white.withValues(alpha: 0.65)),
              splashRadius: 18,
            ),
          ),
        ],
      ),
    );
  }
}
