import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/badge_dot.dart';
import '../providers/student_provider.dart';

class StudentBottomNav extends ConsumerWidget {
  const StudentBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Test badge: new tests created since last visit
    final lastSeenTest = ref.watch(studentTestBadgeNotifier);
    final pendingAsync = ref.watch(pendingTestsProvider);
    final offlineAsync = ref.watch(offlineTestsProvider);
    final hasTestBadge = _hasNew(lastSeenTest, [pendingAsync, offlineAsync]);

    // Grade badge: new offline grades since last visit
    final lastSeenGrade = ref.watch(studentGradeBadgeNotifier);
    final gradeAsync = ref.watch(studentOfflineGradesProvider(null));
    final hasGradeBadge = gradeAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list
            .map((g) => g.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return _isNew(lastSeenGrade, latest);
      },
      orElse: () => false,
    );

    final showTestsBadge = hasTestBadge || hasGradeBadge;

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
                  onTap: () => context.go(RouteNames.studentDashboard),
                ),
                _NavItem(
                  icon: Icons.grade_outlined,
                  label: 'Grades',
                  onTap: () =>
                      context.go('${RouteNames.studentDashboard}/grades'),
                ),
                _NavItem(
                  icon: Icons.quiz_outlined,
                  label: 'Tests',
                  showBadge: showTestsBadge,
                  onTap: () {
                    ref.read(studentTestBadgeNotifier.notifier).markSeen();
                    ref.read(studentGradeBadgeNotifier.notifier).markSeen();
                    context.go('${RouteNames.studentDashboard}/tests');
                  },
                ),
                _NavItem(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Attendance',
                  onTap: () =>
                      context.go('${RouteNames.studentDashboard}/attendance'),
                ),
                _NavItem(
                  icon: Icons.assignment_outlined,
                  label: 'Homework',
                  onTap: () =>
                      context.go('${RouteNames.studentDashboard}/homework'),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  bool _hasNew(DateTime? lastSeen, List<dynamic> asyncValues) {
    for (final dynamic item in asyncValues) {
      final list = (item as AsyncValue).value as List?;
      if (list == null || list.isEmpty) continue;
      try {
        final latest = list
            .map((e) => (e as dynamic).createdAt as DateTime)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (_isNew(lastSeen, latest)) return true;
      } catch (_) {}
    }
    return false;
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
    final currentPath = GoRouterState.of(context).uri.toString();
    final isActive = _isActivePath(currentPath);
    final color = isActive ? AppColors.accent : AppColors.primary;

    final sw = MediaQuery.of(context).size.width;
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
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
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
        return path == RouteNames.studentDashboard ||
            path == '${RouteNames.studentDashboard}/';
      case 'Grades':
        return path.contains('/grades');
      case 'Tests':
        return path.contains('/tests');
      case 'Attendance':
        return path.contains('/attendance');
      case 'Homework':
        return path.contains('/homework');
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
