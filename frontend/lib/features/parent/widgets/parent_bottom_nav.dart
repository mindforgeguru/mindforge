import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/badge_dot.dart';
import '../providers/parent_provider.dart';

class ParentBottomNav extends ConsumerWidget {
  const ParentBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Test badge on Grades: new tests created for child since last visit
    final lastSeenTest = ref.watch(parentTestBadgeNotifier);
    final testsAsync = ref.watch(parentChildTestsProvider);
    final hasTestBadge = testsAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list
            .map((t) => t.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return _isNew(lastSeenTest, latest);
      },
      orElse: () => false,
    );

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
        child: LayoutBuilder(builder: (context, constraints) {
          final sw = constraints.maxWidth;
          final vPad = (sw * 0.018).clamp(6.0, 10.0);
          return Padding(
            padding: EdgeInsets.symmetric(vertical: vPad),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: () => context.go(RouteNames.parentDashboard),
                ),
                _NavItem(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Attendance',
                  onTap: () =>
                      context.go('${RouteNames.parentDashboard}/attendance'),
                ),
                _NavItem(
                  icon: Icons.calendar_today_outlined,
                  label: 'Timetable',
                  onTap: () =>
                      context.go('${RouteNames.parentDashboard}/timetable'),
                ),
                _NavItem(
                  icon: Icons.grade_outlined,
                  label: 'Grades',
                  showBadge: hasTestBadge,
                  onTap: () {
                    ref.read(parentTestBadgeNotifier.notifier).markSeen();
                    context.go('${RouteNames.parentDashboard}/grades');
                  },
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Fees',
                  onTap: () =>
                      context.go('${RouteNames.parentDashboard}/fees'),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showBadge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final currentPath = GoRouterState.of(context).uri.toString();
    final active = _isActivePath(currentPath);
    final color = active ? AppColors.accent : AppColors.primary;

    final iconSz = (sw * 0.054).clamp(19.0, 25.0);
    final fontSize = (sw * 0.024).clamp(8.5, 11.0);
    final hPad = (sw * 0.008).clamp(2.0, 6.0);
    final vPad = (sw * 0.010).clamp(4.0, 8.0);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeDot(
                show: showBadge,
                child: Icon(icon, size: iconSz, color: color),
              ),
              SizedBox(height: (sw * 0.008).clamp(2.0, 4.0)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isActivePath(String path) {
    switch (label) {
      case 'Home':
        return path == RouteNames.parentDashboard ||
            path == '${RouteNames.parentDashboard}/';
      case 'Attendance':
        return path.contains('/attendance');
      case 'Timetable':
        return path.contains('/timetable');
      case 'Grades':
        return path.contains('/grades');
      case 'Fees':
        return path.contains('/fees');
      default:
        return false;
    }
  }
}

bool _isNew(DateTime? lastSeen, DateTime? latest) {
  if (latest == null) return false;
  if (lastSeen == null) return true;
  return latest.isAfter(lastSeen);
}
