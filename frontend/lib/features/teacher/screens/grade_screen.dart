import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/test.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';

class TeacherGradeScreen extends ConsumerStatefulWidget {
  const TeacherGradeScreen({super.key});

  @override
  ConsumerState<TeacherGradeScreen> createState() => _TeacherGradeScreenState();
}

class _TeacherGradeScreenState extends ConsumerState<TeacherGradeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TeacherScaffold(
      appBar: AppBar(
        title: const Text('Grades'),
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
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'All Grades'),
            Tab(text: 'Enter Offline Marks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _AllGradesTab(),
          _EnterOfflineMarksTab(),
        ],
      ),
    );
  }
}

// ─── Tab 1: All Grades ────────────────────────────────────────────────────────

class _AllGradesTab extends ConsumerStatefulWidget {
  const _AllGradesTab();

  @override
  ConsumerState<_AllGradesTab> createState() => _AllGradesTabState();
}

class _AllGradesTabState extends ConsumerState<_AllGradesTab> {
  int? _filterGrade;
  int? _filterStudentId;
  String? _filterSubject;

  @override
  Widget build(BuildContext context) {
    // Load students only when a grade is selected
    final studentsAsync = _filterGrade != null
        ? ref.watch(studentsInGradeProvider(_filterGrade!))
        : null;
    final students = studentsAsync?.valueOrNull ?? [];
    final studentMap = {for (final s in students) s.id: s.username};

    final gradesAsync =
        ref.watch(teacherGradesProvider((_filterSubject, _filterStudentId)));

    return Column(
      children: [
        // ── Filter panel ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: AppColors.cardBackground,
          child: Column(
            children: [
              // Row 1: Grade + Subject
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _filterGrade,
                      decoration: const InputDecoration(
                          labelText: 'Grade', isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All Grades')),
                        ...AppConstants.grades.map((g) =>
                            DropdownMenuItem(
                                value: g, child: Text('Grade $g'))),
                      ],
                      onChanged: (v) => setState(() {
                        _filterGrade = v;
                        _filterStudentId = null; // reset student on grade change
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _filterSubject,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Subject', isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('All Subjects',
                                overflow: TextOverflow.ellipsis)),
                        ...AppConstants.subjects.map((s) =>
                            DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _filterSubject = v),
                    ),
                  ),
                ],
              ),
              // Row 2: Student (only when grade selected)
              if (_filterGrade != null) ...[
                const SizedBox(height: 10),
                studentsAsync!.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (studs) => DropdownButtonFormField<int?>(
                    initialValue: _filterStudentId,
                    decoration: const InputDecoration(
                        labelText: 'Student', isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Students')),
                      ...studs.map((s) => DropdownMenuItem(
                          value: s.id, child: Text(s.username))),
                    ],
                    onChanged: (v) =>
                        setState(() => _filterStudentId = v),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Grade list ──────────────────────────────────────────────────────
        Expanded(
          child: gradesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (allGrades) {
              // If a grade (class) is selected, show only students from that class
              final grades = _filterGrade != null && studentMap.isNotEmpty
                  ? allGrades
                      .where((g) => studentMap.containsKey(g.studentId))
                      .toList()
                  : allGrades;

              if (grades.isEmpty) {
                return const Center(
                    child: Text('No grade records found.',
                        style: TextStyle(color: AppColors.textMuted)));
              }
              final Map<String, List<double>> subjectPcts = {};
              for (final g in grades) {
                subjectPcts
                    .putIfAbsent(g.subject, () => [])
                    .add(g.percentage);
              }
              return RefreshIndicator(
                onRefresh: () => ref.refresh(
                    teacherGradesProvider((_filterSubject, _filterStudentId))
                        .future),
                child: ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: grades.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final g = grades[i];
                    final pcts = subjectPcts[g.subject]!;
                    return _GradeTile(
                      grade: g,
                      studentName: studentMap[g.studentId],
                      classHigh:
                          pcts.reduce((a, b) => a > b ? a : b),
                      classLow:
                          pcts.reduce((a, b) => a < b ? a : b),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GradeTile extends StatelessWidget {
  final GradeModel grade;
  final String? studentName;
  final double classHigh;
  final double classLow;

  const _GradeTile({
    required this.grade,
    required this.classHigh,
    required this.classLow,
    this.studentName,
  });

  Color _pctColor(double pct) {
    if (pct >= 75) return AppColors.success;
    if (pct >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final pctColor = _pctColor(grade.percentage);
    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: R.fluid(context, 52, min: 44, max: 60),
            height: R.fluid(context, 52, min: 44, max: 60),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: grade.percentage / 100,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                  strokeWidth: 5,
                ),
                Text('${grade.percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: R.fs(context, 10, min: 9, max: 12),
                        fontWeight: FontWeight.bold,
                        color: pctColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(grade.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(grade.chapter, style: Theme.of(context).textTheme.bodySmall),
                Text('${grade.marksObtained}/${grade.maxMarks} marks',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: R.fs(context, 12, min: 10, max: 14))),
                if (studentName != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(studentName!,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('High: ${classHigh.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: R.fs(context, 11, min: 10, max: 13),
                      color: AppColors.success)),
              Text('Low: ${classLow.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: R.fs(context, 11, min: 10, max: 13),
                      color: AppColors.error)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(grade.gradeType.toUpperCase(),
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tab 2: Enter Offline Marks ───────────────────────────────────────────────

class _EnterOfflineMarksTab extends ConsumerStatefulWidget {
  const _EnterOfflineMarksTab();

  @override
  ConsumerState<_EnterOfflineMarksTab> createState() => _EnterOfflineMarksTabState();
}

class _EnterOfflineMarksTabState extends ConsumerState<_EnterOfflineMarksTab> {
  int _selectedGrade = 8;

  void _openGradeEntry(TestModel test) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GradeEntrySheet(test: test, ref: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(teacherTestsProvider(_selectedGrade));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Grade selector ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<int>(
            initialValue: _selectedGrade,
            decoration: const InputDecoration(labelText: 'Grade', isDense: true),
            items: [8, 9, 10]
                .map((g) => DropdownMenuItem(value: g, child: Text('Grade $g')))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedGrade = v);
            },
          ),
        ),

        // ── Offline tests list ───────────────────────────────────────────────
        Expanded(
          child: testsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (tests) {
              final offlineTests =
                  tests.where((t) => t.testType == 'offline').toList();
              if (offlineTests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.print_outlined,
                          size: 56, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No offline tests for Grade $_selectedGrade yet.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: offlineTests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) =>
                    _OfflineTestCard(
                      test: offlineTests[i],
                      onEnterGrades: () => _openGradeEntry(offlineTests[i]),
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Offline test card with marks status ──────────────────────────────────────

class _OfflineTestCard extends ConsumerWidget {
  final TestModel test;
  final VoidCallback onEnterGrades;

  const _OfflineTestCard({required this.test, required this.onEnterGrades});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesAsync = ref.watch(testGradesProvider(test.id));
    final hasMarks = gradesAsync.valueOrNull?.isNotEmpty ?? false;

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: R.fluid(context, 44, min: 40, max: 52),
            height: R.fluid(context, 44, min: 40, max: 52),
            decoration: BoxDecoration(
              color: hasMarks
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasMarks ? Icons.check_circle_outline : Icons.print_outlined,
              color: hasMarks ? AppColors.success : AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(test.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${test.subject} · Grade ${test.grade} · ${test.totalMarks.toInt()} marks',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: test.isPublished
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        test.isPublished ? 'Published' : 'Draft',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: test.isPublished
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                    if (hasMarks)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Marks Entered',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (gradesAsync.isLoading)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                ElevatedButton.icon(
                  icon: Icon(
                    hasMarks ? Icons.edit : Icons.edit_outlined,
                    size: 15,
                  ),
                  label: Text(
                    hasMarks ? 'Edit Marks' : 'Enter Grades',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasMarks ? AppColors.primary : null,
                    foregroundColor: hasMarks ? Colors.white : null,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onEnterGrades,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet: student mark entry for one test ────────────────────────────

class _GradeEntrySheet extends ConsumerStatefulWidget {
  final TestModel test;
  final WidgetRef ref;

  const _GradeEntrySheet({required this.test, required this.ref});

  @override
  ConsumerState<_GradeEntrySheet> createState() => _GradeEntrySheetState();
}

class _GradeEntrySheetState extends ConsumerState<_GradeEntrySheet> {
  final Map<int, TextEditingController> _marksCtrls = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _marksCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveMarks(List<UserModel> students) async {
    final grades = <Map<String, dynamic>>[];
    for (final student in students) {
      final ctrl = _marksCtrls[student.id];
      final marks = double.tryParse(ctrl?.text.trim() ?? '');
      if (marks == null) continue;
      if (marks < 0 || marks > widget.test.totalMarks) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${student.username}: marks must be 0 – ${widget.test.totalMarks.toInt()}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      grades.add({'student_id': student.id, 'marks_obtained': marks});
    }

    if (grades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter marks for at least one student.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.saveOfflineGrades(widget.test.id, grades);
      ref.invalidate(teacherGradesProvider);
      ref.invalidate(testGradesProvider(widget.test.id));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Grades saved successfully!'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsInGradeProvider(widget.test.grade));
    final existingGradesAsync = ref.watch(testGradesProvider(widget.test.id));
    final existingMap = {
      for (final g in existingGradesAsync.valueOrNull ?? [])
        (g['student_id'] as int): (g['marks_obtained'] as num).toDouble()
    };
    final maxH = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(
                  existingMap.isNotEmpty
                      ? Icons.edit
                      : Icons.print_outlined,
                  color: existingMap.isNotEmpty
                      ? AppColors.primary
                      : AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existingMap.isNotEmpty
                            ? 'Edit Marks'
                            : 'Enter Marks',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${widget.test.title} · out of ${widget.test.totalMarks.toInt()} marks',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Student list
          Flexible(
            child: studentsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error loading students: $e')),
              data: (students) {
                if (students.isEmpty) {
                  return const Center(
                      child: Text('No students in this grade.'));
                }
                for (final s in students) {
                  _marksCtrls.putIfAbsent(s.id, () {
                    final existing = existingMap[s.id];
                    final text = existing != null
                        ? (existing % 1 == 0
                            ? existing.toInt().toString()
                            : existing.toString())
                        : '';
                    return TextEditingController(text: text);
                  });
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: students.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    if (i == students.length) {
                      return Padding(
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom:
                              MediaQuery.of(context).viewInsets.bottom + 12,
                        ),
                        child: ElevatedButton.icon(
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.save),
                          label: Text(
                              _saving ? 'Saving…' : 'Save All Grades'),
                          onPressed:
                              _saving ? null : () => _saveMarks(students),
                        ),
                      );
                    }
                    final s = students[i];
                    return Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          radius: 18,
                          child: Text(
                            s.username.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                        ),
                        SizedBox(
                          width: 88,
                          child: TextField(
                            controller: _marksCtrls[s.id],
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                                  '/ ${widget.test.totalMarks.toInt()}',
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8)),
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
