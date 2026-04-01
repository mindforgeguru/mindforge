import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/timetable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_bottom_nav.dart';
import '../widgets/parent_error_widget.dart';

class ParentTimetableScreen extends ConsumerStatefulWidget {
  const ParentTimetableScreen({super.key});

  @override
  ConsumerState<ParentTimetableScreen> createState() =>
      _ParentTimetableScreenState();
}

class _ParentTimetableScreenState
    extends ConsumerState<ParentTimetableScreen> {
  late DateTime _calendarMonth;
  late DateTime _selectedDate;
  Timer? _refreshTimer;

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month);
    _selectedDate = now.weekday >= 6
        ? now.add(Duration(days: 8 - now.weekday))
        : now;
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(parentChildTimetableProvider(_dateString));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _prevMonth() => setState(() =>
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1));

  void _nextMonth() => setState(() =>
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1));

  @override
  Widget build(BuildContext context) {
    final timetableAsync = ref.watch(parentChildTimetableProvider(_dateString));
    final today = DateTime.now();
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Child's Timetable"),
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
      bottomNavigationBar: const ParentBottomNav(),
      body: Column(
        children: [
          // ── Monthly calendar ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: mindForgeCardDecoration(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _prevMonth,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_calendarMonth),
                      style: TextStyle(
                          fontSize: R.fs(context, 15, min: 13, max: 17), fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(d,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textMuted,
                                  )),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                _CalendarGrid(
                  month: _calendarMonth,
                  selectedDate: _selectedDate,
                  today: today,
                  onDateTapped: (date) =>
                      setState(() => _selectedDate = date),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Selected day header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isToday
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE').format(_selectedDate),
                          style: TextStyle(
                            fontSize: R.fs(context, 15, min: 13, max: 17),
                            fontWeight: FontWeight.bold,
                            color: isToday ? Colors.white : AppColors.primary,
                          ),
                        ),
                        Text(
                          DateFormat('d MMMM yyyy').format(_selectedDate),
                          style: TextStyle(
                            fontSize: R.fs(context, 12, min: 10, max: 14),
                            color: isToday
                                ? Colors.white70
                                : AppColors.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'TODAY',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Period list ───────────────────────────────────────────────
          Expanded(
            child: timetableAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  parentErrorWidget(e),
                ],
              ),
              data: (slots) => RefreshIndicator(
                onRefresh: () => ref
                    .refresh(parentChildTimetableProvider(_dateString).future),
                child: slots.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 60),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_busy_outlined,
                                  size: 48,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              const Text(
                                'No classes scheduled',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Pull down to refresh',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: slots.length,
                        itemBuilder: (ctx, i) => _PeriodTile(
                          slot: slots[i],
                          isToday: isToday,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Calendar grid ─────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final void Function(DateTime) onDateTapped;

  const _CalendarGrid({
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.onDateTapped,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((startOffset + daysInMonth + 6) ~/ 7) * 7;

    final rows = <Widget>[];
    for (int week = 0; week < totalCells ~/ 7; week++) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final cellIndex = week * 7 + col;
        final dayNum = cellIndex - startOffset + 1;

        if (dayNum < 1 || dayNum > daysInMonth) {
          cells.add(Expanded(child: SizedBox(height: R.fluid(context, 36, min: 30, max: 44))));
          continue;
        }

        final date = DateTime(month.year, month.month, dayNum);
        final isSelected = date.year == selectedDate.year &&
            date.month == selectedDate.month &&
            date.day == selectedDate.day;
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;

        Color? bgColor;
        Color textColor = AppColors.textSecondary;
        Border? border;

        if (isSelected) {
          bgColor = AppColors.primary;
          textColor = Colors.white;
        } else if (isToday) {
          bgColor = AppColors.accent.withValues(alpha: 0.15);
          textColor = AppColors.accent;
          border = Border.all(
              color: AppColors.accent.withValues(alpha: 0.8), width: 1.5);
        }

        cells.add(Expanded(
          child: GestureDetector(
            onTap: () => onDateTapped(date),
            child: Container(
              margin: const EdgeInsets.all(2),
              height: R.fluid(context, 34, min: 28, max: 42),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: border,
              ),
              child: Center(
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: textColor,
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

// ─── Period tile ───────────────────────────────────────────────────────────────

class _PeriodTile extends StatelessWidget {
  final TimetableSlotModel slot;
  final bool isToday;

  const _PeriodTile({required this.slot, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final accentColor = slot.isHoliday
        ? AppColors.warning
        : (isToday ? AppColors.accent : AppColors.secondary);

    final hasTime = slot.startTime != null && slot.endTime != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: mindForgeCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: R.fluid(context, 44, min: 36, max: 52),
            height: R.fluid(context, 44, min: 36, max: 52),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'P${slot.periodNumber}',
                style: TextStyle(
                  fontSize: R.fs(context, 12, min: 10, max: 14),
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.isHoliday ? 'Holiday' : slot.subject,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: R.fs(context, 14, min: 12, max: 16)),
                ),
                if (!slot.isHoliday) ...[
                  if (slot.teacherUsername != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(slot.teacherUsername!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                  if (hasTime) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${slot.startTime}  –  ${slot.endTime}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                  if (slot.comment != null && slot.comment!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.comment_outlined,
                            size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            slot.comment!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                                fontStyle: FontStyle.italic),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          Icon(
            slot.isHoliday ? Icons.beach_access : Icons.book_outlined,
            color: accentColor,
            size: 20,
          ),
        ],
      ),
    );
  }
}
