import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/test.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../providers/student_provider.dart';

class TestAttemptScreen extends ConsumerStatefulWidget {
  final int testId;
  const TestAttemptScreen({super.key, required this.testId});

  @override
  ConsumerState<TestAttemptScreen> createState() => _TestAttemptScreenState();
}

class _TestAttemptScreenState extends ConsumerState<TestAttemptScreen> {
  TestModel? _test;
  bool _loading = true;
  int _currentIndex = 0;

  // question id string → selected/typed answer
  final Map<String, String> _answers = {};

  // Cached text controllers keyed by question id string (for text-input questions)
  final Map<String, TextEditingController> _textCtrls = {};

  Timer? _timer;
  int _secondsLeft = 0;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadTest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTest() async {
    final api = ref.read(apiClientProvider);
    final pending = await api.getPendingTests();
    final testData = pending.firstWhere(
      (t) => t['id'] == widget.testId,
      orElse: () => <String, dynamic>{},
    );
    if ((testData as Map).isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final test = TestModel.fromJson(testData as Map<String, dynamic>);

    // Build text controllers for non-selection questions
    for (final q in test.questions ?? []) {
      final qId = q['id'].toString();
      final qType = (q['type'] as String? ?? '').toLowerCase();
      if (qType != 'mcq' && qType != 'true_false') {
        _textCtrls[qId] = TextEditingController();
      }
    }

    setState(() {
      _test = test;
      _loading = false;
      // 1 minute per question (timeLimitMinutes already set server-side)
      _secondsLeft = (test.timeLimitMinutes ?? test.questionCount) * 60;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 0) {
        t.cancel();
        _submitTest(autoSubmitted: true);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  List<Map<String, dynamic>> get _questions =>
      _test?.questions?.cast<Map<String, dynamic>>() ?? [];

  String get _timeDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (_secondsLeft > 60) return AppColors.success;
    if (_secondsLeft > 30) return AppColors.warning;
    return AppColors.error;
  }

  void _goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() => _currentIndex = index);
  }

  void _onAnswer(String qId, String answer) {
    setState(() => _answers[qId] = answer);
  }

  int get _answeredCount =>
      _questions.where((q) => _answers.containsKey(q['id'].toString())).length;

  Future<void> _submitTest({bool autoSubmitted = false}) async {
    if (_submitted) return;

    // Flush text controller values into _answers before submitting
    for (final entry in _textCtrls.entries) {
      if (entry.value.text.isNotEmpty) {
        _answers[entry.key] = entry.value.text;
      }
    }

    setState(() => _submitted = true);
    _timer?.cancel();

    final api = ref.read(apiClientProvider);
    try {
      final result = await api.submitTest(
        widget.testId,
        Map<String, dynamic>.from(_answers),
        autoSubmitted,
      );
      ref.invalidate(pendingTestsProvider);
      ref.invalidate(completedTestsProvider);
      ref.invalidate(studentGradesProvider);

      final score = (result['score'] as num?)?.toDouble() ?? 0;
      final total = _test?.totalMarks ?? 0;

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ResultDialog(
            score: score,
            total: total,
            autoSubmitted: autoSubmitted,
            totalQuestions: _questions.length,
            answered: _answeredCount,
          ),
        );
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Submission failed: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _submitted = false);
      }
    }
  }

  Future<void> _showSubmitConfirmation() async {
    // Flush current text answers
    for (final entry in _textCtrls.entries) {
      if (entry.value.text.isNotEmpty) {
        _answers[entry.key] = entry.value.text;
      }
    }
    final unanswered = _questions.length - _answeredCount;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submit Test?'),
        content: Text(unanswered > 0
            ? '$unanswered question(s) unanswered. Submit anyway?'
            : 'All questions answered. Submit now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Review')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () {
              Navigator.pop(context);
              _submitTest();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_test == null || _questions.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('Test not found or has no questions.')));
    }

    final q = _questions[_currentIndex];
    final qId = q['id'].toString();
    final qType = (q['type'] as String? ?? '').toLowerCase();
    final isLast = _currentIndex == _questions.length - 1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_test!.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
            Text(
              '$_answeredCount/${_questions.length} answered',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          // Countdown timer badge
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _timerColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _timerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, size: 14, color: _timerColor),
                const SizedBox(width: 4),
                Text(
                  _timeDisplay,
                  style: TextStyle(
                      color: _timerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: R.fs(context, 15, min: 13, max: 17)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Overall progress bar ─────────────────────────────────────────
          LinearProgressIndicator(
            value: _answeredCount / _questions.length,
            backgroundColor: AppColors.divider,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 3,
          ),

          // ── Question dots overview ────────────────────────────────────────
          _QuestionDotsRow(
            questions: _questions,
            answers: _answers,
            currentIndex: _currentIndex,
            onTap: _goTo,
          ),

          // ── Question content ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Question number + type header
                  Row(
                    children: [
                      Container(
                        width: R.fluid(context, 36, min: 32, max: 44),
                        height: R.fluid(context, 36, min: 32, max: 44),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Center(
                          child: Text(
                            '${_currentIndex + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TypeChip(qType: qType),
                      const Spacer(),
                      Text(
                        '${q['marks']} mark${q['marks'] == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Question text card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: mindForgeCardDecoration(
                        color: AppColors.primary.withOpacity(0.05)),
                    child: Text(
                      q['question'] as String? ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(height: 1.5),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Answer input
                  if (qType == 'mcq') ...[
                    ..._buildMcqOptions(q, qId),
                  ] else if (qType == 'true_false') ...[
                    _TrueFalseSelector(
                      selected: _answers[qId],
                      onSelected: (v) => _onAnswer(qId, v),
                    ),
                  ] else ...[
                    _TextAnswerField(
                      controller: _textCtrls[qId]!,
                      qType: qType,
                      onChanged: (v) => _onAnswer(qId, v),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Navigation bar ────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Previous'),
                  onPressed: _currentIndex > 0
                      ? () => _goTo(_currentIndex - 1)
                      : null,
                ),
                const Spacer(),
                if (!isLast)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Next'),
                    onPressed: () => _goTo(_currentIndex + 1),
                  )
                else
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Submit Test'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success),
                    onPressed: _submitted ? null : _showSubmitConfirmation,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMcqOptions(Map<String, dynamic> q, String qId) {
    final opts = q['options'] as Map<String, dynamic>? ?? {};
    return opts.entries.map((entry) {
      final isSelected = _answers[qId] == entry.key;
      return GestureDetector(
        onTap: () => _onAnswer(qId, entry.key),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.10)
                : AppColors.cardBackground,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.divider,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor:
                    isSelected ? AppColors.primary : AppColors.background,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(entry.value as String,
                      style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal))),
            ],
          ),
        ),
      );
    }).toList();
  }
}

// ─── Question dots overview ────────────────────────────────────────────────────

class _QuestionDotsRow extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final Map<String, String> answers;
  final int currentIndex;
  final void Function(int) onTap;

  const _QuestionDotsRow({
    required this.questions,
    required this.answers,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.background,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: questions.length,
        itemBuilder: (_, i) {
          final qId = questions[i]['id'].toString();
          final isAnswered = answers.containsKey(qId);
          final isCurrent = i == currentIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.primary
                    : isAnswered
                        ? AppColors.success.withOpacity(0.85)
                        : AppColors.divider,
                borderRadius: BorderRadius.circular(8),
                border: isCurrent
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (isCurrent || isAnswered)
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Type chip ────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String qType;
  const _TypeChip({required this.qType});

  String get _label {
    switch (qType) {
      case 'mcq': return 'MCQ';
      case 'true_false': return 'True / False';
      case 'fill_blank': return 'Fill Blank';
      case 'vsa': return 'Very Short Answer';
      case 'numerical': return 'Numerical';
      default: return qType.toUpperCase();
    }
  }

  Color get _color {
    switch (qType) {
      case 'mcq': return AppColors.secondary;
      case 'true_false': return AppColors.warning;
      case 'fill_blank': return AppColors.accent;
      case 'numerical': return AppColors.error;
      default: return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(_label,
          style: TextStyle(
              fontSize: 11,
              color: _color,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Text answer field ────────────────────────────────────────────────────────

class _TextAnswerField extends StatelessWidget {
  final TextEditingController controller;
  final String qType;
  final void Function(String) onChanged;

  const _TextAnswerField({
    required this.controller,
    required this.qType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: qType == 'vsa' ? 3 : 2,
      decoration: InputDecoration(
        labelText: 'Your Answer',
        hintText: qType == 'fill_blank'
            ? 'Enter the missing word(s)...'
            : qType == 'numerical'
                ? 'Enter numerical answer with units...'
                : 'Write your answer here...',
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

// ─── True/False selector ──────────────────────────────────────────────────────

class _TrueFalseSelector extends StatelessWidget {
  final String? selected;
  final void Function(String) onSelected;

  const _TrueFalseSelector({this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['True', 'False'].map((v) {
        final isSelected = selected == v;
        final color = v == 'True' ? AppColors.success : AppColors.error;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelected(v),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.12) : AppColors.background,
                border: Border.all(
                  color: isSelected ? color : AppColors.divider,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Icon(
                    v == 'True' ? Icons.check_circle : Icons.cancel,
                    color: isSelected ? color : AppColors.textMuted,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    v,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected ? color : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Result dialog ────────────────────────────────────────────────────────────

class _ResultDialog extends StatelessWidget {
  final double score;
  final double total;
  final bool autoSubmitted;
  final int totalQuestions;
  final int answered;

  const _ResultDialog({
    required this.score,
    required this.total,
    required this.autoSubmitted,
    required this.totalQuestions,
    required this.answered,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (score / total * 100) : 0.0;
    final color = pct >= 75
        ? AppColors.success
        : pct >= 50
            ? AppColors.warning
            : AppColors.error;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            autoSubmitted ? Icons.timer_off : Icons.check_circle,
            color: autoSubmitted ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 8),
          Text(autoSubmitted ? 'Time Up!' : 'Test Submitted!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (autoSubmitted)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Your test was auto-submitted when the timer ran out.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.warning, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 52,
            backgroundColor: color.withOpacity(0.15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
                Text(
                  '${score.toStringAsFixed(1)} / ${total.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$answered of $totalQuestions questions answered',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            pct >= 75
                ? 'Excellent work!'
                : pct >= 50
                    ? 'Good effort!'
                    : 'Keep practising!',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 15),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
