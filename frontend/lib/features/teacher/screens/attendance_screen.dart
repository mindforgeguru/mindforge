import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ── Attendance Calendar Dialog ─────────────────────────────────────────────

/// Shows a custom monthly calendar that highlights days with attendance records.
Future<DateTime?> showAttendanceCalendar({
  required BuildContext context,
  required DateTime initialDate,
  required int grade,
}) async {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _AttendanceCalendarDialog(
      initialDate: initialDate,
      grade: grade,
    ),
  );
}

class _AttendanceCalendarDialog extends ConsumerStatefulWidget {
  final DateTime initialDate;
  final int grade;

  const _AttendanceCalendarDialog({
    required this.initialDate,
    required this.grade,
  });

  @override
  ConsumerState<_AttendanceCalendarDialog> createState() =>
      _AttendanceCalendarDialogState();
}

class _AttendanceCalendarDialogState
    extends ConsumerState<_AttendanceCalendarDialog> {
  late DateTime _displayMonth;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _displayMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_displayMonth);

  void _prevMonth() => setState(() =>
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1));

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_displayMonth.year, _displayMonth.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() => _displayMonth = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datesAsync = ref.watch(
      teacherAttendanceDatesProvider((widget.grade, _monthKey)),
    );
    final markedDates = datesAsync.valueOrNull?.toSet() ?? {};
    final today = DateTime.now();
    final isCurrentMonth = _displayMonth.year == today.year &&
        _displayMonth.month == today.month;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_s(context, 20, min: 14, max: 24))),
      child: LayoutBuilder(builder: (context, constraints) {
        final sw = constraints.maxWidth;
        final pad = (sw * 0.06).clamp(14.0, 22.0);
        final btnSz = (sw * 0.092).clamp(36.0, 48.0);
        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Select Date',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: _fs(context, 16, min: 14, max: 18),
                      color: AppColors.primary),
                ),
              ),
              SizedBox(height: _s(context, 4, min: 3, max: 6)),
              Text(
                'Grade ${widget.grade}',
                style: GoogleFonts.poppins(
                    fontSize: _fs(context, 12, min: 10, max: 13),
                    color: AppColors.textMuted),
              ),
              SizedBox(height: _s(context, 12, min: 8, max: 16)),

              // Month navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: btnSz,
                    height: btnSz,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.chevron_left,
                          size: (sw * 0.058).clamp(20.0, 26.0)),
                      onPressed: _prevMonth,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              DateFormat('MMMM yyyy').format(_displayMonth),
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: _fs(context, 15, min: 13, max: 17),
                                  color: AppColors.primary),
                            ),
                          ),
                        ),
                        if (datesAsync.isLoading) ...[
                          SizedBox(width: _s(context, 8, min: 6, max: 10)),
                          SizedBox(
                            width: _s(context, 12, min: 10, max: 14),
                            height: _s(context, 12, min: 10, max: 14),
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: btnSz,
                    height: btnSz,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.chevron_right,
                          size: (sw * 0.058).clamp(20.0, 26.0)),
                      onPressed: isCurrentMonth ? null : _nextMonth,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: isCurrentMonth
                            ? AppColors.textMuted
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: _s(context, 8, min: 6, max: 10)),

              // Weekday labels (Sun-first)
              Row(
                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                    .map((d) => Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(d,
                                  style: GoogleFonts.poppins(
                                    fontSize: _fs(context, 11, min: 9, max: 12),
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  )),
                            ),
                          ),
                        ))
                    .toList(),
              ),

              SizedBox(height: _s(context, 6, min: 4, max: 8)),

              _buildGrid(markedDates, today),

              SizedBox(height: _s(context, 12, min: 8, max: 16)),

              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _LegendDot(color: AppColors.accent, label: 'Attendance marked'),
                  SizedBox(width: _s(context, 16, min: 10, max: 20)),
                  const _LegendDot(color: AppColors.primary, label: 'Selected'),
                ],
              ),

              SizedBox(height: _s(context, 16, min: 12, max: 20)),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: _s(context, 12, min: 10, max: 14)),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              fontSize: _fs(context, 14, min: 12, max: 15))),
                    ),
                  ),
                  SizedBox(width: _s(context, 12, min: 8, max: 16)),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: EdgeInsets.symmetric(
                            vertical: _s(context, 12, min: 10, max: 14)),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => Navigator.pop(context, _selected),
                      child: Text('Select',
                          style: GoogleFonts.poppins(
                              fontSize: _fs(context, 14, min: 12, max: 15))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildGrid(Set<String> markedDates, DateTime today) {
    final firstDay = DateTime(_displayMonth.year, _displayMonth.month, 1);
    final startOffset = firstDay.weekday % 7; // Sun=0, Mon=1…Sat=6
    final daysInMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final totalCells = ((startOffset + daysInMonth + 6) ~/ 7) * 7;

    final rows = <Widget>[];
    for (int week = 0; week < totalCells ~/ 7; week++) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final idx = week * 7 + col;
        final dayNum = idx - startOffset + 1;

        if (dayNum < 1 || dayNum > daysInMonth) {
          cells.add(Expanded(child: SizedBox(height: R.fluid(context, 38, min: 32, max: 48))));
          continue;
        }

        final date = DateTime(_displayMonth.year, _displayMonth.month, dayNum);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final isMarked = markedDates.contains(dateStr);
        final isSelected = date.year == _selected.year &&
            date.month == _selected.month &&
            date.day == _selected.day;
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
        final isFuture = date.isAfter(today);

        Color? bgColor;
        Color textColor = AppColors.textSecondary;

        if (isSelected) {
          bgColor = AppColors.primary;
          textColor = Colors.white;
        } else if (isMarked) {
          bgColor = AppColors.accent;
          textColor = Colors.white;
        }

        cells.add(Expanded(
          child: GestureDetector(
            onTap: isFuture ? null : () => setState(() => _selected = date),
            child: Container(
              margin: const EdgeInsets.all(2),
              height: R.fluid(context, 38, min: 32, max: 48),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$dayNum',
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 12, min: 10, max: 14),
                      fontWeight: isSelected || isMarked || isToday
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isFuture
                          ? AppColors.textMuted.withValues(alpha: 0.3)
                          : (bgColor != null ? textColor : AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
      }
      rows.add(Row(children: cells));
      if (week < totalCells ~/ 7 - 1) rows.add(const SizedBox(height: 2));
    }

    return Column(children: rows);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final dotSz = _s(context, 10, min: 8, max: 12);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSz,
          height: dotSz,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: _s(context, 5, min: 4, max: 7)),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: _fs(context, 11, min: 9, max: 12),
                color: AppColors.textMuted)),
      ],
    );
  }
}

class TeacherAttendanceScreen extends ConsumerStatefulWidget {
  const TeacherAttendanceScreen({super.key});

  @override
  ConsumerState<TeacherAttendanceScreen> createState() =>
      _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState
    extends ConsumerState<TeacherAttendanceScreen> {
  int _selectedGrade = 8;
  DateTime _selectedDate = DateTime.now();
  int _selectedPeriod = 1;

  // student_id → present (true) / absent (false)
  final Map<int, bool> _attendance = {};

  // Tracks which (grade, date, period) we last initialised _attendance for,
  // so we don't reset user edits on every rebuild.
  (int, String, int)? _loadedKey;

  bool _submitting = false;

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  /// Initialise _attendance from student list + any existing records.
  /// Only runs when the key (grade, date, period) changes.
  void _initAttendance(
      List<UserModel> students, List<AttendanceModel> records) {
    final key = (_selectedGrade, _dateStr, _selectedPeriod);
    if (_loadedKey == key) return;
    _loadedKey = key;

    // Default everyone to present
    final newMap = {for (final s in students) s.id: true};

    // Override with existing saved records for this specific period
    for (final r in records) {
      if (r.period == _selectedPeriod && newMap.containsKey(r.studentId)) {
        newMap[r.studentId] = r.isPresent;
      }
    }
    _attendance
      ..clear()
      ..addAll(newMap);
  }

  void _resetAll() {
    setState(() {
      for (final id in _attendance.keys) {
        _attendance[id] = true;
      }
    });
  }

  Future<void> _submit(BuildContext context, List<UserModel> students,
      {required bool isUpdate}) async {
    if (students.isEmpty) return;
    setState(() => _submitting = true);
    final api = ref.read(apiClientProvider);
    try {
      final records = students
          .map((s) => {
                'student_id': s.id,
                'grade': _selectedGrade,
                'period': _selectedPeriod,
                'date': _dateStr,
                'status': (_attendance[s.id] ?? true) ? 'present' : 'absent',
              })
          .toList();

      await api.markAttendance({
        'grade': _selectedGrade,
        'period': _selectedPeriod,
        'date': _dateStr,
        'records': records,
      });

      // Invalidate so the provider re-fetches fresh data next time
      ref.invalidate(teacherAttendanceProvider((_selectedGrade, _dateStr)));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isUpdate
                ? 'Attendance updated successfully!'
                : 'Attendance submitted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(teacherTimetableConfigProvider);
    final periodsPerDay = configAsync.valueOrNull?.periodsPerDay ?? 8;

    final studentsAsync = ref.watch(studentsInGradeProvider(_selectedGrade));
    final existingAsync = ref.watch(
        teacherAttendanceProvider((_selectedGrade, _dateStr)));

    return TeacherScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Attendance',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 18, min: 15, max: 21),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────
          _FilterBar(
            selectedGrade: _selectedGrade,
            selectedDate: _selectedDate,
            selectedPeriod: _selectedPeriod,
            periodsPerDay: periodsPerDay,
            onGradeChanged: (g) => setState(() {
              _selectedGrade = g;
              _loadedKey = null;
            }),
            onDateChanged: (d) => setState(() {
              _selectedDate = d;
              _loadedKey = null;
            }),
            onPeriodChanged: (p) => setState(() {
              _selectedPeriod = p;
              _loadedKey = null;
            }),
          ),

          // ── Content ─────────────────────────────────────────────────
          Expanded(
            child: studentsAsync.when(
              loading: () => const ShimmerList(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(studentsInGradeProvider(_selectedGrade)),
              ),
              data: (students) {
                if (students.isEmpty) {
                  return Center(
                    child: Text(
                      'No active students found in this grade.',
                      style: GoogleFonts.poppins(
                          fontSize: _fs(context, 13, min: 11, max: 15),
                          color: AppColors.textMuted),
                    ),
                  );
                }

                return existingAsync.when(
                  loading: () => const ShimmerList(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(teacherAttendanceProvider((_selectedGrade, _dateStr))),
                  ),
                  data: (records) {
                    _initAttendance(students, records);

                    final alreadySubmitted = records
                        .any((r) => r.period == _selectedPeriod);

                    final presentCount = _attendance.values
                        .where((v) => v)
                        .length;
                    final absentCount =
                        students.length - presentCount;

                    return Column(
                      children: [
                        // ── Summary strip ──────────────────────────
                        _SummaryStrip(
                          total: students.length,
                          present: presentCount,
                          absent: absentCount,
                        ),

                        // ── Already-submitted banner ───────────────
                        if (alreadySubmitted)
                          _SubmittedBanner(dateStr: _dateStr, period: _selectedPeriod),

                        // ── Student list + action buttons at bottom ─
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(teacherAttendanceProvider((_selectedGrade, _dateStr)));
                              ref.invalidate(studentsInGradeProvider(_selectedGrade));
                            },
                            child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                                16, 12, 16,
                                R.sp(context, 16, min: 12, max: 24)),
                            itemCount: students.length + 1,
                            separatorBuilder: (_, i) => SizedBox(
                                height: i < students.length - 1 ? 8 : 16),
                            itemBuilder: (ctx, i) {
                              if (i == students.length) {
                                return _BottomActions(
                                  submitting: _submitting,
                                  isUpdate: alreadySubmitted,
                                  onReset: _resetAll,
                                  onSubmit: () => _submit(
                                      context, students,
                                      isUpdate: alreadySubmitted),
                                );
                              }
                              final s = students[i];
                              final isPresent =
                                  _attendance[s.id] ?? true;
                              return _StudentTile(
                                student: s,
                                isPresent: isPresent,
                                onChanged: (val) => setState(
                                    () => _attendance[s.id] = val),
                              );
                            },
                          ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final int selectedGrade;
  final DateTime selectedDate;
  final int selectedPeriod;
  final int periodsPerDay;
  final void Function(int) onGradeChanged;
  final void Function(DateTime) onDateChanged;
  final void Function(int) onPeriodChanged;

  const _FilterBar({
    required this.selectedGrade,
    required this.selectedDate,
    required this.selectedPeriod,
    required this.periodsPerDay,
    required this.onGradeChanged,
    required this.onDateChanged,
    required this.onPeriodChanged,
  });

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showAttendanceCalendar(
      context: context,
      initialDate: selectedDate,
      grade: selectedGrade,
    );
    if (picked != null) onDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      // Scale padding and gaps off the available width, not screen width,
      // so the filter bar never overflows regardless of device size.
      final hPad = (sw * 0.04).clamp(8.0, 20.0);
      final vPad = (sw * 0.03).clamp(8.0, 16.0);
      final gap  = (sw * 0.025).clamp(6.0, 14.0);

      // Inner content width after horizontal padding
      final inner = sw - hPad * 2 - gap * 2;
      // Grade=30%, Date=45%, Period=25%
      final gradeW  = inner * 0.30;
      final dateW   = inner * 0.45;
      final periodW = inner * 0.25;

      final labelStyle = GoogleFonts.poppins(
        fontSize: (sw * 0.03).clamp(10.0, 13.0),
        color: AppColors.textSecondary,
      );
      final valueStyle = GoogleFonts.poppins(
        fontSize: (sw * 0.033).clamp(11.0, 14.0),
        color: AppColors.primary,
      );
      final iconSize = (sw * 0.038).clamp(13.0, 17.0);

      final dropDecoration = InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: (sw * 0.025).clamp(6.0, 12.0),
          vertical:   (sw * 0.028).clamp(8.0, 14.0),
        ),
      );

      return Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        color: AppColors.cardBackground,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Grade dropdown ───────────────────────────────────────────
            SizedBox(
              width: gradeW,
              child: DropdownButtonFormField<int>(
                value: selectedGrade,
                isExpanded: true,
                decoration: dropDecoration.copyWith(labelText: 'Grade'),
                style: valueStyle,
                items: AppConstants.grades
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Grade $g', style: valueStyle),
                          ),
                        ))
                    .toList(),
                onChanged: (v) { if (v != null) onGradeChanged(v); },
              ),
            ),

            SizedBox(width: gap),

            // ── Date picker button ───────────────────────────────────────
            SizedBox(
              width: dateW,
              height: 48,
              child: OutlinedButton.icon(
                icon: Icon(Icons.calendar_today, size: iconSize),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    DateFormat('dd MMM yyyy').format(selectedDate),
                    style: valueStyle,
                    maxLines: 1,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: (sw * 0.025).clamp(6.0, 12.0),
                  ),
                  minimumSize: Size(dateW, 48),
                ),
                onPressed: () => _pickDate(context),
              ),
            ),

            SizedBox(width: gap),

            // ── Period dropdown ──────────────────────────────────────────
            SizedBox(
              width: periodW,
              child: DropdownButtonFormField<int>(
                value: selectedPeriod,
                isExpanded: true,
                decoration: dropDecoration.copyWith(labelText: 'Period'),
                style: valueStyle,
                items: List.generate(
                  periodsPerDay,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('P${i + 1}', style: valueStyle),
                  ),
                ),
                onChanged: (v) { if (v != null) onPeriodChanged(v); },
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Summary strip ──────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int total;
  final int present;
  final int absent;

  const _SummaryStrip({
    required this.total,
    required this.present,
    required this.absent,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : present / total;
    final gap = R.sp(context, 12, min: 8, max: 16);
    return Container(
      margin: EdgeInsets.fromLTRB(
          R.sp(context, 16, min: 12, max: 20),
          R.sp(context, 12, min: 8, max: 16),
          R.sp(context, 16, min: 12, max: 20),
          0),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 16, min: 12, max: 20),
          vertical: R.sp(context, 12, min: 8, max: 16)),
      decoration: mindForgeCardDecoration(),
      child: Row(
        children: [
          _StatChip(label: 'Total', value: '$total', color: AppColors.primary),
          SizedBox(width: gap),
          _StatChip(label: 'Present', value: '$present', color: AppColors.success),
          SizedBox(width: gap),
          _StatChip(label: 'Absent', value: '$absent', color: AppColors.error),
          const Spacer(),
          // Mini progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: _fs(context, 16, min: 13, max: 18),
                    color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: R.fluid(context, 80, min: 60, max: 100),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: AppColors.error.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: _fs(context, 18, min: 15, max: 22),
                  color: color)),
        ),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: _fs(context, 10, min: 9, max: 12),
                color: AppColors.textMuted)),
      ],
    );
  }
}

// ── Student tile ───────────────────────────────────────────────────────────

class _StudentTile extends StatelessWidget {
  final UserModel student;
  final bool isPresent;
  final void Function(bool) onChanged;

  const _StudentTile({
    required this.student,
    required this.isPresent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final avatarRadius = R.fluid(context, 18, min: 15, max: 22);
    return Container(
      decoration: mindForgeCardDecoration(),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 16, min: 12, max: 20),
          vertical: R.sp(context, 10, min: 8, max: 14)),
      child: Row(
        children: [
          CircleAvatar(
            radius: avatarRadius,
            backgroundColor: isPresent
                ? AppColors.success.withOpacity(0.15)
                : AppColors.error.withOpacity(0.15),
            child: Icon(
              isPresent ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: R.fluid(context, 20, min: 16, max: 24),
              color: isPresent ? AppColors.success : AppColors.error,
            ),
          ),
          SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
          Expanded(
            child: Text(
              student.username,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 14, min: 12, max: 16),
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            isPresent ? 'Present' : 'Absent',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 12, min: 10, max: 13),
              fontWeight: FontWeight.w600,
              color: isPresent ? AppColors.success : AppColors.error,
            ),
          ),
          SizedBox(width: R.sp(context, 4, min: 2, max: 8)),
          Switch.adaptive(
            value: isPresent,
            activeColor: AppColors.success,
            inactiveTrackColor: AppColors.error.withOpacity(0.3),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Already-submitted banner ───────────────────────────────────────────────

class _SubmittedBanner extends StatelessWidget {
  final String dateStr;
  final int period;
  const _SubmittedBanner({required this.dateStr, required this.period});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
          R.sp(context, 16, min: 12, max: 20),
          R.sp(context, 8, min: 6, max: 12),
          R.sp(context, 16, min: 12, max: 20),
          0),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 14, min: 10, max: 18),
          vertical: R.sp(context, 10, min: 8, max: 13)),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.accent,
              size: R.fluid(context, 18, min: 15, max: 22)),
          SizedBox(width: R.sp(context, 8, min: 6, max: 10)),
          Expanded(
            child: Text(
              'Attendance already submitted for Period $period on $dateStr. '
              'Make changes below and tap Update to save.',
              style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 10, max: 13),
                  color: AppColors.accent,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom action bar ──────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final bool submitting;
  final bool isUpdate;
  final VoidCallback onReset;
  final VoidCallback onSubmit;

  const _BottomActions({
    required this.submitting,
    required this.isUpdate,
    required this.onReset,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final vPad = R.sp(context, 14, min: 11, max: 17);
    final btnColor = isUpdate ? AppColors.accent : AppColors.primary;
    final btnLabel = submitting
        ? (isUpdate ? 'Updating…' : 'Submitting…')
        : (isUpdate ? 'Update Attendance' : 'Submit Attendance');
    final btnIcon = isUpdate ? Icons.edit_outlined : Icons.send_outlined;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: R.sp(context, 4, min: 2, max: 8)),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.refresh, size: R.fluid(context, 18, min: 16, max: 20)),
              label: Text('Reset',
                  style: GoogleFonts.poppins(
                      fontSize: _fs(context, 14, min: 12, max: 16))),
              onPressed: submitting ? null : onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                side: const BorderSide(color: AppColors.textMuted),
                padding: EdgeInsets.symmetric(vertical: vPad),
              ),
            ),
          ),
          SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              icon: submitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(btnIcon,
                      size: R.fluid(context, 18, min: 16, max: 20)),
              label: Text(
                btnLabel,
                style: GoogleFonts.poppins(
                    fontSize: _fs(context, 14, min: 12, max: 16)),
              ),
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: btnColor,
                padding: EdgeInsets.symmetric(vertical: vPad),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
