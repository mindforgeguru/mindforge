import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';

class AdminBottomNav extends StatelessWidget {
  const AdminBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x181D3557),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_outlined, label: 'Home',
                  onTap: () => context.go(RouteNames.adminDashboard)),
              _NavItem(icon: Icons.people_outlined, label: 'Users',
                  onTap: () => context.go('${RouteNames.adminDashboard}/users')),
              _NavItem(icon: Icons.account_balance_wallet_outlined, label: 'Fees',
                  onTap: () => context.go('${RouteNames.adminDashboard}/fees')),
              _NavItem(icon: Icons.bar_chart_outlined, label: 'Reports',
                  onTap: () => context.go('${RouteNames.adminDashboard}/reports')),
              _NavItem(icon: Icons.calendar_month_outlined, label: 'Timetable',
                  onTap: () => context.go('${RouteNames.adminDashboard}/timetable')),
              _NavItem(icon: Icons.person_outline_rounded, label: 'Profile',
                  onTap: () => context.go('${RouteNames.adminDashboard}/profile')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _NavItem({
    super.key, 
    required this.icon, 
    required this.label, 
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.toString();
    final active = isActive || _isActivePath(currentPath);
    final color = active ? AppColors.accent : AppColors.primary;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: R.sp(context, 10), vertical: R.sp(context, 6, min: 6, max: 8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: R.fluid(context, 24, min: 22, max: 26), color: color),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: R.fs(context, 10, min: 9, max: 12),
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  bool _isActivePath(String path) {
    switch (label) {
      case 'Home':
        return path == RouteNames.adminDashboard ||
            path == '${RouteNames.adminDashboard}/';
      case 'Users':
        return path.contains('/users');
      case 'Fees':
        return path.contains('/fees');
      case 'Reports':
        return path.contains('/reports');
      case 'Timetable':
        return path.contains('/timetable');
      case 'Profile':
        return path.contains('/profile');
      default:
        return false;
    }
  }
}
