import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/timetable.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';

class TeacherTimetableScreen extends ConsumerStatefulWidget {
  const TeacherTimetableScreen({super.key});

  @override
  ConsumerState<TeacherTimetableScreen> createState() =>
      _TeacherTimetableScreenState();
}

class _TeacherTimetableScreenState
    extends ConsumerState<TeacherTimetableScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // When teacher taps "Edit" on the View tab, store grade+date here
  // and force-recreate the Create tab via a ValueKey.
  int _createGrade = 8;
  DateTime? _createDate;
  // Key changes each time an edit is requested → _CreateTab rebuilds fresh
  int _createKey = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _editTimetable(int grade, DateTime date) {
    setState(() {
      _createGrade = grade;
      _createDate = date;
      _createKey++;
    });
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return TeacherScaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_today_outlined), text: 'My Timetable'),
            Tab(icon: Icon(Icons.edit_calendar_outlined), text: 'Create / Edit'),
            Tab(icon: Icon(Icons.grid_view_outlined), text: 'Full Timetable'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ViewTab(onEditTimetable: _editTimetable),
          _CreateTab(
            key: ValueKey(_createKey),
            initialGrade: _createGrade,
            initialDate: _createDate,
          ),
          _FullTimetableTab(onEditTimetable: _editTimetable),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VIEW TAB
// ══════════════════════════════════════════════════════════════════════════════

class _ViewTab extends ConsumerStatefulWidget {
  final void Function(int grade, DateTime date) onEditTimetable;
  const _ViewTab({required this.onEditTimetable});

  @override
  ConsumerState<_ViewTab> createState() => _ViewTabState();
}

class _ViewTabState extends ConsumerState<_ViewTab> {
  late DateTime _selectedDate;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = now.weekday >= 6
        ? now.add(Duration(days: 8 - now.weekday))
        : now;
    _weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final myTimetableAsync = ref.watch(myTimetableProvider);
    final configAsync = ref.watch(teacherTimetableConfigProvider);
    final today = DateTime.now();

    return myTimetableAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myTimetableProvider)),
      data: (slots) {
        // Period times from config
        final periodTimes = <int, (String, String)>{};
        final config = configAsync.valueOrNull;
        if (config?.periodTimes != null) {
          for (final pt in config!.periodTimes!) {
            final m = pt as Map<String, dynamic>;
            periodTimes[m['period'] as int] =
                (m['start'] as String, m['end'] as String);
          }
        }

        // Group by slotDate (String "YYYY-MM-DD")
        final byDate = <String, List<TimetableSlotModel>>{};
        for (final slot in slots) {
          byDate.putIfAbsent(slot.slotDate, () => []).add(slot);
        }

        // Dates that have timetable (used to highlight calendar cells)
        final datesWithTimetable = byDate.keys.toSet();

        // Slots for selected date
        final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        final selectedSlots =
            List<TimetableSlotModel>.from(byDate[selectedDateStr] ?? [])
              ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

        final isToday = _selectedDate.year == today.year &&
            _selectedDate.month == today.month &&
            _selectedDate.day == today.day;

        final isWide = MediaQuery.of(context).size.width >= 900;


        // ── Day header (mobile only) ───────────────────────────────────────
        final dayHeader = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('EEE').format(_selectedDate)}  ·  ${DateFormat('d MMM yyyy').format(_selectedDate)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isToday ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                    child: const Text('TODAY', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
              ],
            ),
          ),
        );

        // ── Period list for selected day ──────────────────────────────────
        final periodList = selectedSlots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined,
                              size: 40,
                              color: AppColors.textMuted
                                  .withValues(alpha: 0.4)),
                          const SizedBox(height: 8),
                          const Text('No classes on this day',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13)),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit_calendar_outlined,
                                size: 16),
                            label: const Text('Create Timetable'),
                            onPressed: () => widget.onEditTimetable(
                                8, _selectedDate),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: selectedSlots.length,
                      itemBuilder: (ctx, i) {
                        final slot = selectedSlots[i];
                        final times = periodTimes[slot.periodNumber];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: mindForgeCardDecoration(),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.secondary
                                  .withValues(alpha: 0.15),
                              child: Text('P${slot.periodNumber}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary)),
                            ),
                            title: Text(
                                slot.subject?.isNotEmpty == true
                                    ? slot.subject!
                                    : slot.teacherUsername ?? 'Period ${slot.periodNumber}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Grade ${slot.grade}'
                                  '${times != null ? '  ·  ${times.$1} – ${times.$2}' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                if (slot.comment != null && slot.comment!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.comment_outlined,
                                            size: 11, color: AppColors.textMuted),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(slot.comment!,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                  fontStyle: FontStyle.italic),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            trailing: const Icon(Icons.book_outlined,
                                color: AppColors.secondary, size: 18),
                          ),
                        );
                      },
                    );

        // ── Assemble layout ───────────────────────────────────────────────
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Week strip left panel
              SizedBox(
                width: 380,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  decoration: mindForgeCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(children: [
                          Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Select Date',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        ]),
                      ),
                      const Divider(height: 1),
                      _WeekStrip(
                        weekStart: _weekStart,
                        selectedDate: _selectedDate,
                        datesWithTimetable: datesWithTimetable,
                        onDateSelected: (date) => setState(() => _selectedDate = date),
                        onWeekChanged: (newWeekStart) => setState(() => _weekStart = newWeekStart),
                      ),
                    ],
                  ),
                ),
              ),
              // Period list right panel
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  decoration: mindForgeCardDecoration(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE, d MMMM').format(_selectedDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 16),
                      Expanded(child: periodList),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _WeekStrip(
              weekStart: _weekStart,
              selectedDate: _selectedDate,
              datesWithTimetable: datesWithTimetable,
              onDateSelected: (date) => setState(() => _selectedDate = date),
              onWeekChanged: (newWeekStart) => setState(() => _weekStart = newWeekStart),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            dayHeader,
            const SizedBox(height: 4),
            Expanded(child: periodList),
          ],
        );
      },
    );
  }

}

// ══════════════════════════════════════════════════════════════════════════════
// CREATE / EDIT TAB
// ══════════════════════════════════════════════════════════════════════════════

class _CreateTab extends ConsumerStatefulWidget {
  final int initialGrade;
  final DateTime? initialDate;

  const _CreateTab({
    super.key,
    this.initialGrade = 8,
    this.initialDate,
  });

  @override
  ConsumerState<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends ConsumerState<_CreateTab> {
  late int _selectedGrade;

  // Calendar state
  late DateTime _selectedDate;
  late DateTime _weekStart; // Monday of the displayed week

  String get _dateString =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  final Map<int, int?> _teacherIds = {};
  final Map<int, String?> _subjects = {};
  final Map<int, String?> _comments = {};

  int? _populatedGrade;
  String? _populatedDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedGrade = widget.initialGrade;
    final initial = widget.initialDate ?? DateTime.now();
    _selectedDate = initial;
    // Monday of the week containing the initial date
    _weekStart = initial.subtract(Duration(days: initial.weekday - 1));
  }

  void _onDateTapped(DateTime date) {
    setState(() {
      _selectedDate = date;
      _teacherIds.clear();
      _subjects.clear();
      _comments.clear();
      _populatedGrade = null;
      _populatedDate = null;
    });
  }

  void _populateFromSlots(
      List<TimetableSlotModel> slots, List<UserModel> teachers) {
    final currentDate = _dateString;
    if (_populatedGrade == _selectedGrade &&
        _populatedDate == currentDate) {
      return;
    }
    _populatedGrade = _selectedGrade;
    _populatedDate = currentDate;

    final validIds = teachers.map((t) => t.id).toSet();
    for (final slot in slots.where((s) => s.slotDate == currentDate)) {
      _teacherIds[slot.periodNumber] =
          (slot.teacherId != null && validIds.contains(slot.teacherId))
              ? slot.teacherId
              : null;
      _subjects[slot.periodNumber] =
          slot.isHoliday ? null : slot.subject;
      _comments[slot.periodNumber] = slot.comment;
    }
  }

  /// Returns Map<period, Map<teacherId, busyGrade>>
  Map<int, Map<int, int>> _computeBusyTeachers() {
    final busy = <int, Map<int, int>>{};
    for (final grade in AppConstants.grades) {
      if (grade == _selectedGrade) continue;
      ref.read(teacherTimetableProvider((grade, _dateString))).whenData((slots) {
        for (final slot in slots) {
          if (slot.teacherId == null) continue;
          busy.putIfAbsent(slot.periodNumber, () => {})[slot.teacherId!] = grade;
        }
      });
    }
    return busy;
  }

  @override
  Widget build(BuildContext context) {
    final timetableAsync =
        ref.watch(teacherTimetableProvider((_selectedGrade, _dateString)));
    final teachersAsync = ref.watch(teachersListProvider);
    final configAsync = ref.watch(teacherTimetableConfigProvider);

    for (final grade in AppConstants.grades) {
      if (grade != _selectedGrade) {
        ref.watch(teacherTimetableProvider((grade, _dateString)));
      }
    }

    final config = configAsync.valueOrNull;
    final periodsPerDay = config?.periodsPerDay ?? 8;
    final periodTimes = <int, (String, String)>{};
    if (config?.periodTimes != null) {
      for (final pt in config!.periodTimes!) {
        final m = pt as Map<String, dynamic>;
        periodTimes[m['period'] as int] =
            (m['start'] as String, m['end'] as String);
      }
    }

    // Date strings that already have at least one slot saved for this grade
    final datesWithTimetable = timetableAsync.valueOrNull
            ?.map((s) => s.slotDate)
            .toSet() ??
        const <String>{};

    final isWide = MediaQuery.of(context).size.width >= 900;

    // ── Period editor widget (built from async data) ─────────────────────
    Widget periodEditor = timetableAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(teacherTimetableProvider((_selectedGrade, _dateString))),
      ),
      data: (slots) {
        final busyByPeriod = _computeBusyTeachers();
        final existingSlots = slots
            .where((s) => s.slotDate == _dateString)
            .toList()
          ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));
        final isUpdate = existingSlots.isNotEmpty;

        return teachersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(teachersListProvider)),
          data: (teachers) {
            _populateFromSlots(slots, teachers);

            final teacherSubjectsMap = <int, List<String>>{
              for (final t in teachers)
                if (t.teachableSubjects != null &&
                    t.teachableSubjects!.isNotEmpty)
                  t.id: t.teachableSubjects!,
            };

            final actionButtons = Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _saveAll(context, periodsPerDay),
                      icon: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(isUpdate ? Icons.update : Icons.save_outlined),
                      label: Text(
                        _saving
                            ? 'Saving…'
                            : isUpdate ? 'Update Timetable' : 'Save Timetable',
                        style: TextStyle(fontSize: R.fs(context, 14, min: 12, max: 16)),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: isUpdate ? AppColors.success : null,
                        padding: EdgeInsets.symmetric(
                            vertical: R.sp(context, 14, min: 10, max: 16)),
                      ),
                    ),
                  ),
                  if (isUpdate) ...[
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _confirmDelete(context),
                      icon: Icon(Icons.delete_outline,
                          size: R.fluid(context, 18, min: 16, max: 20)),
                      label: Text('Delete',
                          style: TextStyle(fontSize: R.fs(context, 14, min: 12, max: 16))),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: EdgeInsets.symmetric(
                          horizontal: R.sp(context, 16, min: 12, max: 20),
                          vertical: R.sp(context, 14, min: 10, max: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );

            return _PeriodList(
              periodsPerDay: periodsPerDay,
              periodTimes: periodTimes,
              teachers: teachers,
              teacherIds: _teacherIds,
              subjects: _subjects,
              comments: _comments,
              busyByPeriod: busyByPeriod,
              teacherSubjectsMap: teacherSubjectsMap,
              footer: actionButtons,
              onTeacherChanged: (p, id) => setState(() {
                _teacherIds[p] = id;
                if (id != null && teacherSubjectsMap.containsKey(id)) {
                  final allowed = teacherSubjectsMap[id]!;
                  if (_subjects[p] != null && !allowed.contains(_subjects[p])) {
                    _subjects[p] = null;
                  }
                }
              }),
              onSubjectChanged: (p, s) => setState(() => _subjects[p] = s),
              onCommentChanged: (p, c) =>
                  setState(() => _comments[p] = c.isEmpty ? null : c),
            );
          },
        );
      },
    );

    // ── Calendar panel widget ────────────────────────────────────────────
    final calendarPanel = _ScrollableCalendar(
      selectedDate: _selectedDate,
      datesWithTimetable: datesWithTimetable,
      onDateSelected: (date) => _onDateTapped(date),
    );

    // ── Web layout ───────────────────────────────────────────────────────
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: calendar + grade selector
          SizedBox(
            width: 380,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
              decoration: mindForgeCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: grade selector + selected date
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.school_outlined, size: 15, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Grade $_selectedGrade',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showGradePicker(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Change', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
                              Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primary),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(child: calendarPanel),
                ],
              ),
            ),
          ),
          // Right: period editor
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              decoration: mindForgeCardDecoration(),
              child: periodEditor,
            ),
          ),
        ],
      );
    }

    // ── Mobile layout ────────────────────────────────────────────────────
    return Column(
      children: [
        // Grade selector pill
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: _SelectorPill(
            label: 'Grade',
            value: 'Grade $_selectedGrade',
            showArrow: true,
            onTap: () => _showGradePicker(context),
          ),
        ),
        const SizedBox(height: 4),
        // Week strip
        _WeekStrip(
          weekStart: _weekStart,
          selectedDate: _selectedDate,
          datesWithTimetable: datesWithTimetable,
          onDateSelected: (date) {
            setState(() {
              _selectedDate = date;
              _weekStart = date.subtract(Duration(days: date.weekday - 1));
              _teacherIds.clear();
              _subjects.clear();
              _comments.clear();
              _populatedGrade = null;
              _populatedDate = null;
            });
          },
          onWeekChanged: (newWeekStart) =>
              setState(() => _weekStart = newWeekStart),
        ),
        const Divider(height: 1),
        // Selected date label
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: AppColors.primary.withValues(alpha: 0.06),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              DateFormat('EEE, d MMMM yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ]),
        ),
        // Period rows
        Expanded(child: periodEditor),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final dateLabel = DateFormat('d MMM yyyy').format(_selectedDate);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Timetable'),
        content: Text(
            'Delete the entire timetable for Grade $_selectedGrade on $dateLabel?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteTimetable(_selectedGrade, _dateString);
      ref.invalidate(teacherTimetableProvider((_selectedGrade, _dateString)));
      ref.invalidate(myTimetableProvider);
      // Clear form
      setState(() {
        _teacherIds.clear();
        _subjects.clear();
        _comments.clear();
        _populatedGrade = null;
        _populatedDate = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Timetable deleted — Grade $_selectedGrade · $dateLabel'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showGradePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Select Grade',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.grades.map((g) {
                final selected = g == _selectedGrade;
                return ChoiceChip(
                  label: Text('Grade $g'),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedGrade = g;
                      _teacherIds.clear();
                      _subjects.clear();
                      _comments.clear();
                      _populatedGrade = null;
                      _populatedDate = null;
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showDatePicker(BuildContext context, Set<String> datesWithTimetable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(children: [
                    Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Select Date',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _ScrollableCalendar(
                selectedDate: _selectedDate,
                datesWithTimetable: datesWithTimetable,
                onDateSelected: (date) {
                  _onDateTapped(date);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAll(BuildContext context, int periodsPerDay) async {
    final allPeriods = List.generate(periodsPerDay, (i) => i + 1);
    // A period is worth saving if it has a subject, teacher, or comment
    final hasAny = allPeriods.any((p) {
      final hasSubject = _subjects[p] != null && _subjects[p]!.isNotEmpty;
      final hasTeacher = _teacherIds[p] != null;
      final hasComment = _comments[p] != null && _comments[p]!.isNotEmpty;
      return hasSubject || hasTeacher || hasComment;
    });
    if (!hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in at least one period.')),
      );
      return;
    }

    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    try {
      for (final p in allPeriods) {
        final subject = _subjects[p];
        final teacherId = _teacherIds[p];
        final comment = _comments[p];
        // Skip empty periods (no subject, no teacher, no comment)
        final hasSubject = subject != null && subject.isNotEmpty;
        final hasTeacher = teacherId != null;
        final hasComment = comment != null && comment.isNotEmpty;
        if (!hasSubject && !hasTeacher && !hasComment) continue;
        await api.createTimetableSlot({
          'grade': _selectedGrade,
          'slot_date': _dateString,
          'period_number': p,
          'subject': hasSubject ? subject : '',
          if (hasTeacher) 'teacher_id': teacherId,
          'is_holiday': false,
          if (hasComment) 'comment': comment,
        });
      }
      ref.invalidate(teacherTimetableProvider((_selectedGrade, _dateString)));
      ref.invalidate(myTimetableProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timetable saved — Grade $_selectedGrade · ${DateFormat('d MMM yyyy').format(_selectedDate)}',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FULL TIMETABLE TAB
// ══════════════════════════════════════════════════════════════════════════════

class _FullTimetableTab extends ConsumerStatefulWidget {
  final void Function(int grade, DateTime date) onEditTimetable;
  const _FullTimetableTab({required this.onEditTimetable});

  @override
  ConsumerState<_FullTimetableTab> createState() => _FullTimetableTabState();
}

class _FullTimetableTabState extends ConsumerState<_FullTimetableTab> {
  late DateTime _selectedDate;
  late DateTime _weekStart;

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = now.weekday >= 6
        ? now.add(Duration(days: 8 - now.weekday))
        : now;
    _weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(teacherTimetableConfigProvider);
    final config = configAsync.valueOrNull;
    final periodTimes = <int, (String, String)>{};
    if (config?.periodTimes != null) {
      for (final pt in config!.periodTimes!) {
        final m = pt as Map<String, dynamic>;
        periodTimes[m['period'] as int] =
            (m['start'] as String, m['end'] as String);
      }
    }

    final today = DateTime.now();
    final isToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    final isWide = MediaQuery.of(context).size.width >= 900;

    final gradeList = ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: AppConstants.grades
          .map((grade) => _GradeSection(
                grade: grade,
                dateString: _dateString,
                selectedDate: _selectedDate,
                periodTimes: periodTimes,
                onEditTimetable: widget.onEditTimetable,
              ))
          .toList(),
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
              decoration: mindForgeCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(children: [
                      const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                          child: const Text('TODAY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                  const Divider(height: 1),
                  _WeekStrip(
                    weekStart: _weekStart,
                    selectedDate: _selectedDate,
                    datesWithTimetable: const {},
                    onDateSelected: (date) => setState(() => _selectedDate = date),
                    onWeekChanged: (newWeekStart) => setState(() => _weekStart = newWeekStart),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              decoration: mindForgeCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(children: [
                      Icon(Icons.school_outlined, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('All Grades',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(child: gradeList),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── Mobile layout ─────────────────────────────────────────────────────
    return Column(
      children: [
        _WeekStrip(
          weekStart: _weekStart,
          selectedDate: _selectedDate,
          datesWithTimetable: const {},
          onDateSelected: (date) => setState(() => _selectedDate = date),
          onWeekChanged: (newWeekStart) => setState(() => _weekStart = newWeekStart),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: AppColors.primary.withValues(alpha: 0.06),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              DateFormat('EEE, d MMMM yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                child: const Text('TODAY', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ],
          ]),
        ),
        Expanded(child: gradeList),
      ],
    );
  }
}

// ─── Grade section for Full Timetable tab ─────────────────────────────────────

class _GradeSection extends ConsumerStatefulWidget {
  final int grade;
  final String dateString;
  final DateTime selectedDate;
  final Map<int, (String, String)> periodTimes;
  final void Function(int grade, DateTime date) onEditTimetable;

  const _GradeSection({
    required this.grade,
    required this.dateString,
    required this.selectedDate,
    required this.periodTimes,
    required this.onEditTimetable,
  });

  @override
  ConsumerState<_GradeSection> createState() => _GradeSectionState();
}

class _GradeSectionState extends ConsumerState<_GradeSection> {
  bool _deleting = false;

  Future<void> _confirmDelete(BuildContext context) async {
    final dateLabel = DateFormat('d MMM yyyy').format(widget.selectedDate);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Timetable'),
        content: Text(
            'Delete the entire timetable for Grade ${widget.grade} on $dateLabel?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _deleting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteTimetable(widget.grade, widget.dateString);
      ref.invalidate(teacherTimetableProvider((widget.grade, widget.dateString)));
      ref.invalidate(myTimetableProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Timetable deleted — Grade ${widget.grade} · $dateLabel'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetableAsync =
        ref.watch(teacherTimetableProvider((widget.grade, widget.dateString)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grade header
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.school_outlined,
                  size: 16, color: AppColors.secondary),
              const SizedBox(width: 8),
              Text(
                'Grade ${widget.grade}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),

        timetableAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Error loading Grade ${widget.grade}',
                style:
                    const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
          data: (slots) {
            final daySlots = slots
                .where((s) => s.slotDate == widget.dateString)
                .toList()
              ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

            if (daySlots.isEmpty) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: mindForgeCardDecoration(),
                child: Row(
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 18,
                        color: AppColors.textMuted.withValues(alpha: 0.5)),
                    const SizedBox(width: 10),
                    const Text('No classes scheduled',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Period tiles
                ...daySlots.map((slot) {
                  final times = widget.periodTimes[slot.periodNumber];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: mindForgeCardDecoration(),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.12),
                        child: Text('P${slot.periodNumber}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ),
                      title: Text(
                        slot.isHoliday
                            ? 'Holiday'
                            : (slot.subject?.isNotEmpty == true
                                ? slot.subject!
                                : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (slot.teacherUsername != null)
                            Row(children: [
                              const Icon(Icons.person_outline,
                                  size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text(slot.teacherUsername!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ]),
                          if (times != null)
                            Row(children: [
                              const Icon(Icons.schedule,
                                  size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text('${times.$1}  –  ${times.$2}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ]),
                          if (slot.comment != null && slot.comment!.isNotEmpty)
                            Row(children: [
                              const Icon(Icons.comment_outlined,
                                  size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(slot.comment!,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                        fontStyle: FontStyle.italic),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                        ],
                      ),
                      trailing: Icon(
                        slot.isHoliday
                            ? Icons.beach_access
                            : Icons.book_outlined,
                        color: AppColors.primary.withValues(alpha: 0.6),
                        size: 18,
                      ),
                    ),
                  );
                }),

                // Edit + Delete buttons
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: Text('Update Grade ${widget.grade}'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          onPressed: _deleting
                              ? null
                              : () => widget.onEditTimetable(
                                  widget.grade, widget.selectedDate),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: _deleting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        onPressed:
                            _deleting ? null : () => _confirmDelete(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Selector pill ────────────────────────────────────────────────────────────

class _SelectorPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData? leadingIcon;
  final bool showArrow;
  final VoidCallback onTap;

  const _SelectorPill({
    required this.label,
    required this.value,
    required this.onTap,
    this.leadingIcon,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.primary.withValues(alpha: 0.04),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 13, color: AppColors.primary),
              const SizedBox(width: 4),
            ],
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            if (showArrow)
              const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ─── Calendar grid ────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? selectedDate;
  final Set<String> datesWithTimetable; // "YYYY-MM-DD" strings already configured
  final void Function(DateTime) onDateTapped;
  final bool compact;

  const _CalendarGrid({
    required this.month,
    required this.selectedDate,
    required this.datesWithTimetable,
    required this.onDateTapped,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1; // Mon=0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    final totalCells = ((startOffset + daysInMonth + 6) ~/ 7) * 7;
    final numWeeks = totalCells ~/ 7;

    return LayoutBuilder(builder: (context, constraints) {
      final cellSize = compact
          ? (constraints.maxWidth / 7).clamp(16.0, 22.0)
          : (constraints.maxWidth / 7).clamp(28.0, 36.0);
      final dotSize = compact ? 2.0 : 4.0;

      final rows = <Widget>[];
      for (int week = 0; week < numWeeks; week++) {
        final cells = <Widget>[];
        for (int col = 0; col < 7; col++) {
          final cellIndex = week * 7 + col;
          final dayNum = cellIndex - startOffset + 1;

          if (dayNum < 1 || dayNum > daysInMonth) {
            cells.add(Expanded(child: SizedBox(height: cellSize + dotSize + 2)));
            continue;
          }

          final date = DateTime(month.year, month.month, dayNum);
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final isSelected = selectedDate != null &&
              date.year == selectedDate!.year &&
              date.month == selectedDate!.month &&
              date.day == selectedDate!.day;
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
          final hasTimetable = datesWithTimetable.contains(dateStr);

          cells.add(Expanded(
            child: GestureDetector(
              onTap: () => onDateTapped(date),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.all(1),
                    height: cellSize,
                    width: cellSize,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isToday
                              ? AppColors.accent.withValues(alpha: 0.15)
                              : hasTimetable
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : null,
                      shape: BoxShape.circle,
                      border: isToday && !isSelected
                          ? Border.all(
                              color: AppColors.accent.withValues(alpha: 0.8),
                              width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: cellSize * 0.38,
                          fontWeight: isSelected || isToday || hasTimetable
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : isToday
                                  ? AppColors.accent
                                  : hasTimetable
                                      ? AppColors.success
                                      : col >= 5
                                          ? AppColors.error.withValues(alpha: 0.55)
                                          : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (hasTimetable && !isSelected)
                    Container(
                      width: dotSize,
                      height: dotSize,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    SizedBox(height: dotSize + 1),
                ],
              ),
            ),
          ));
        }
        rows.add(Row(children: cells));
        if (week < numWeeks - 1) rows.add(const SizedBox(height: 1));
      }

      return Column(children: rows);
    });
  }
}

// ─── Scrollable multi-month calendar ─────────────────────────────────────────

class _ScrollableCalendar extends StatefulWidget {
  final DateTime selectedDate;
  final Set<String> datesWithTimetable;
  final void Function(DateTime) onDateSelected;
  final int monthsBack;
  final int monthsForward;

  const _ScrollableCalendar({
    required this.selectedDate,
    required this.datesWithTimetable,
    required this.onDateSelected,
    this.monthsBack = 3,
    this.monthsForward = 9,
  });

  @override
  State<_ScrollableCalendar> createState() => _ScrollableCalendarState();
}

class _ScrollableCalendarState extends State<_ScrollableCalendar> {
  // Approximate rendered height of one month block (header + weekdays + 5-6 rows)
  static const double _kMonthHeight = 370.0;
  final ScrollController _ctrl = ScrollController();
  late final List<DateTime> _months;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _months = List.generate(
      widget.monthsBack + 1 + widget.monthsForward,
      (i) => DateTime(now.year, now.month - widget.monthsBack + i),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToSelected());
  }

  void _jumpToSelected() {
    final sel = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    final idx = _months.indexWhere(
        (m) => m.year == sel.year && m.month == sel.month);
    if (idx < 0 || !_ctrl.hasClients) return;
    final offset =
        (idx * _kMonthHeight).clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.jumpTo(offset);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _ctrl,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
      itemCount: _months.length,
      itemBuilder: (context, i) => _MonthSection(
        month: _months[i],
        selectedDate: widget.selectedDate,
        datesWithTimetable: widget.datesWithTimetable,
        onDateTapped: widget.onDateSelected,
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  final DateTime month;
  final DateTime? selectedDate;
  final Set<String> datesWithTimetable;
  final void Function(DateTime) onDateTapped;

  const _MonthSection({
    required this.month,
    required this.selectedDate,
    required this.datesWithTimetable,
    required this.onDateTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              DateFormat('MMMM yyyy').format(month),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textMuted)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          _CalendarGrid(
            month: month,
            selectedDate: selectedDate,
            datesWithTimetable: datesWithTimetable,
            onDateTapped: onDateTapped,
            compact: false,
          ),
        ],
      ),
    );
  }
}

// ─── Period list (unchanged logic) ───────────────────────────────────────────

class _PeriodList extends StatelessWidget {
  final int periodsPerDay;
  final Map<int, (String, String)> periodTimes;
  final List<UserModel> teachers;
  final Map<int, int?> teacherIds;
  final Map<int, String?> subjects;
  final Map<int, String?> comments;
  final Map<int, Map<int, int>> busyByPeriod; // period → {teacherId: busyGrade}
  final Map<int, List<String>> teacherSubjectsMap;
  final Widget? footer;
  final void Function(int, int?) onTeacherChanged;
  final void Function(int, String?) onSubjectChanged;
  final void Function(int, String) onCommentChanged;

  const _PeriodList({
    required this.periodsPerDay,
    required this.periodTimes,
    required this.teachers,
    required this.teacherIds,
    required this.subjects,
    required this.comments,
    required this.busyByPeriod,
    required this.teacherSubjectsMap,
    this.footer,
    required this.onTeacherChanged,
    required this.onSubjectChanged,
    required this.onCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final periods = List.generate(periodsPerDay, (i) => i + 1);
    final hasFooter = footer != null;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: periods.length + (hasFooter ? 1 : 0),
      itemBuilder: (ctx, index) {
        // Footer as last item
        if (hasFooter && index == periods.length) return footer!;

        final period = periods[index];
        final selectedTeacherId = teacherIds[period];
        final allowedSubjects =
            selectedTeacherId != null &&
                    teacherSubjectsMap.containsKey(selectedTeacherId)
                ? teacherSubjectsMap[selectedTeacherId]!
                : AppConstants.subjects;
        return _PeriodRow(
          period: period,
          timeRange: periodTimes[period],
          teachers: teachers,
          busyTeacherGrades: busyByPeriod[period] ?? {},
          selectedTeacherId: selectedTeacherId,
          selectedSubject: subjects[period],
          comment: comments[period],
          allowedSubjects: allowedSubjects,
          onTeacherChanged: (id) => onTeacherChanged(period, id),
          onSubjectChanged: (s) => onSubjectChanged(period, s),
          onCommentChanged: (c) => onCommentChanged(period, c),
        );
      },
    );
  }
}

// ─── Single period row ────────────────────────────────────────────────────────

class _PeriodRow extends StatelessWidget {
  final int period;
  final (String, String)? timeRange;
  final List<UserModel> teachers;
  final Map<int, int> busyTeacherGrades; // teacherId → busyGrade
  final int? selectedTeacherId;
  final String? selectedSubject;
  final String? comment;
  final List<String> allowedSubjects;
  final void Function(int?) onTeacherChanged;
  final void Function(String?) onSubjectChanged;
  final void Function(String) onCommentChanged;

  const _PeriodRow({
    required this.period,
    required this.timeRange,
    required this.teachers,
    required this.busyTeacherGrades,
    required this.selectedTeacherId,
    required this.selectedSubject,
    this.comment,
    required this.allowedSubjects,
    required this.onTeacherChanged,
    required this.onSubjectChanged,
    required this.onCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: mindForgeCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period badge + time header
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text('P$period',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              if (timeRange != null) ...[
                const SizedBox(width: 10),
                Text(
                  '${timeRange!.$1}  –  ${timeRange!.$2}',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Teacher dropdown — full width
          DropdownButtonFormField<int?>(
            value: selectedTeacherId,
            decoration: const InputDecoration(
              labelText: 'Teacher',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<int?>(
                  value: null, child: Text('— None —')),
              ...teachers.map((t) {
                final busyGrade = busyTeacherGrades[t.id];
                final busy = busyGrade != null;
                return DropdownMenuItem<int?>(
                  value: t.id,
                  enabled: !busy,
                  child: Text(
                    busy
                        ? '${t.username}  (Busy: Grade $busyGrade)'
                        : t.username,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: busy ? Colors.grey : null),
                  ),
                );
              }),
            ],
            onChanged: onTeacherChanged,
          ),
          const SizedBox(height: 10),

          // Subject dropdown — full width
          DropdownButtonFormField<String?>(
            value: selectedSubject != null &&
                    allowedSubjects.contains(selectedSubject)
                ? selectedSubject
                : null,
            decoration: const InputDecoration(
              labelText: 'Subject',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('— None —')),
              ...allowedSubjects.map((s) => DropdownMenuItem<String?>(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: onSubjectChanged,
          ),
          const SizedBox(height: 10),

          // Comment text field
          TextFormField(
            initialValue: comment ?? '',
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'e.g. Bring textbook, Test today…',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            maxLength: 300,
            onChanged: onCommentChanged,
          ),
        ],
      ),
    );
  }
}

// ─── Week Strip ───────────────────────────────────────────────────────────────

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart; // always a Monday
  final DateTime selectedDate;
  final Set<String> datesWithTimetable;
  final void Function(DateTime) onDateSelected;
  final void Function(DateTime) onWeekChanged;

  const _WeekStrip({
    required this.weekStart,
    required this.selectedDate,
    required this.datesWithTimetable,
    required this.onDateSelected,
    required this.onWeekChanged,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final monthLabel = DateFormat('MMMM yyyy').format(weekStart);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month label + prev/next arrows
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () =>
                    onWeekChanged(weekStart.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () =>
                    onWeekChanged(weekStart.add(const Duration(days: 7))),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Day cells
          Row(
            children: days.map((date) {
              final isSelected = date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;
              final isToday = date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              final hasTimetable = datesWithTimetable.contains(dateStr);
              final isWeekend = date.weekday >= 6;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('E').format(date)[0],
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isWeekend
                              ? AppColors.error.withOpacity(0.7)
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.primary
                              : isToday
                                  ? AppColors.primary.withOpacity(0.12)
                                  : Colors.transparent,
                        ),
                        child: Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : isToday
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Dot if timetable exists
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasTimetable
                              ? (isSelected
                                  ? Colors.white
                                  : AppColors.accent)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}
