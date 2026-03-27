import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/badge_dot.dart';
import '../providers/teacher_provider.dart';

class TeacherBottomNav extends ConsumerWidget {
  const TeacherBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Grade badge: new offline grade entries since last visit to Tests screen
    final lastSeenGrade = ref.watch(teacherGradeBadgeNotifier);
    final gradesAsync = ref.watch(teacherGradesProvider((null, null)));
    final hasGradeBadge = gradesAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list
            .map((g) => g.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return _isNew(lastSeenGrade, latest);
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
          final vPad = (sw * 0.015).clamp(5.0, 9.0);
          return Padding(
            padding: EdgeInsets.symmetric(vertical: vPad),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: () => context.go(RouteNames.teacherDashboard),
                ),
                _NavItem(
                  icon: Icons.grade_outlined,
                  label: 'Grades',
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/grades'),
                ),
                _NavItem(
                  icon: Icons.quiz_outlined,
                  label: 'Tests',
                  showBadge: hasGradeBadge,
                  onTap: () {
                    ref
                        .read(teacherGradeBadgeNotifier.notifier)
                        .markSeen();
                    context.go('${RouteNames.teacherDashboard}/tests');
                  },
                ),
                _NavItem(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Attendance',
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/attendance'),
                ),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Timetable',
                  onTap: () =>
                      context.go('${RouteNames.teacherDashboard}/timetable'),
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

    final iconSz = (sw * 0.050).clamp(18.0, 23.0);
    final fontSize = (sw * 0.022).clamp(8.0, 10.5);
    final hPad = (sw * 0.006).clamp(2.0, 5.0);
    final vPad = (sw * 0.010).clamp(3.0, 7.0);

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
              SizedBox(height: (sw * 0.007).clamp(2.0, 4.0)),
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
        return path == RouteNames.teacherDashboard ||
            path == '${RouteNames.teacherDashboard}/';
      case 'Grades':
        return path.contains('/grades');
      case 'Tests':
        return path.contains('/tests');
      case 'Attendance':
        return path.contains('/attendance');
      case 'Timetable':
        return path.contains('/timetable');
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
