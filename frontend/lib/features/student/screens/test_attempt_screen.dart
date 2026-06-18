import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_guard.dart' as leave_guard;
import '../../../core/utils/responsive.dart';
import '../providers/student_provider.dart';

class TestAttemptScreen extends ConsumerStatefulWidget {
  final int testId;
  const TestAttemptScreen({super.key, required this.testId});

  @override
  ConsumerState<TestAttemptScreen> createState() => _TestAttemptScreenState();
}

class _TestAttemptScreenState extends ConsumerState<TestAttemptScreen>
    with WidgetsBindingObserver {
  // Attempt data fetched from /start
  String _title = '';
  double _totalMarks = 0;
  List<Map<String, dynamic>> _questions = const [];
  bool _loading = true;
  bool _loadFailed = false;

  int _currentIndex = 0;

  // question id string → selected/typed answer
  final Map<String, String> _answers = {};

  // Cached text controllers keyed by question id string (for text-input questions)
  final Map<String, TextEditingController> _textCtrls = {};

  int _initialSeconds = 0;
  bool _submitted = false;

  // Autosave: every 20s, last sent snapshot to skip no-op saves
  Timer? _autosaveTimer;
  String _lastSavedSnapshot = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAttempt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    leave_guard.disableLeaveConfirmation();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Set when the lifecycle handler forfeits a backgrounded attempt — the
  // result dialog must wait until the app is foregrounded again.
  bool _pendingResultDialog = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Strict single-attempt policy: leaving the app ends the attempt. Rather
    // than zeroing it, we auto-submit whatever has been answered so far, so
    // the student keeps credit. 'inactive' is skipped because it fires on
    // transient overlays (notification panel, control center) — those
    // shouldn't end the test. 'paused' and 'hidden' are real exits.
    //
    // Web is excluded: there, 'hidden'/'paused' also fire on a mere tab-switch
    // or window-minimize, which shouldn't auto-submit. On web, a real exit
    // (closing/refreshing/navigating the tab away) is caught by the
    // beforeunload guard in leave_guard instead; answers are autosaved every
    // 20s and finalized server-side on the next /start.
    if (!kIsWeb &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      if (!_submitted) {
        _submitted = true;
        _pendingResultDialog = true;
        _autosaveTimer?.cancel();
        _flushAnswers();
        // Fire-and-forget — the screen is going into the background, so
        // there's nothing to await against. The server finalizes with these
        // answers; /start also finalizes the row server-side next time the
        // student opens the test, so it ends up submitted even if lost.
        final api = ref.read(apiClientProvider);
        api
            .submitTest(
              widget.testId,
              Map<String, dynamic>.from(_answers),
              true,
            )
            .catchError((_) => <String, dynamic>{});
        ref.invalidate(pendingTestsProvider);
        ref.invalidate(completedTestsProvider);
        ref.invalidate(studentGradesProvider);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pendingResultDialog) {
        _pendingResultDialog = false;
        _surfaceAutoSubmitResult();
      } else if (!_submitted) {
        _refreshAttemptOnResume();
      }
    }
  }

  /// One-time notice shown as soon as the attempt loads, warning the student
  /// that going back or closing the app will end the test and auto-submit.
  Future<void> _showStartWarning() async {
    if (!mounted || _submitted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(child: Text('Before you begin')),
          ],
        ),
        content: const Text(
          'This is a single attempt. If you press back or close the app, '
          'the test will be automatically submitted with your answers so far '
          'and you will not be able to resume.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  /// Confirmation shown when the student tries to leave the test (Android back
  /// button / iOS swipe-back). Returns true if they chose to submit and leave.
  Future<bool> _confirmExitSubmit() async {
    if (_submitted) return true;
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This will submit your test.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// After a background auto-submit, fetch the finalized score and show it.
  Future<void> _surfaceAutoSubmitResult() async {
    if (!mounted) return;
    double score = 0;
    try {
      final data =
          await ref.read(apiClientProvider).startTestAttempt(widget.testId);
      score = (data['score'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      // Network hiccup on resume — fall back to 0 in the dialog; the grade
      // list will still reflect the real server-side score.
    }
    await _showResultDialog(score: score, autoSubmitted: true);
    _leaveTest();
  }

  Future<void> _startAttempt() async {
    final api = ref.read(apiClientProvider);
    try {
      final data = await api.startTestAttempt(widget.testId);
      _applyAttemptResponse(data);
      // If server returned a finalized attempt (i.e. deadline already passed),
      // jump straight to the result dialog.
      if (data['is_finalized'] == true) {
        if (!mounted) return;
        await _showResultDialog(
          score: (data['score'] as num?)?.toDouble() ?? 0,
          autoSubmitted: data['auto_submitted'] == true,
        );
        _leaveTest();
        return;
      }
      _autosaveTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _autosaveNow(silent: true),
      );
      // Web only: warn (native browser prompt) if they try to close the tab,
      // refresh, or navigate the browser away mid-test. The in-app back button
      // is handled separately by the PopScope dialog below.
      leave_guard.enableLeaveConfirmation();
      // One-time heads-up so the student understands the strict single-attempt
      // policy before answering: leaving the screen / closing the app ends the
      // attempt and auto-submits whatever has been answered.
      await _showStartWarning();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not start test: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  void _applyAttemptResponse(Map<String, dynamic> data) {
    final qs = (data['questions'] as List<dynamic>? ?? const [])
        .map((q) => Map<String, dynamic>.from(q as Map))
        .toList();
    final saved = (data['saved_answers'] as Map<String, dynamic>? ?? const {});

    // (Re)build text controllers, prefilled with anything the server has saved.
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    _textCtrls.clear();
    for (final q in qs) {
      final qId = q['id'].toString();
      final qType = (q['type'] as String? ?? '').toLowerCase();
      if (qType != 'mcq' && qType != 'true_false') {
        _textCtrls[qId] = TextEditingController(
          text: saved[qId]?.toString() ?? '',
        );
      }
    }

    _answers
      ..clear()
      ..addEntries(saved.entries.map((e) => MapEntry(e.key, e.value.toString())));
    _lastSavedSnapshot = _answers.toString();

    setState(() {
      _title = data['title'] as String? ?? '';
      _totalMarks = (data['total_marks'] as num?)?.toDouble() ?? 0;
      _questions = qs;
      _loading = false;
      _initialSeconds = (data['remaining_seconds'] as num?)?.toInt() ?? 0;
    });
  }

  void _flushAnswers() {
    for (final entry in _textCtrls.entries) {
      final v = entry.value.text;
      if (v.isNotEmpty) {
        _answers[entry.key] = v;
      } else {
        _answers.remove(entry.key);
      }
    }
  }

  Future<void> _autosaveNow({bool silent = false}) async {
    if (_submitted) return;
    _flushAnswers();
    final snapshot = _answers.toString();
    if (snapshot == _lastSavedSnapshot) return;
    final api = ref.read(apiClientProvider);
    try {
      await api.saveTestAnswers(
        widget.testId,
        Map<String, dynamic>.from(_answers),
      );
      _lastSavedSnapshot = snapshot;
    } on DioException catch (e) {
      // 410 = server finalized the attempt because the deadline passed.
      if (e.response?.statusCode == 410) {
        await _handleServerFinalization();
        return;
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autosave failed — will retry.')),
        );
      }
    } catch (_) {
      // Swallow other errors: autosave is best-effort, the timer will retry.
    }
  }

  Future<void> _refreshAttemptOnResume() async {
    final api = ref.read(apiClientProvider);
    try {
      final data = await api.startTestAttempt(widget.testId);
      if (data['is_finalized'] == true) {
        if (!mounted) return;
        _submitted = true;
        await _showResultDialog(
          score: (data['score'] as num?)?.toDouble() ?? 0,
          autoSubmitted: data['auto_submitted'] == true,
        );
        _leaveTest();
        return;
      }
      // Resync remaining time so the on-screen timer reflects real time spent
      // backgrounded.
      if (!mounted) return;
      setState(() {
        _initialSeconds = (data['remaining_seconds'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // Stale UI is fine; the next autosave will eventually surface a 410.
    }
  }

  Future<void> _handleServerFinalization() async {
    if (_submitted) return;
    _submitted = true;
    _autosaveTimer?.cancel();
    ref.invalidate(pendingTestsProvider);
    ref.invalidate(completedTestsProvider);
    ref.invalidate(studentGradesProvider);
    if (!mounted) return;
    await _showResultDialog(score: 0, autoSubmitted: true, fromTimeout: true);
    _leaveTest();
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

  Future<void> _showResultDialog({
    required double score,
    required bool autoSubmitted,
    bool fromTimeout = false,
  }) async {
    // The attempt is over — stop warning about leaving the page.
    leave_guard.disableLeaveConfirmation();
    if (!mounted) return;
    await showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => _ResultDialog(
        score: score,
        total: _totalMarks,
        autoSubmitted: autoSubmitted,
        fromTimeout: fromTimeout,
        totalQuestions: _questions.length,
        answered: _answeredCount,
      ),
    );
  }

  /// Leave the test screen once the attempt is over. Pops back to the tests
  /// list when there's a route to return to; otherwise navigates there
  /// explicitly so the screen never lingers behind a remaining timer.
  void _leaveTest() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/student/tests');
    }
  }

  Future<void> _submitTest({bool autoSubmitted = false}) async {
    if (_submitted) return;
    _flushAnswers();
    setState(() => _submitted = true);
    _autosaveTimer?.cancel();

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
      final wasAuto = (result['auto_submitted'] as bool?) ?? autoSubmitted;
      await _showResultDialog(score: score, autoSubmitted: wasAuto);
      _leaveTest();
    } on DioException catch (e) {
      // 409 = already submitted (server finalized while we were away).
      // 410 = window expired. Either way, the attempt is done.
      final code = e.response?.statusCode;
      if (code == 409 || code == 410) {
        ref.invalidate(pendingTestsProvider);
        ref.invalidate(completedTestsProvider);
        ref.invalidate(studentGradesProvider);
        await _showResultDialog(
            score: 0, autoSubmitted: true, fromTimeout: code == 410);
        _leaveTest();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Submission failed: $e'),
              backgroundColor: AppColors.error),
        );
        setState(() => _submitted = false);
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
    _flushAnswers();
    final unanswered = _questions.length - _answeredCount;
    await showDialog(
      context: context,
      useRootNavigator: false,
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
    if (_loadFailed || _questions.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('Test not found or has no questions.')));
    }

    final q = _questions[_currentIndex];
    final qId = q['id'].toString();
    final qType = (q['type'] as String? ?? '').toLowerCase();
    final isLast = _currentIndex == _questions.length - 1;

    // Back button: under the strict single-attempt policy, exiting the screen
    // ends the attempt. We warn first ("Are you sure? This will submit your
    // test.") and, if confirmed, submit the current answers. Once submitted
    // canPop=true so the pop goes through normally.
    return PopScope(
      canPop: _submitted,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitted) return;
        final confirmed = await _confirmExitSubmit();
        if (confirmed) {
          await _submitTest(autoSubmitted: true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
              Text(
                '$_answeredCount/${_questions.length} answered',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      body: Column(
        children: [
          // ── Prominent countdown timer ────────────────────────────────────
          // Keyed on _initialSeconds so it resets cleanly when the remaining
          // time is resynced after the app is backgrounded and resumed.
          _CountdownBar(
            key: ValueKey(_initialSeconds),
            initialSeconds: _initialSeconds,
            onExpired: () => _submitTest(autoSubmitted: true),
          ),
          // ── Overall progress bar (questions answered) ────────────────────
          LinearProgressIndicator(
            value: _answeredCount / _questions.length,
            backgroundColor: AppColors.divider,
            valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
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
                        style:       TextStyle(
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
                        color: AppColors.primary.withValues(alpha: 0.05)),
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
                    color: Colors.black.withValues(alpha: 0.06),
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
                ? AppColors.primary.withValues(alpha: 0.10)
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

// ─── Countdown bar ────────────────────────────────────────────────────────────
// Prominent full-width timer shown at the top of the test body: a coloured
// banner with "MM:SS remaining" and a time-left progress bar that drains as
// the clock runs down. Owns the 1-second Timer so its setState only repaints
// the bar, not the whole screen (question dots, content stay untouched).

class _CountdownBar extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback onExpired;
  const _CountdownBar({
    super.key,
    required this.initialSeconds,
    required this.onExpired,
  });

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        setState(() => _secondsLeft = 0);
        widget.onExpired();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _display {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _color {
    if (_secondsLeft > 60) return AppColors.success;
    if (_secondsLeft > 30) return AppColors.warning;
    return AppColors.error;
  }

  // Fraction of the originally-remaining time that is still left, so the bar
  // starts full when the screen opens and drains to empty at expiry.
  double get _fraction => widget.initialSeconds > 0
      ? (_secondsLeft / widget.initialSeconds).clamp(0.0, 1.0)
      : 0.0;

  @override
  Widget build(BuildContext context) {
    // Solid coloured banner with white text/track for maximum contrast — the
    // timer must be obvious at a glance. Colour shifts green → amber → red as
    // the clock runs down.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: _color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                '$_display remaining',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: R.fs(context, 17, min: 15, max: 20),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.30),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
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
                        ? AppColors.success.withValues(alpha: 0.85)
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
        color: _color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
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
                color: isSelected ? color.withValues(alpha: 0.12) : AppColors.background,
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
  // True when finalization happened because the deadline passed while the
  // student was away from the screen (vs. timer running out in-app).
  final bool fromTimeout;
  final int totalQuestions;
  final int answered;

  const _ResultDialog({
    required this.score,
    required this.total,
    required this.autoSubmitted,
    this.fromTimeout = false,
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
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fromTimeout
                    ? 'The test was auto-submitted because the timer expired while the app was closed.'
                    : 'Your test was auto-submitted when the timer ran out.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.warning, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 52,
            backgroundColor: color.withValues(alpha: 0.15),
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
