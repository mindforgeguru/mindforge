import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../providers/student_provider.dart';

class TestReviewScreen extends ConsumerWidget {
  final int testId;
  const TestReviewScreen({super.key, required this.testId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(testReviewProvider(testId));

    return Scaffold(
      appBar: AppBar(
        title: reviewAsync.maybeWhen(
          data: (d) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d['title'] as String, style: const TextStyle(fontSize: 15)),
              Text(
                '${d['subject']}  ·  Score: ${(d['score'] as num).toStringAsFixed(1)} / ${(d['total_marks'] as num).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          orElse: () => const Text('Test Review'),
        ),
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final questions =
              (data['questions'] as List<dynamic>).cast<Map<String, dynamic>>();
          final studentAnswers =
              (data['student_answers'] as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, v?.toString() ?? ''));
          final score = (data['score'] as num).toDouble();
          final total = (data['total_marks'] as num).toDouble();
          final pct = total > 0 ? score / total * 100 : 0.0;
          final pctColor = pct >= 75
              ? AppColors.success
              : pct >= 50
                  ? AppColors.warning
                  : AppColors.error;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: questions.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              // Header score card
              if (i == 0) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: mindForgeCardDecoration(
                      color: pctColor.withValues(alpha: 0.07)),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: pctColor.withValues(alpha: 0.15),
                        child: Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: pctColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${score.toStringAsFixed(1)} / ${total.toStringAsFixed(0)} marks',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pct >= 75
                                ? 'Excellent!'
                                : pct >= 50
                                    ? 'Good effort!'
                                    : 'Keep practising!',
                            style: TextStyle(color: pctColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              final q = questions[i - 1];
              final qId = q['id'].toString();
              final qType = (q['type'] as String? ?? '').toLowerCase();
              final correctAnswer =
                  (q['answer'] as String? ?? '').trim();
              final studentAnswer =
                  (studentAnswers[qId] ?? '').trim();
              final isCorrect = _isCorrect(
                  qType, studentAnswer.toLowerCase(), correctAnswer.toLowerCase());

              return _QuestionReviewCard(
                index: i,
                question: q,
                qType: qType,
                correctAnswer: correctAnswer,
                studentAnswer: studentAnswer,
                isCorrect: isCorrect,
              );
            },
          );
        },
      ),
    );
  }

  bool _isCorrect(String qType, String student, String correct) {
    if (student.isEmpty) return false;
    if (qType == 'mcq' || qType == 'true_false' || qType == 'fill_blank') {
      return student == correct;
    }
    // VSA / numerical: keyword overlap ≥ 50 %
    const stopWords = {
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'of', 'in', 'on',
      'at', 'to', 'for', 'it', 'its'
    };
    final cWords = correct.split(' ').toSet().difference(stopWords);
    final sWords = student.split(' ').toSet().difference(stopWords);
    if (cWords.isEmpty) return false;
    return sWords.intersection(cWords).length / cWords.length >= 0.5;
  }
}

// ─── Single question review card ──────────────────────────────────────────────

class _QuestionReviewCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> question;
  final String qType;
  final String correctAnswer;
  final String studentAnswer;
  final bool isCorrect;

  const _QuestionReviewCard({
    required this.index,
    required this.question,
    required this.qType,
    required this.correctAnswer,
    required this.studentAnswer,
    required this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = studentAnswer.isEmpty
        ? AppColors.textMuted
        : isCorrect
            ? AppColors.success
            : AppColors.error;
    final statusIcon = studentAnswer.isEmpty
        ? Icons.remove_circle_outline
        : isCorrect
            ? Icons.check_circle
            : Icons.cancel;
    final statusLabel = studentAnswer.isEmpty
        ? 'Not Answered'
        : isCorrect
            ? 'Correct'
            : 'Incorrect';

    return Container(
      decoration: mindForgeCardDecoration(
          color: statusColor.withValues(alpha: 0.04)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: R.fluid(context, 28, min: 24, max: 34),
                  height: R.fluid(context, 28, min: 24, max: 34),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Center(
                    child: Text('$index',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                _TypeChip(qType: qType),
                const Spacer(),
                Icon(statusIcon, color: statusColor, size: 16),
                const SizedBox(width: 4),
                Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(width: 8),
                Text(
                  '${question['marks']} mark${question['marks'] == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question text
                Text(
                  question['question'] as String? ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 12),

                // MCQ options with highlights
                if (qType == 'mcq' &&
                    question['options'] is Map<String, dynamic>)
                  ..._buildMcqOptions(
                      question['options'] as Map<String, dynamic>)
                else if (qType == 'true_false')
                  _buildTrueFalse()
                else ...[
                  // Text-based questions
                  _AnswerRow(
                    label: 'Your answer',
                    text: studentAnswer.isEmpty ? '(not answered)' : studentAnswer,
                    color: studentAnswer.isEmpty
                        ? AppColors.textMuted
                        : isCorrect
                            ? AppColors.success
                            : AppColors.error,
                    icon: studentAnswer.isEmpty
                        ? Icons.remove
                        : isCorrect
                            ? Icons.check
                            : Icons.close,
                  ),
                  const SizedBox(height: 6),
                  _AnswerRow(
                    label: 'Correct answer',
                    text: correctAnswer,
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMcqOptions(Map<String, dynamic> opts) {
    return opts.entries.map((entry) {
      final key = entry.key;
      final isCorrectOpt = key.toLowerCase() == correctAnswer.toLowerCase();
      final isStudentOpt =
          key.toLowerCase() == studentAnswer.toLowerCase();

      Color bg;
      Color border;
      Color textColor;
      Widget? trailing;

      if (isCorrectOpt && isStudentOpt) {
        bg = AppColors.success.withValues(alpha: 0.12);
        border = AppColors.success;
        textColor = AppColors.success;
        trailing = const Icon(Icons.check_circle, color: AppColors.success, size: 18);
      } else if (isCorrectOpt) {
        bg = AppColors.success.withValues(alpha: 0.08);
        border = AppColors.success;
        textColor = AppColors.success;
        trailing =
            const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18);
      } else if (isStudentOpt) {
        bg = AppColors.error.withValues(alpha: 0.08);
        border = AppColors.error;
        textColor = AppColors.error;
        trailing = const Icon(Icons.cancel, color: AppColors.error, size: 18);
      } else {
        bg = Colors.transparent;
        border = AppColors.divider;
        textColor = AppColors.textSecondary;
        trailing = null;
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: border.withValues(alpha: 0.15),
              child: Text(key,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(entry.value as String,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: (isCorrectOpt || isStudentOpt)
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
    }).toList();
  }

  Widget _buildTrueFalse() {
    return Row(
      children: ['True', 'False'].map((v) {
        final isCorrectOpt = v.toLowerCase() == correctAnswer.toLowerCase();
        final isStudentOpt = v.toLowerCase() == studentAnswer.toLowerCase();

        Color color;
        if (isCorrectOpt && isStudentOpt) {
          color = AppColors.success;
        } else if (isCorrectOpt) {
          color = AppColors.success;
        } else if (isStudentOpt) {
          color = AppColors.error;
        } else {
          color = AppColors.divider;
        }

        Widget? badge;
        if (isCorrectOpt && isStudentOpt) {
          badge = const Icon(Icons.check_circle, color: AppColors.success, size: 16);
        } else if (isCorrectOpt) {
          badge = const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16);
        } else if (isStudentOpt) {
          badge = const Icon(Icons.cancel, color: AppColors.error, size: 16);
        }

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(v == 'True' ? Icons.check_circle : Icons.cancel,
                    color: color, size: 24),
                const SizedBox(height: 4),
                Text(v,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  badge,
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Answer row (for text questions) ─────────────────────────────────────────

class _AnswerRow extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final IconData icon;

  const _AnswerRow({
    required this.label,
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(text,
                    style: TextStyle(color: color, fontSize: 13)),
              ],
            ),
          ),
        ],
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
      case 'vsa': return 'VSA';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(_label,
          style: TextStyle(
              fontSize: 10, color: _color, fontWeight: FontWeight.bold)),
    );
  }
}
