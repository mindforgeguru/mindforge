import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/student/screens/test_attempt_screen.dart';

// Seen on the simulator, 2026-10-10: a student who closed the app mid-test and
// came back was told "Time Up! Your test was auto-submitted when the timer ran
// out." with 06:05 still on the clock. Every automatic submission used the
// timer's wording, including the ones caused by leaving the test — which is
// the rule the student most needs explained.

Future<void> _show(WidgetTester tester, TestResultDialog dialog) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));

void main() {
  group('why an attempt ended', () {
    test('auto-submitted with time left means the student left', () {
      expect(
          attemptEndedByLeaving(
              {'auto_submitted': true, 'remaining_seconds': 365}),
          isTrue);
    });

    test('auto-submitted with no time left is the timer', () {
      expect(
          attemptEndedByLeaving(
              {'auto_submitted': true, 'remaining_seconds': 0}),
          isFalse);
      expect(attemptEndedByLeaving({'auto_submitted': true}), isFalse);
    });

    test('a normal submission is neither', () {
      expect(
          attemptEndedByLeaving(
              {'auto_submitted': false, 'remaining_seconds': 365}),
          isFalse);
    });
  });

  group('TestResultDialog wording', () {
    testWidgets('leaving the test does not blame the timer', (tester) async {
      await _show(
          tester,
          const TestResultDialog(
            score: 0,
            total: 5,
            autoSubmitted: true,
            leftTest: true,
            totalQuestions: 5,
            answered: 1,
          ));

      expect(find.text('Test Ended'), findsOneWidget);
      expect(find.textContaining('left the test'), findsOneWidget);
      expect(find.text('Time Up!'), findsNothing);
      expect(find.textContaining('timer'), findsNothing);
    });

    testWidgets('the timer running out says so', (tester) async {
      await _show(
          tester,
          const TestResultDialog(
            score: 3,
            total: 5,
            autoSubmitted: true,
            totalQuestions: 5,
            answered: 4,
          ));

      expect(find.text('Time Up!'), findsOneWidget);
      expect(find.textContaining('timer ran out'), findsOneWidget);
    });

    testWidgets('a deadline that passed while away says so', (tester) async {
      await _show(
          tester,
          const TestResultDialog(
            score: 0,
            total: 5,
            autoSubmitted: true,
            fromTimeout: true,
            totalQuestions: 5,
            answered: 0,
          ));

      expect(find.text('Time Up!'), findsOneWidget);
      expect(find.textContaining('while the app was closed'), findsOneWidget);
    });

    testWidgets('a normal submission shows no warning', (tester) async {
      await _show(
          tester,
          const TestResultDialog(
            score: 5,
            total: 5,
            autoSubmitted: false,
            totalQuestions: 5,
            answered: 5,
          ));

      expect(find.text('Test Submitted!'), findsOneWidget);
      expect(find.textContaining('auto-submitted'), findsNothing);
      expect(find.textContaining('left the test'), findsNothing);
    });
  });
}
