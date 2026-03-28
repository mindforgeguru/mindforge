import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/attendance.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_bottom_nav.dart';
import '../widgets/parent_error_widget.dart';

// ─── Responsive helpers ───────────────────────────────────────────────────────
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.7 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 8, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class ParentAttendanceScreen extends ConsumerStatefulWidget {
  const ParentAttendanceScreen({super.key});

  @override
  ConsumerState<ParentAttendanceScreen> createState() =>
      _ParentAttendanceScreenState();
}

class _ParentAttendanceScreenState
    extends ConsumerState<ParentAttendanceScreen> {
  late DateTime _displayMonth;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(parentChildAttendanceProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _prevMonth() => setState(() =>
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1));

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_displayMonth.year, _displayMonth.month + 1);
    if (next.isBefore(DateTime(now.year, now.month + 1))) {
      setState(() => _displayMonth = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(parentChildAttendanceProvider);
    final now = DateTime.now();
    final isCurrentMonth =
        _displayMonth.year == now.year && _displayMonth.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            "Child's Attendance",
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 16, min: 14, max: 20),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: AppColors.primary,
      ),
      bottomNavigationBar: const ParentBottomNav(),
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: parentErrorWidget(e)),
        data: (records) {
          final statusMap = _buildStatusMap(records);

          final monthRecords = records.where((r) =>
              r.date.year == _displayMonth.year &&
              r.date.month == _displayMonth.month).toList();

          final Set<String> presentDays = {};
          final Set<String> recordedDays = {};
          for (final r in monthRecords) {
            final key = _dateKey(r.date);
            recordedDays.add(key);
            if (r.isPresent) presentDays.add(key);
          }

          final totalDays = recordedDays.length;
          final presentCount = presentDays.length;
          final absentCount = totalDays - presentCount;
          final pct = totalDays > 0 ? (presentCount / totalDays * 100) : 0.0;
          final pctColor = pct >= 75
              ? AppColors.success
              : pct >= 50
                  ? AppColors.warning
                  : AppColors.error;

          return LayoutBuilder(builder: (context, constraints) {
            final sw = constraints.maxWidth;
            final hPad = (sw * 0.03).clamp(10.0, 16.0);
            final vPad = (sw * 0.02).clamp(6.0, 12.0);

            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(parentChildAttendanceProvider.future),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad * 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Month navigation ──────────────────────────────
                    _MonthNavigator(
                      displayMonth: _displayMonth,
                      onPrev: _prevMonth,
                      onNext: isCurrentMonth ? null : _nextMonth,
                    ),

                    SizedBox(height: (sw * 0.015).clamp(5.0, 8.0)),

                    // ── Calendar grid ─────────────────────────────────
                    Container(
                      decoration: mindForgeCardDecoration(),
                      padding: EdgeInsets.fromLTRB(
                        (sw * 0.015).clamp(4.0, 8.0),
                        (sw * 0.02).clamp(6.0, 10.0),
                        (sw * 0.015).clamp(4.0, 8.0),
                        (sw * 0.015).clamp(4.0, 8.0),
                      ),
                      child: Column(
                        children: [
                          _WeekdayRow(),
                          SizedBox(height: (sw * 0.005).clamp(2.0, 4.0)),
                          _CalendarGrid(
                            month: _displayMonth,
                            statusMap: statusMap,
                          ),
                          SizedBox(height: (sw * 0.01).clamp(3.0, 6.0)),
                          const _Legend(),
                        ],
                      ),
                    ),

                    SizedBox(height: (sw * 0.025).clamp(8.0, 14.0)),

                    // ── Monthly stats ─────────────────────────────────
                    Container(
                      decoration: mindForgeCardDecoration(),
                      padding: EdgeInsets.symmetric(
                        horizontal: (sw * 0.035).clamp(12.0, 18.0),
                        vertical: (sw * 0.03).clamp(10.0, 16.0),
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              DateFormat('MMMM yyyy').format(_displayMonth),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: _fs(context, 14, min: 12, max: 17),
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          SizedBox(height: (sw * 0.02).clamp(6.0, 10.0)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(
                                child: _StatPill(
                                  label: 'Present',
                                  value: '$presentCount',
                                  color: AppColors.success,
                                ),
                              ),
                              Expanded(
                                child: _StatPill(
                                  label: 'Absent',
                                  value: '$absentCount',
                                  color: AppColors.error,
                                ),
                              ),
                              Expanded(
                                child: _StatPill(
                                  label: 'Total Days',
                                  value: '$totalDays',
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: (sw * 0.025).clamp(8.0, 12.0)),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              backgroundColor: AppColors.divider,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(pctColor),
                              minHeight: (sw * 0.018).clamp(6.0, 10.0),
                            ),
                          ),
                          SizedBox(height: (sw * 0.015).clamp(5.0, 8.0)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              totalDays == 0
                                  ? 'No records this month'
                                  : 'Attendance: ${pct.toStringAsFixed(1)}%',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: _fs(context, 13, min: 11, max: 16),
                                color: totalDays == 0
                                    ? AppColors.textMuted
                                    : pctColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
        },
      ),
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, _DayStatus> _buildStatusMap(
      List<AttendanceModel> records) {
    final Map<String, Set<String>> dayStatuses = {};
    for (final r in records) {
      final key = _dateKey(r.date);
      dayStatuses.putIfAbsent(key, () => {}).add(r.status);
    }
    final result = <String, _DayStatus>{};
    for (final entry in dayStatuses.entries) {
      final statuses = entry.value;
      if (statuses.contains('present') && statuses.contains('absent')) {
        result[entry.key] = _DayStatus.mixed;
      } else if (statuses.contains('present')) {
        result[entry.key] = _DayStatus.present;
      } else {
        result[entry.key] = _DayStatus.absent;
      }
    }
    return result;
  }
}

enum _DayStatus { present, absent, mixed }

// ─── Month navigator ──────────────────────────────────────────────────────────

class _MonthNavigator extends StatelessWidget {
  final DateTime displayMonth;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _MonthNavigator({
    required this.displayMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final btnSize = (sw * 0.092).clamp(36.0, 48.0);
    return Row(
      children: [
        SizedBox(
          width: btnSize,
          height: btnSize,
          child: IconButton(
            icon: Icon(Icons.chevron_left,
                size: (sw * 0.055).clamp(20.0, 26.0)),
            onPressed: onPrev,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.cardBackground,
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                DateFormat('MMMM yyyy').format(displayMonth),
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 15, min: 13, max: 18),
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: btnSize,
          height: btnSize,
          child: IconButton(
            icon: Icon(Icons.chevron_right,
                size: (sw * 0.055).clamp(20.0, 26.0)),
            onPressed: onNext,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.cardBackground,
              foregroundColor:
                  onNext != null ? AppColors.primary : AppColors.textMuted,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Weekday label row ────────────────────────────────────────────────────────

class _WeekdayRow extends StatelessWidget {
  static const _labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final fs = (sw * 0.022).clamp(7.5, 10.0);
    return Row(
      children: _labels.map((d) {
        final isWeekend = d == 'Sat' || d == 'Sun';
        return Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                d,
                style: GoogleFonts.poppins(
                  fontSize: fs,
                  fontWeight: FontWeight.w600,
                  color: isWeekend
                      ? AppColors.textMuted
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Calendar grid ────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, _DayStatus> statusMap;

  const _CalendarGrid({required this.month, required this.statusMap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Each cell = 1/7 of available width, with a small gap margin
      final cellSize =
          ((constraints.maxWidth / 7) - 2).clamp(0.0, 40.0);

      final firstDay = DateTime(month.year, month.month, 1);
      final startOffset = firstDay.weekday % 7;
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      final today = DateTime.now();
      final totalCells = (startOffset + daysInMonth + 6) ~/ 7 * 7;

      final rows = <Widget>[];
      for (int week = 0; week < totalCells ~/ 7; week++) {
        final cells = <Widget>[];
        for (int col = 0; col < 7; col++) {
          final cellIndex = week * 7 + col;
          final dayNum = cellIndex - startOffset + 1;

          if (dayNum < 1 || dayNum > daysInMonth) {
            cells.add(Expanded(child: SizedBox(height: cellSize)));
            continue;
          }

          final date = DateTime(month.year, month.month, dayNum);
          final key =
              '${month.year}-${month.month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
          final status = statusMap[key];
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
          final isFuture = date.isAfter(today);

          cells.add(Expanded(
            child: _DayCell(
              dayNum: dayNum,
              status: status,
              isToday: isToday,
              isFuture: isFuture,
              cellSize: cellSize,
            ),
          ));
        }
        rows.add(Row(children: cells));
        if (week < totalCells ~/ 7 - 1) {
          rows.add(SizedBox(height: (cellSize * 0.06).clamp(1.0, 3.0)));
        }
      }

      return Column(children: rows);
    });
  }
}

// ─── Single day cell ──────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int dayNum;
  final _DayStatus? status;
  final bool isToday;
  final bool isFuture;
  final double cellSize;

  const _DayCell({
    required this.dayNum,
    required this.status,
    required this.isToday,
    required this.isFuture,
    required this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    Color? bgColor;
    Color textColor = AppColors.textSecondary;
    FontWeight fontWeight = FontWeight.normal;

    if (!isFuture && status != null) {
      switch (status!) {
        case _DayStatus.present:
          bgColor = AppColors.success;
          textColor = Colors.white;
          fontWeight = FontWeight.bold;
        case _DayStatus.absent:
          bgColor = AppColors.error;
          textColor = Colors.white;
          fontWeight = FontWeight.bold;
        case _DayStatus.mixed:
          bgColor = AppColors.warning;
          textColor = Colors.white;
          fontWeight = FontWeight.bold;
      }
    }

    // Font scales with cell size, always fits
    final fontSize = (cellSize * 0.34).clamp(8.0, 13.0);

    return Container(
      margin: EdgeInsets.all((cellSize * 0.04).clamp(0.5, 2.0)),
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        color: bgColor?.withValues(alpha: isToday ? 1.0 : 0.85),
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(
                color: bgColor ?? AppColors.primary,
                width: (cellSize * 0.06).clamp(1.5, 2.5),
              )
            : null,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$dayNum',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: isToday ? FontWeight.bold : fontWeight,
              color: isFuture
                  ? AppColors.textMuted.withValues(alpha: 0.4)
                  : (bgColor != null ? textColor : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final gap = (sw * 0.035).clamp(10.0, 18.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _LegendDot(color: AppColors.success, label: 'Present'),
        SizedBox(width: gap),
        const _LegendDot(color: AppColors.error, label: 'Absent'),
        SizedBox(width: gap),
        const _LegendDot(color: AppColors.warning, label: 'Partial'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final dotSize = (sw * 0.025).clamp(8.0, 12.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: (sw * 0.01).clamp(3.0, 6.0)),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: _fs(context, 10, min: 8.5, max: 12),
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── Stat pill ────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 22, min: 16, max: 28),
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        SizedBox(height: (MediaQuery.of(context).size.width * 0.005).clamp(2.0, 4.0)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 10, min: 8.5, max: 13),
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
