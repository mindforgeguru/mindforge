import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/timetable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/student_provider.dart';
import '../widgets/student_scaffold.dart';
import 'package:google_fonts/google_fonts.dart';

class StudentTimetableScreen extends ConsumerStatefulWidget {
  const StudentTimetableScreen({super.key});

  @override
  ConsumerState<StudentTimetableScreen> createState() =>
      _StudentTimetableScreenState();
}

class _StudentTimetableScreenState
    extends ConsumerState<StudentTimetableScreen> {
  late DateTime _calendarMonth;
  late DateTime _selectedDate;
  Timer? _refreshTimer;

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month);
    // Saturday is a working day at our school; only Sunday (weekday 7) jumps
    // forward to Monday.
    _selectedDate = now.weekday == DateTime.sunday
        ? now.add(const Duration(days: 1))
        : now;
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(studentTimetableProvider(_dateString));
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
    final timetableAsync = ref.watch(studentTimetableProvider(_dateString));
    final profileAsync = ref.watch(studentProfileProvider);
    final today = DateTime.now();
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    final gradeLabel = profileAsync.valueOrNull != null
        ? 'Grade ${profileAsync.valueOrNull!['grade']}'
        : null;

    final isWide = MediaQuery.of(context).size.width >= 900;

    final timetableBody = Column(
        children: [
          // ── Monthly calendar ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: mindForgeCardDecoration(),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      onPressed: _prevMonth,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_calendarMonth),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: _nextMonth,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.cardBackground,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(d,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textMuted,
                                  )),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 2),
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

          const SizedBox(height: 6),

          // ── Selected day header ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isToday ? Colors.white : AppColors.primary,
                          ),
                        ),
                        Text(
                          DateFormat('d MMMM yyyy').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 12,
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
              loading: () => RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(studentTimetableProvider(_dateString).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 100),
                    Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
              error: (e, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(studentTimetableProvider(_dateString)),
                  ),
                ],
              ),
              data: (slots) => RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(studentTimetableProvider(_dateString).future),
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
                              Text(
                                gradeLabel != null
                                    ? 'No classes scheduled for $gradeLabel'
                                    : 'No classes scheduled',
                                style: const TextStyle(
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
    );

    if (isWide) {
      return StudentScaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column — Timetable
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _WebColHeader(title: 'Timetable', icon: Icons.calendar_today_outlined),
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: timetableBody),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Right column — Decorative panel
              const Expanded(child: _DecorativePanel()),
            ],
          ),
        ),
      );
    }

    return StudentScaffold(
      appBar: AppBar(
        title: const Text('My Timetable'),
        actions: [
          if (gradeLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    gradeLabel,
                    style:       TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
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
      body: timetableBody,
    );
  }
}

// ─── Decorative blue panel ────────────────────────────────────────────────────

class _DecorativePanel extends StatelessWidget {
  const _DecorativePanel();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base image — splash logo tiled/scaled as background texture
          Image.asset(
            'assets/images/splash_logo.png',
            fit: BoxFit.cover,
            color: const Color(0xFF1D3557).withValues(alpha: 0.15),
            colorBlendMode: BlendMode.multiply,
          ),
          // Blue gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1D3557),        // deep navy
                  Color(0xFF2A6496),        // mid blue
                  Color(0xFF1A8FD1),        // lighter blue
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Decorative circles
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Positioned(
            top: 80,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 28),
                Text(
                  'MIND FORGE',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your schedule,\nyour success.',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Divider line
                Container(
                  width: 48,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A8FD1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // Tagline chips
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(icon: Icons.calendar_today_outlined, label: 'Timetable'),
                    _InfoChip(icon: Icons.menu_book_outlined, label: 'Subjects'),
                    _InfoChip(icon: Icons.people_outline, label: 'Teachers'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Web column header ────────────────────────────────────────────────────────

class _WebColHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _WebColHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
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
          cells.add(Expanded(child: SizedBox(height: R.fluid(context, 28, min: 24, max: 36))));
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
              height: R.fluid(context, 28, min: 24, max: 36),
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
      if (week < totalCells ~/ 7 - 1) rows.add(const SizedBox(height: 1));
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
                  slot.isHoliday
                      ? 'Holiday'
                      : (slot.subject?.isNotEmpty == true ? slot.subject! : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: R.fs(context, 14, min: 12, max: 16)),
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
