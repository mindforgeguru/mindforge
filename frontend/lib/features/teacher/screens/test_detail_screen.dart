import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/test.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/teacher_provider.dart';

class TestDetailScreen extends ConsumerStatefulWidget {
  final TestModel test;
  const TestDetailScreen({super.key, required this.test});

  @override
  ConsumerState<TestDetailScreen> createState() => _TestDetailScreenState();
}

class _TestDetailScreenState extends ConsumerState<TestDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Local mutable copy of questions (so edits are reflected immediately)
  late List<Map<String, dynamic>> _questions;
  late double _totalMarks;
  bool _downloadingPdf = false;
  bool _downloadingKey = false;
  bool _deleting = false;
  bool _savingQuestions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _questions = List<Map<String, dynamic>>.from(
      (widget.test.questions ?? []).map((q) => Map<String, dynamic>.from(q)),
    );
    _totalMarks = widget.test.totalMarks;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _recalcMarks() {
    setState(() {
      _totalMarks = _questions.fold(0, (s, q) => s + (q['marks'] as int? ?? 1));
    });
  }

  // ── Delete test ─────────────────────────────────────────────────────────────

  Future<void> _deleteTest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Test?'),
        content: Text(
            'Delete "${widget.test.title}"? This cannot be undone and will remove all student submissions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await ref.read(apiClientProvider).deleteTest(widget.test.id);
      ref.invalidate(teacherTestsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
        );
        setState(() => _deleting = false);
      }
    }
  }

  // ── Save edited questions ────────────────────────────────────────────────────

  Future<void> _saveQuestions() async {
    setState(() => _savingQuestions = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .updateTestQuestions(widget.test.id, _questions);
      ref.invalidate(teacherTestsProvider);
      final newQuestions = (updated['questions'] as List)
          .map((q) => Map<String, dynamic>.from(q as Map))
          .toList();
      setState(() {
        _questions = newQuestions;
        _totalMarks = (updated['total_marks'] as num).toDouble();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Test saved!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _savingQuestions = false);
    }
  }

  // ── Edit a single question ───────────────────────────────────────────────────

  Future<void> _editQuestion(int index) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditQuestionDialog(question: _questions[index]),
    );
    if (updated == null) return;
    setState(() {
      _questions[index] = updated;
      _recalcMarks();
    });
  }

  // ── Delete a single question ─────────────────────────────────────────────────

  void _deleteQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
      // Re-number
      for (var i = 0; i < _questions.length; i++) {
        _questions[i]['id'] = i + 1;
      }
      _recalcMarks();
    });
  }

  // ── PDF download ─────────────────────────────────────────────────────────────

  Future<void> _downloadPdf({required bool testPaper}) async {
    setState(() => testPaper ? _downloadingPdf = true : _downloadingKey = true);
    try {
      final api = ref.read(apiClientProvider);
      final bytes = Uint8List.fromList(
        testPaper
            ? await api.downloadTestPdf(widget.test.id)
            : await api.downloadAnswerKeyPdf(widget.test.id),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: testPaper
            ? '${widget.test.title}_test.pdf'
            : '${widget.test.title}_answer_key.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(
            () => testPaper ? _downloadingPdf = false : _downloadingKey = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
    final hasEdits = _questionsEdited();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.title, overflow: TextOverflow.ellipsis),
        actions: [
          // Save button — only visible when there are unsaved edits
          if (hasEdits)
            _savingQuestions
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))),
                  )
                : IconButton(
                    icon: const Icon(Icons.save),
                    tooltip: 'Save changes',
                    onPressed: _saveQuestions,
                  ),
          // Delete test button
          _deleting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))),
                )
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete test',
                  color: AppColors.error,
                  onPressed: _deleteTest,
                ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Preview & Edit'),
            Tab(text: 'Grades'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: TabBarView(
          controller: _tabController,
          children: [
            _PreviewEditTab(
              test: t,
              questions: _questions,
              totalMarks: _totalMarks,
              hasEdits: hasEdits,
              downloadingPdf: _downloadingPdf,
              downloadingKey: _downloadingKey,
              onDownloadPdf: () => _downloadPdf(testPaper: true),
              onDownloadKey: () => _downloadPdf(testPaper: false),
              onEdit: _editQuestion,
              onDelete: _deleteQuestion,
              onSave: hasEdits ? _saveQuestions : null,
              saving: _savingQuestions,
            ),
            t.testType == 'online'
                ? _OnlineGradesTab(test: t)
                : _OfflineGradeEntryTab(test: t),
          ],
        ),
      ),
    );
  }

  bool _questionsEdited() {
    final original = widget.test.questions ?? [];
    if (original.length != _questions.length) return true;
    for (var i = 0; i < original.length; i++) {
      final o = original[i];
      final n = _questions[i];
      if (o['question'] != n['question'] ||
          o['answer'] != n['answer'] ||
          o['marks'] != n['marks']) { return true; }
    }
    return false;
  }
}

// ─── Preview + Edit Tab ───────────────────────────────────────────────────────

class _PreviewEditTab extends StatelessWidget {
  final TestModel test;
  final List<Map<String, dynamic>> questions;
  final double totalMarks;
  final bool hasEdits;
  final bool downloadingPdf;
  final bool downloadingKey;
  final bool saving;
  final VoidCallback onDownloadPdf;
  final VoidCallback onDownloadKey;
  final Future<void> Function(int) onEdit;
  final void Function(int) onDelete;
  final VoidCallback? onSave;

  const _PreviewEditTab({
    required this.test,
    required this.questions,
    required this.totalMarks,
    required this.hasEdits,
    required this.downloadingPdf,
    required this.downloadingKey,
    required this.saving,
    required this.onDownloadPdf,
    required this.onDownloadKey,
    required this.onEdit,
    required this.onDelete,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Test info card ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: mindForgeCardDecoration(
              color: AppColors.primary.withValues(alpha: 0.05)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: test.testType == 'online'
                        ? AppColors.secondary.withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.15),
                    child: Icon(
                      test.testType == 'online'
                          ? Icons.computer
                          : Icons.print_outlined,
                      color: test.testType == 'online'
                          ? AppColors.secondary
                          : AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(test.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('${test.subject} · Grade ${test.grade}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _InfoChip(
                      icon: Icons.assignment,
                      label: '${questions.length} questions'),
                  _InfoChip(
                      icon: Icons.grade,
                      label: '${totalMarks.toInt()} marks'),
                  if (test.timeLimitMinutes != null)
                    _InfoChip(
                        icon: Icons.timer,
                        label: '${questions.length} min'),
                  _InfoChip(
                      icon: test.testType == 'online'
                          ? Icons.wifi
                          : Icons.print_outlined,
                      label: test.testType.toUpperCase()),
                ],
              ),
            ],
          ),
        ),

        // ── Unsaved changes banner ─────────────────────────────────────────────
        if (hasEdits) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Unsaved changes',
                      style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onSave,
                        child: const Text('Save',
                            style: TextStyle(
                                fontSize: 13, color: Colors.white)),
                      ),
              ],
            ),
          ),
        ],

        // ── Offline PDF buttons ───────────────────────────────────────────────
        if (test.testType == 'offline') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: downloadingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('Test Paper PDF'),
                  onPressed: downloadingPdf ? null : onDownloadPdf,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: downloadingKey
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.vpn_key_outlined),
                  label: const Text('Answer Key PDF'),
                  onPressed: downloadingKey ? null : onDownloadKey,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 20),

        // ── Questions header ──────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'Questions (${questions.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${totalMarks.toInt()} marks total',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (questions.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No questions. Delete this test and generate a new one.'),
            ),
          )
        else
          ...questions.asMap().entries.map(
                (e) => _EditableQuestionCard(
                  index: e.key,
                  question: e.value,
                  onEdit: () => onEdit(e.key),
                  onDelete: () => onDelete(e.key),
                ),
              ),
      ],
    );
  }
}

// ─── Editable question card ───────────────────────────────────────────────────

class _EditableQuestionCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> question;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EditableQuestionCard({
    required this.index,
    required this.question,
    required this.onEdit,
    required this.onDelete,
  });

  static const _srcTags = {
    1: ('[P]',  Color(0xFF1565C0)),
    2: ('[E]',  Color(0xFF2E7D32)),
    3: ('[~P]', Color(0xFF1976D2)),
    4: ('[~E]', Color(0xFF388E3C)),
    5: ('[AI]', Color(0xFF6A1B9A)),
  };

  Widget? _sourceChip(Map<String, dynamic> q) {
    final raw = q['source_category'];
    if (raw == null) return null;
    final cat = (raw as num).toInt();
    final entry = _srcTags[cat];
    if (entry == null) return null;
    final (label, color) = entry;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'mcq':
        return AppColors.secondary;
      case 'true_false':
        return AppColors.warning;
      case 'fill_blank':
        return AppColors.accent;
      case 'short_answer':
        return AppColors.primary;
      case 'long_answer':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'mcq':
        return 'MCQ';
      case 'true_false':
        return 'True/False';
      case 'fill_blank':
        return 'Fill Blank';
      case 'vsa':
        return 'VSA';
      case 'short_answer':
        return 'Short Answer';
      case 'long_answer':
        return 'Long Answer';
      case 'numerical':
        return 'Numerical';
      default:
        return type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final qType = question['type'] as String? ?? 'vsa';
    final qText = question['question'] as String? ?? '';
    final marks = question['marks'] as int? ?? 1;
    final options = question['options'] as Map<String, dynamic>?;
    final answer = question['answer'];
    final typeColor = _typeColor(qType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: mindForgeCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: typeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _typeLabel(qType),
                    style: TextStyle(
                        fontSize: 10,
                        color: typeColor,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                if (_sourceChip(question) != null) ...[
                  const SizedBox(width: 5),
                  _sourceChip(question)!,
                ],
                const Spacer(),
                Text(
                  '$marks mark${marks > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.primary),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit question',
                ),
                const SizedBox(width: 4),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.error),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete question',
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Question text
            Text(qText,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),

            // MCQ options
            if (options != null) ...[
              const SizedBox(height: 6),
              ...['A', 'B', 'C', 'D']
                  .where((k) => options.containsKey(k))
                  .map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Text(
                        '($k) ${options[k]}',
                        style: TextStyle(
                          fontSize: 13,
                          color: answer == k || answer == options[k]
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontWeight: answer == k || answer == options[k]
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
            ],

            // Answer
            if (answer != null && answer.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Answer: $answer',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Edit question dialog ─────────────────────────────────────────────────────

class _EditQuestionDialog extends StatefulWidget {
  final Map<String, dynamic> question;
  const _EditQuestionDialog({required this.question});

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  late final TextEditingController _questionCtrl;
  late final TextEditingController _answerCtrl;
  late final TextEditingController _optACtrl;
  late final TextEditingController _optBCtrl;
  late final TextEditingController _optCCtrl;
  late final TextEditingController _optDCtrl;
  late int _marks;
  late String _qType;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _qType = q['type'] as String? ?? 'mcq';
    _questionCtrl =
        TextEditingController(text: q['question'] as String? ?? '');
    _answerCtrl =
        TextEditingController(text: q['answer'] as String? ?? '');
    _marks = q['marks'] as int? ?? 1;
    final opts = q['options'] as Map<String, dynamic>? ?? {};
    _optACtrl = TextEditingController(text: opts['A'] as String? ?? '');
    _optBCtrl = TextEditingController(text: opts['B'] as String? ?? '');
    _optCCtrl = TextEditingController(text: opts['C'] as String? ?? '');
    _optDCtrl = TextEditingController(text: opts['D'] as String? ?? '');
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _answerCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    _optCCtrl.dispose();
    _optDCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildResult() {
    final q = Map<String, dynamic>.from(widget.question);
    q['question'] = _questionCtrl.text.trim();
    q['answer'] = _answerCtrl.text.trim();
    q['marks'] = _marks;
    if (_qType == 'mcq') {
      q['options'] = {
        'A': _optACtrl.text.trim(),
        'B': _optBCtrl.text.trim(),
        'C': _optCCtrl.text.trim(),
        'D': _optDCtrl.text.trim(),
      };
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    final isMcq = _qType == 'mcq';
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title row
            Row(
              children: [
                const Icon(Icons.edit, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Edit Question',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Question text
            TextField(
              controller: _questionCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Question Text',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            // MCQ options
            if (isMcq) ...[
              const Text('Options',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              _OptionField(label: 'A', controller: _optACtrl),
              _OptionField(label: 'B', controller: _optBCtrl),
              _OptionField(label: 'C', controller: _optCCtrl),
              _OptionField(label: 'D', controller: _optDCtrl),
              const SizedBox(height: 6),
              const Text(
                'Correct Answer — enter the option letter (A/B/C/D)',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ] else ...[
              const Text(
                'Correct Answer',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 4),
            TextField(
              controller: _answerCtrl,
              maxLines: isMcq ? 1 : 3,
              decoration: InputDecoration(
                labelText: isMcq ? 'Correct option (e.g. A)' : 'Correct Answer',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Marks
            Row(
              children: [
                const Text('Marks: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _marks > 1
                      ? () => setState(() => _marks--)
                      : null,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$_marks',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _marks++),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Save / Cancel
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_questionCtrl.text.trim().isEmpty) return;
                      Navigator.pop(context, _buildResult());
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _OptionField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'Option $label',
          border: const OutlineInputBorder(),
          isDense: true,
          prefixText: '($label) ',
          prefixStyle: const TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
      ),
    );
  }
}

// ─── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Online Grades Tab ─────────────────────────────────────────────────────────

class _OnlineGradesTab extends ConsumerWidget {
  final TestModel test;
  const _OnlineGradesTab({required this.test});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(testSubmissionsProvider(test.id));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(testSubmissionsProvider(test.id)),
      child: subsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(testSubmissionsProvider(test.id))),
        data: (submissions) {
          if (submissions.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(
                      child: Text('No submissions yet.',
                          textAlign: TextAlign.center)),
                )
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: mindForgeCardDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.05)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                        label: 'Submitted',
                        value: '${submissions.length}'),
                    _StatItem(
                        label: 'Avg Score',
                        value: _avgScore(submissions, test.totalMarks)),
                    _StatItem(
                        label: 'Max Marks',
                        value: '${test.totalMarks.toInt()}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...submissions.map((s) => _SubmissionTile(
                    submission: s,
                    totalMarks: test.totalMarks,
                  )),
            ],
          );
        },
      ),
    );
  }

  String _avgScore(List<Map<String, dynamic>> subs, double totalMarks) {
    final scores = subs
        .where((s) => s['score'] != null)
        .map((s) => (s['score'] as num).toDouble())
        .toList();
    if (scores.isEmpty) return '—';
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    if (totalMarks > 0) {
      return '${(avg / totalMarks * 100).toStringAsFixed(0)}%';
    }
    return avg.toStringAsFixed(1);
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  final Map<String, dynamic> submission;
  final double totalMarks;
  const _SubmissionTile(
      {required this.submission, required this.totalMarks});

  @override
  Widget build(BuildContext context) {
    final score = (submission['score'] as num?)?.toDouble();
    final pct =
        score != null && totalMarks > 0 ? (score / totalMarks * 100) : null;
    final pctColor = pct == null
        ? AppColors.textMuted
        : pct >= 75
            ? AppColors.success
            : pct >= 50
                ? AppColors.warning
                : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: mindForgeCardDecoration(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: pctColor.withValues(alpha: 0.15),
          child: Text(
            pct != null ? '${pct.toStringAsFixed(0)}%' : '?',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: pctColor),
          ),
        ),
        title: Text(submission['student_name'] as String? ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(submission['auto_submitted'] == true
            ? 'Auto-submitted'
            : 'Submitted'),
        trailing: score != null
            ? Text(
                '${score.toStringAsFixed(1)} / ${totalMarks.toInt()}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pctColor,
                    fontSize: 14),
              )
            : const Text('—',
                style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}

// ─── Offline Grade Entry Tab ──────────────────────────────────────────────────

class _OfflineGradeEntryTab extends ConsumerStatefulWidget {
  final TestModel test;
  const _OfflineGradeEntryTab({required this.test});

  @override
  ConsumerState<_OfflineGradeEntryTab> createState() =>
      _OfflineGradeEntryTabState();
}

class _OfflineGradeEntryTabState
    extends ConsumerState<_OfflineGradeEntryTab> {
  final Map<int, TextEditingController> _marksCtrls = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _marksCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync =
        ref.watch(studentsInGradeProvider(widget.test.grade));
    final savedGradesAsync =
        ref.watch(testGradesProvider(widget.test.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(studentsInGradeProvider(widget.test.grade));
        ref.invalidate(testGradesProvider(widget.test.id));
      },
      child: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(studentsInGradeProvider(widget.test.grade))),
        data: (students) {
          for (final s in students) {
            _marksCtrls.putIfAbsent(s.id, () => TextEditingController());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: mindForgeCardDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter Marks — ${widget.test.title}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total Marks: ${widget.test.totalMarks.toInt()}  •  Grade ${widget.test.grade}  •  ${widget.test.subject}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              savedGradesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (saved) {
                  if (saved.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Already Graded (${saved.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      ...saved.map((g) => _SavedGradeTile(grade: g)),
                      const Divider(height: 24),
                      const Text('Enter New Grades',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
              if (students.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No students found for this grade.')),
                )
              else ...[
                ...students.map((s) => _MarkEntryRow(
                      student: s,
                      controller: _marksCtrls[s.id]!,
                      maxMarks: widget.test.totalMarks,
                    )),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Grades'),
                  onPressed: _saving ? null : () => _saveGrades(students),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveGrades(List<UserModel> students) async {
    final entries = <Map<String, dynamic>>[];
    for (final s in students) {
      final ctrl = _marksCtrls[s.id];
      if (ctrl == null || ctrl.text.isEmpty) continue;
      final marks = double.tryParse(ctrl.text);
      if (marks == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Invalid marks for ${s.username}'),
            backgroundColor: AppColors.error));
        return;
      }
      if (marks < 0 || marks > widget.test.totalMarks) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Marks for ${s.username} must be 0–${widget.test.totalMarks.toInt()}'),
            backgroundColor: AppColors.error));
        return;
      }
      entries.add({'student_id': s.id, 'marks_obtained': marks});
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter marks for at least one student.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(apiClientProvider)
          .saveOfflineGrades(widget.test.id, entries);
      ref.invalidate(testGradesProvider(widget.test.id));
      for (final c in _marksCtrls.values) {
        c.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved ${result['saved']} grade(s)!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MarkEntryRow extends StatelessWidget {
  final UserModel student;
  final TextEditingController controller;
  final double maxMarks;

  const _MarkEntryRow({
    required this.student,
    required this.controller,
    required this.maxMarks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: mindForgeCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                student.username.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.username,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('ID: ${student.id}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '/ ${maxMarks.toInt()}',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedGradeTile extends StatelessWidget {
  final Map<String, dynamic> grade;
  const _SavedGradeTile({required this.grade});

  @override
  Widget build(BuildContext context) {
    final marks = (grade['marks_obtained'] as num).toDouble();
    final max = (grade['max_marks'] as num).toDouble();
    final pct = (grade['percentage'] as num).toDouble();
    final color = pct >= 75
        ? AppColors.success
        : pct >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration:
          mindForgeCardDecoration(color: color.withValues(alpha: 0.04)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            '${pct.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color),
          ),
        ),
        title: Text(grade['student_name'] as String? ?? 'Unknown',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        trailing: Text(
          '${marks.toStringAsFixed(1)} / ${max.toInt()}',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 13),
        ),
      ),
    );
  }
}
