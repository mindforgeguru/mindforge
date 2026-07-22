import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/admin_provider.dart';

/// The admin's one-time school-setup workflow, drawn as a graphical "road" that
/// mirrors the teacher dashboard's Today's Workflow card. Four milestones must
/// be completed in strict order — Academic Year → Timetable → Fee Details →
/// Bank / Payment — with a car parked at the current step. Completed steps are
/// green and tappable (to edit); the current step is the car; future steps are
/// locked and not tappable ("no skipping"). Once every step is done the card
/// stays pinned to the dashboard so any task can still be edited.
class SetupRoadCard extends StatelessWidget {
  final AdminSetupStatus status;
  const SetupRoadCard({super.key, required this.status});

  static const _doneColor = Color(0xFF22C55E); // green
  static const _currentColor = Color(0xFFF59E0B); // amber
  static const _lockedColor = AppColors.textMuted;

  static const _labels = <String>[
    'Academic Year',
    'Timetable',
    'Fee Details',
    'Bank / Payment',
  ];

  void _goto(BuildContext context, int i) {
    switch (i) {
      case 0:
        context.go('${RouteNames.adminDashboard}/academic-year');
        break;
      case 1:
        context.go('${RouteNames.adminDashboard}/timetable');
        break;
      case 2:
        context.go('${RouteNames.adminDashboard}/fees');
        break;
      case 3:
        // Deep-link straight to the Payment Info tab.
        context.go('${RouteNames.adminDashboard}/fees?tab=2');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = status.currentStep;
    final complete = status.allComplete;

    final steps = <_SetupStep>[
      for (var i = 0; i < _labels.length; i++)
        _SetupStep(
          label: _labels[i],
          done: status.steps[i],
          // Completed steps and the current step are actionable; future steps
          // are locked until their predecessor is finished.
          enabled: i <= current,
          onTap: i <= current ? () => _goto(context, i) : null,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : Icons.flag_rounded,
                  size: 18,
                  color: complete ? _doneColor : AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'School Setup',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              complete
                  ? 'Setup complete — tap any step to edit.'
                  : 'Finish these steps in order to open the dashboard.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 84,
              child: _SetupRoad(
                steps: steps,
                currentIdx: current,
                doneColor: _doneColor,
                currentColor: _currentColor,
                lockedColor: _lockedColor,
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            const Row(
              children: [
                _LegendDot(color: _doneColor, label: 'Done'),
                SizedBox(width: 14),
                _LegendDot(color: _currentColor, label: 'Current'),
                SizedBox(width: 14),
                _LegendDot(color: _lockedColor, label: 'Locked'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupStep {
  final String label;
  final bool done;
  final bool enabled;
  final VoidCallback? onTap;
  const _SetupStep({
    required this.label,
    required this.done,
    required this.enabled,
    required this.onTap,
  });
}

class _SetupRoad extends StatelessWidget {
  final List<_SetupStep> steps;
  final int currentIdx;
  final Color doneColor;
  final Color currentColor;
  final Color lockedColor;
  const _SetupRoad({
    required this.steps,
    required this.currentIdx,
    required this.doneColor,
    required this.currentColor,
    required this.lockedColor,
  });

  @override
  Widget build(BuildContext context) {
    final n = steps.length;

    return LayoutBuilder(builder: (context, constraints) {
      const radius = 12.0;
      const carRadius = 16.0;
      const labelHeight = 20.0;
      const labelWidth = 84.0;
      const leftPad = 40.0;
      const rightPad = 40.0;
      final width = constraints.maxWidth;
      final innerWidth =
          (width - leftPad - rightPad).clamp(1.0, double.infinity);
      double xAt(int i) => leftPad + innerWidth * i / (n - 1);
      final centerY = constraints.maxHeight / 2;

      // Solid line covers every pixel the car has driven over: from the start
      // to the car's position (or the final milestone once all steps are done).
      double doneEndX;
      if (currentIdx <= 0) {
        doneEndX = leftPad;
      } else if (currentIdx >= n) {
        doneEndX = xAt(n - 1);
      } else {
        doneEndX = xAt(currentIdx);
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RoadPainter(
                color: doneColor,
                pendingColor: AppColors.divider,
                startX: leftPad,
                doneEndX: doneEndX,
                allEndX: xAt(n - 1),
                centerY: centerY,
              ),
            ),
          ),
          for (var i = 0; i < n; i++) ...[
            if (i == currentIdx)
              // Current step → tappable car.
              Positioned(
                left: xAt(i) - carRadius,
                top: centerY - carRadius,
                child: GestureDetector(
                  onTap: steps[i].onTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: carRadius * 2,
                    height: carRadius * 2,
                    child: Center(
                      child: Icon(
                        Icons.directions_car_rounded,
                        size: 26,
                        color: currentColor,
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: xAt(i) - radius,
                top: centerY - radius,
                child: GestureDetector(
                  onTap: steps[i].onTap,
                  behavior: HitTestBehavior.opaque,
                  child: _Milestone(
                    step: steps[i],
                    doneColor: doneColor,
                    lockedColor: lockedColor,
                    radius: radius,
                  ),
                ),
              ),
            // Label alternates above/below to avoid crowding.
            Positioned(
              left: xAt(i) - labelWidth / 2,
              width: labelWidth,
              top: i.isEven
                  ? centerY - radius - labelHeight - 2
                  : centerY + radius + 4,
              child: GestureDetector(
                onTap: steps[i].onTap,
                child: Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: steps[i].enabled
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Milestone extends StatelessWidget {
  final _SetupStep step;
  final Color doneColor;
  final Color lockedColor;
  final double radius;
  const _Milestone({
    required this.step,
    required this.doneColor,
    required this.lockedColor,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final fill = step.done ? doneColor : lockedColor;
    return Opacity(
      opacity: step.enabled || step.done ? 1 : 0.7,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: fill.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          step.done ? Icons.check_rounded : Icons.lock_rounded,
          size: 13,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  final Color color;
  final Color pendingColor;
  final double startX;
  final double doneEndX;
  final double allEndX;
  final double centerY;
  _RoadPainter({
    required this.color,
    required this.pendingColor,
    required this.startX,
    required this.doneEndX,
    required this.allEndX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final solidPaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dashPaint = Paint()
      ..color = pendingColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (doneEndX > startX) {
      canvas.drawLine(
          Offset(startX, centerY), Offset(doneEndX, centerY), solidPaint);
    }
    const dashLen = 6.0;
    const gapLen = 4.0;
    var x = doneEndX;
    while (x < allEndX) {
      final next = (x + dashLen).clamp(x, allEndX);
      canvas.drawLine(Offset(x, centerY), Offset(next, centerY), dashPaint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.doneEndX != doneEndX ||
      old.allEndX != allEndX ||
      old.startX != startX ||
      old.centerY != centerY ||
      old.color != color ||
      old.pendingColor != pendingColor;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
