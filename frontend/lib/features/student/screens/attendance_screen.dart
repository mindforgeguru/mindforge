import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/attendance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_provider.dart';
import '../widgets/student_scaffold.dart';

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base,
    {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(
      min == 0 ? base * 0.75 : min,
      max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

class StudentAttendanceScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const StudentAttendanceScreen({super.key, this.embedded = false});

  @override
  ConsumerState<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState
    extends ConsumerState<StudentAttendanceScreen> {
  late DateTime _displayMonth;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(studentAttendanceProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _prevMonth() => setState(() =>
      _displayMonth =
          DateTime(_displayMonth.year, _displayMonth.month - 1));

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_displayMonth.year, _displayMonth.month + 1);
    if (next.isBefore(DateTime(now.year, now.month + 1))) {
      setState(() => _displayMonth = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final recordsAsync = ref.watch(studentAttendanceProvider);
    final now = DateTime.now();
    final isCurrentMonth = _displayMonth.year == now.year &&
        _displayMonth.month == now.month;

    // ── Embedded (inside timetable combined layout) ──────────────────────────
    if (widget.embedded) {
      return recordsAsync.when(
        loading: () => const ShimmerList(showAvatar: false, itemHeight: 56),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(studentAttendanceProvider),
        ),
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
          final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TimetableStyleMonthNav(
                  displayMonth: _displayMonth,
                  onPrev: _prevMonth,
                  onNext: isCurrentMonth ? null : _nextMonth,
                ),
                const SizedBox(height: 6),
                const _CompactWeekdayRow(),
                const SizedBox(height: 4),
                _CalendarGrid(month: _displayMonth, statusMap: statusMap, compact: true),
                const SizedBox(height: 8),
                const _Legend(),
                const SizedBox(height: 12),
                Container(
                  decoration: mindForgeCardDecoration(),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(_displayMonth),
                        style:       TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _StatPill(label: 'Present', value: '$presentCount', color: AppColors.success)),
                        Expanded(child: _StatPill(label: 'Absent', value: '$absentCount', color: AppColors.error)),
                        Expanded(child: _StatPill(label: 'Total', value: '$totalDays', color: AppColors.primary)),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        totalDays == 0 ? 'No records this month' : 'Attendance: ${pct.toStringAsFixed(1)}%',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                            color: totalDays == 0 ? AppColors.textMuted : pctColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // ── Wide (web) — 3-column layout ─────────────────────────────────────────
    if (isWide) {
      return StudentScaffold(
        wideContent: true,
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: Text('My Attendance',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
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
        body: Padding(
          padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left column: Profile ───────────────────────────────────
              SizedBox(
                width: 230,
                child: _ProfileColumn(ref: ref),
              ),
              const SizedBox(width: 20),
              // ── Middle column: Donut + Leaderboard ─────────────────────
              Expanded(
                flex: 2,
                child: recordsAsync.when(
                  loading: () => const ShimmerList(showAvatar: false, itemHeight: 56),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(studentAttendanceProvider),
                  ),
                  data: (records) => _DonutLeaderboardColumn(records: records),
                ),
              ),
              const SizedBox(width: 20),
              // ── Right column: Calendar ──────────────────────────────────
              Expanded(
                flex: 2,
                child: Container(
                  decoration: mindForgeCardDecoration(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: recordsAsync.when(
                    loading: () => const ShimmerList(showAvatar: false, itemHeight: 56),
                    error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(studentAttendanceProvider),
                    ),
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
                      final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                      Icon(Icons.fact_check_outlined, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text('Attendance Calendar',
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                const SizedBox(width: 8),
                                const Expanded(child: Divider(color: AppColors.divider, thickness: 1, height: 1)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _TimetableStyleMonthNav(
                              displayMonth: _displayMonth,
                              onPrev: _prevMonth,
                              onNext: isCurrentMonth ? null : _nextMonth,
                            ),
                            const SizedBox(height: 8),
                            const _CompactWeekdayRow(),
                            const SizedBox(height: 4),
                            _CalendarGrid(month: _displayMonth, statusMap: statusMap, compact: true),
                            const SizedBox(height: 10),
                            const _Legend(),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 14),
                            Text(DateFormat('MMMM yyyy').format(_displayMonth),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: _StatPill(label: 'Present', value: '$presentCount', color: AppColors.success)),
                              Expanded(child: _StatPill(label: 'Absent', value: '$absentCount', color: AppColors.error)),
                              Expanded(child: _StatPill(label: 'Total', value: '$totalDays', color: AppColors.primary)),
                            ]),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: pct / 100,
                                backgroundColor: AppColors.divider,
                                valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              totalDays == 0 ? 'No records this month' : 'Attendance: ${pct.toStringAsFixed(1)}%',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13,
                                  color: totalDays == 0 ? AppColors.textMuted : pctColor),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Mobile layout ────────────────────────────────────────────────────────
    return StudentScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'My Attendance',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 18, min: 15, max: 21),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
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
      body: recordsAsync.when(
        loading: () => const ShimmerList(showAvatar: false, itemHeight: 56),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(studentAttendanceProvider),
        ),
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
          final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;
          final sw = MediaQuery.of(context).size.width;
          final hPad = (sw * 0.04).clamp(12.0, 20.0);
          final vPad = (sw * 0.03).clamp(10.0, 16.0);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(studentAttendanceProvider.future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad * 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: mindForgeCardDecoration(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    child: Column(
                      children: [
                        _TimetableStyleMonthNav(
                          displayMonth: _displayMonth,
                          onPrev: _prevMonth,
                          onNext: isCurrentMonth ? null : _nextMonth,
                        ),
                        const SizedBox(height: 6),
                        const _CompactWeekdayRow(),
                        const SizedBox(height: 4),
                        _CalendarGrid(month: _displayMonth, statusMap: statusMap, compact: true),
                        SizedBox(height: _s(context, 16, min: 10, max: 20)),
                        const _Legend(),
                      ],
                    ),
                  ),
                  SizedBox(height: _s(context, 16, min: 10, max: 20)),
                  Container(
                    decoration: mindForgeCardDecoration(),
                    padding: EdgeInsets.all((sw * 0.05).clamp(14.0, 22.0)),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(DateFormat('MMMM yyyy').format(_displayMonth),
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                                  fontSize: _fs(context, 15, min: 13, max: 17), color: AppColors.primary)),
                        ),
                        SizedBox(height: _s(context, 16, min: 10, max: 20)),
                        Row(children: [
                          Expanded(child: _StatPill(label: 'Present', value: '$presentCount', color: AppColors.success)),
                          Expanded(child: _StatPill(label: 'Absent', value: '$absentCount', color: AppColors.error)),
                          Expanded(child: _StatPill(label: 'Total Days', value: '$totalDays', color: AppColors.primary)),
                        ]),
                        SizedBox(height: _s(context, 20, min: 14, max: 26)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(_s(context, 8, min: 6, max: 10)),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            backgroundColor: AppColors.divider,
                            valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                            minHeight: _s(context, 10, min: 8, max: 12),
                          ),
                        ),
                        SizedBox(height: _s(context, 10, min: 6, max: 12)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            totalDays == 0 ? 'No records this month' : 'Attendance: ${pct.toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                                fontSize: _fs(context, 15, min: 12, max: 17),
                                color: totalDays == 0 ? AppColors.textMuted : pctColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
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

// ─── Web left column: Student Profile ────────────────────────────────────────

class _ProfileColumn extends ConsumerWidget {
  final WidgetRef ref;
  const _ProfileColumn({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final gradeAsync = ref.watch(studentGradeProvider);
    final profileAsync = ref.watch(studentProfileProvider);
    final summaryAsync = ref.watch(studentAttendanceSummaryProvider);
    final username = auth.username ?? 'Student';

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
            backgroundImage: auth.profilePicUrl != null
                ? CachedNetworkImageProvider(auth.profilePicUrl!) as ImageProvider
                : null,
            child: auth.profilePicUrl == null
                ? Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'S',
                    style: GoogleFonts.poppins(
                        fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.secondary),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          // Name
          Text(
            username,
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Grade badge
          gradeAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (g) => g == null ? const SizedBox.shrink() : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Grade $g',
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // Role pill
          Row(
            children: [
              const Icon(Icons.school_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text('Student', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          // Parent info
          profileAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (p) {
              final parentName = p['parent_username'] as String?;
              return Row(
                children: [
                  Icon(Icons.family_restroom, size: 14,
                      color: parentName != null ? AppColors.accent : AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      parentName != null ? 'Parent: $parentName' : 'No parent linked',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: parentName != null ? AppColors.accent : AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          // Overall attendance summary
          summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, __) => const SizedBox.shrink(),
            data: (s) {
              final pct = s.attendancePercentage;
              final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Attendance',
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppColors.textMuted, letterSpacing: 0.4)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _MiniStat(label: 'Present', value: '${s.presentCount}', color: AppColors.success)),
                    Expanded(child: _MiniStat(label: 'Absent', value: '${s.absentCount}', color: AppColors.error)),
                    Expanded(child: _MiniStat(label: 'Total', value: '${s.totalClasses}', color: AppColors.primary)),
                  ]),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${pct.toStringAsFixed(1)}%',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: pctColor)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }
}

// ─── Web middle column: Donut chart + Leaderboard ─────────────────────────────

class _DonutLeaderboardColumn extends ConsumerWidget {
  final List<AttendanceModel> records;
  const _DonutLeaderboardColumn({required this.records});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(studentAttendanceSummaryProvider);
    final leaderboardAsync = ref.watch(classAttendanceLeaderboardProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Donut chart card ─────────────────────────────────────────
          Container(
            decoration: mindForgeCardDecoration(),
            padding: const EdgeInsets.all(20),
            child: summaryAsync.when(
              loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, __) => const SizedBox.shrink(),
              data: (s) {
                final pct = s.attendancePercentage;
                final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;
                final absentPct = 100 - pct;
                return Column(
                  children: [
                    Row(
                      children: [
                              Icon(Icons.pie_chart_outline, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('% of Attendance',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              sectionsSpace: 3,
                              centerSpaceRadius: 58,
                              sections: [
                                PieChartSectionData(
                                  value: pct > 0 ? pct : 0.01,
                                  color: pctColor,
                                  radius: 24,
                                  showTitle: false,
                                ),
                                PieChartSectionData(
                                  value: absentPct > 0 ? absentPct : 0.01,
                                  color: AppColors.divider,
                                  radius: 20,
                                  showTitle: false,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${pct.toStringAsFixed(0)}%',
                                  style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: pctColor)),
                              Text('Present',
                                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DonutLegendItem(color: pctColor, label: '${pct.toStringAsFixed(1)}%  Present'),
                        const SizedBox(width: 20),
                        _DonutLegendItem(color: AppColors.divider, label: '${absentPct.toStringAsFixed(1)}%  Absent', textColor: AppColors.textMuted),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // ── Top Students leaderboard ─────────────────────────────────
          leaderboardAsync.when(
            loading: () => Container(
              decoration: mindForgeCardDecoration(),
              padding: const EdgeInsets.all(20),
              child: const ShimmerList(showAvatar: true, itemHeight: 52),
            ),
            error: (e, _) => Container(
              decoration: mindForgeCardDecoration(),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('Could not load leaderboard',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted)),
              ),
            ),
            data: (list) => Container(
            decoration: mindForgeCardDecoration(),
            padding: const EdgeInsets.all(20),
            child: Builder(builder: (context) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No class data', style: GoogleFonts.poppins(color: AppColors.textMuted))),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                              Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Text('Top Students',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${list.length}',
                              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...list.asMap().entries.map((entry) {
                      final i = entry.key;
                      final s = entry.value;
                      final isMe = s['is_me'] as bool? ?? false;
                      final pct = (s['attendance_percentage'] as num).toDouble();
                      final pctColor = pct >= 75 ? AppColors.success : pct >= 50 ? AppColors.warning : AppColors.error;
                      final picUrl = s['profile_pic_url'] as String?;
                      final name = s['username'] as String? ?? '?';
                      final rank = s['rank'] as int? ?? (i + 1);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isMe ? Border.all(color: AppColors.primary.withValues(alpha: 0.2)) : null,
                        ),
                        child: Row(
                          children: [
                            // Rank badge
                            SizedBox(
                              width: 24,
                              child: Text(
                                rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '#$rank',
                                style: GoogleFonts.poppins(fontSize: rank <= 3 ? 16 : 11,
                                    fontWeight: FontWeight.w700, color: AppColors.textMuted),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Avatar
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
                              backgroundImage: picUrl != null ? CachedNetworkImageProvider(picUrl) as ImageProvider : null,
                              child: picUrl == null
                                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.secondary))
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            // Name
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMe ? '$name (You)' : name,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                                        color: isMe ? AppColors.primary : AppColors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Circular progress + percentage
                            SizedBox(
                              width: 46,
                              height: 46,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: pct / 100,
                                    strokeWidth: 3.5,
                                    backgroundColor: AppColors.divider,
                                    valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                                  ),
                                  Text('${pct.toInt()}%',
                                      style: GoogleFonts.poppins(fontSize: 8.5, fontWeight: FontWeight.w700, color: pctColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _DonutLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final Color? textColor;
  const _DonutLegendItem({required this.color, required this.label, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.poppins(fontSize: 11, color: textColor ?? AppColors.textSecondary)),
      ],
    );
  }
}

// ─── Timetable-style month navigator ─────────────────────────────────────────

class _TimetableStyleMonthNav extends StatelessWidget {
  final DateTime displayMonth;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _TimetableStyleMonthNav({
    required this.displayMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardBackground,
            foregroundColor: AppColors.primary,
          ),
        ),
        Text(
          DateFormat('MMMM yyyy').format(displayMonth),
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: onNext,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardBackground,
            foregroundColor: onNext != null ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Compact weekday label row (M T W T F S S, Monday-first) ─────────────────

class _CompactWeekdayRow extends StatelessWidget {
  const _CompactWeekdayRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) => Expanded(
        child: Center(
          child: Text(
            d,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
      )).toList(),
    );
  }
}

// ─── Calendar grid ────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, _DayStatus> statusMap;
  final bool compact;

  const _CalendarGrid({required this.month, required this.statusMap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final rowGap = (sw * 0.012).clamp(3.0, 6.0);

    final firstDay = DateTime(month.year, month.month, 1);
    // compact = Monday-first (Mon=1 → offset 0, like timetable)
    // normal  = Sunday-first (Sun=7→%7=0, Mon=1→%7=1, …)
    final startOffset = compact ? firstDay.weekday - 1 : firstDay.weekday % 7;
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
          cells.add(const Expanded(child: SizedBox()));
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
            compact: compact,
          ),
        ));
      }
      rows.add(Row(children: cells));
      if (week < totalCells ~/ 7 - 1) rows.add(SizedBox(height: rowGap));
    }

    return Column(children: rows);
  }
}

// ─── Single day cell ──────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int dayNum;
  final _DayStatus? status;
  final bool isToday;
  final bool isFuture;
  final bool compact;

  const _DayCell({
    required this.dayNum,
    required this.status,
    required this.isToday,
    required this.isFuture,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final cellSize = compact ? 30.0 : ((sw / 7) * 0.82).clamp(28.0, 44.0);
    final margin = compact ? 2.0 : (sw * 0.006).clamp(1.5, 3.0);

    Color? bgColor;
    Color textColor = AppColors.textSecondary;
    FontWeight fontWeight = FontWeight.w400;

    if (!isFuture && status != null) {
      switch (status!) {
        case _DayStatus.present:
          bgColor = AppColors.success;
          textColor = Colors.white;
          fontWeight = FontWeight.w700;
        case _DayStatus.absent:
          bgColor = AppColors.error;
          textColor = Colors.white;
          fontWeight = FontWeight.w700;
        case _DayStatus.mixed:
          bgColor = AppColors.warning;
          textColor = Colors.white;
          fontWeight = FontWeight.w700;
      }
    }

    return Container(
      margin: EdgeInsets.all(margin),
      height: cellSize,
      decoration: BoxDecoration(
        color: bgColor?.withValues(alpha: isToday ? 1.0 : 0.85),
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(
                color: bgColor ?? AppColors.primary,
                width: 2,
              )
            : null,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$dayNum',
            style: GoogleFonts.poppins(
              fontSize: (cellSize * 0.38).clamp(9.0, 14.0),
              fontWeight: isToday ? FontWeight.w700 : fontWeight,
              color: isFuture
                  ? AppColors.textMuted.withValues(alpha: 0.4)
                  : (bgColor != null
                      ? textColor
                      : AppColors.textSecondary),
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
    final gap = _s(context, 16, min: 10, max: 20);
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
    final dotSz = _s(context, 11, min: 9, max: 13);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSz,
          height: dotSz,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: _s(context, 5, min: 4, max: 7)),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: _fs(context, 11, min: 9, max: 12),
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
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 24, min: 18, max: 28),
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        SizedBox(height: _s(context, 2, min: 1, max: 4)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 11, min: 9, max: 12),
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
