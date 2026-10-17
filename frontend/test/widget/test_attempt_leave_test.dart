import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/theme/app_theme.dart';
import 'package:mindforge/features/student/screens/test_attempt_screen.dart';

/// Leaving a test in progress submits it with the answers given so far.
///
/// On the web the browser's Back button does not go through PopScope: the
/// router just replaces the page. On 2026-10-16 that closed the test with no
/// warning and threw away everything answered since the last 20-second
/// autosave — the student reopened it to "0 of 3 questions answered".
class _FakeApi extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;

  /// (answers, autoSubmitted) of every submit, in order.
  final submits = <(Map<String, dynamic>, bool)>[];

  @override
  Future<Map<String, dynamic>> startTestAttempt(int testId) async => {
        'title': 'QA test',
        'total_marks': 2,
        'remaining_seconds': 600,
        'is_finalized': false,
        'saved_answers': <String, dynamic>{},
        'questions': [
          for (final i in [1, 2])
            {
              'id': i,
              'type': 'mcq',
              'marks': 1,
              'question': 'Question $i',
              'options': {'A': 'Right $i', 'B': 'Wrong $i'},
            },
        ],
      };

  @override
  Future<Map<String, dynamic>> saveTestAnswers(
          int testId, Map<String, dynamic> answers) async =>
      {'remaining_seconds': 600};

  @override
  Future<Map<String, dynamic>> submitTest(
      int testId, Map<String, dynamic> answers, bool autoSubmitted) async {
    submits.add((answers, autoSubmitted));
    return {'score': 1, 'auto_submitted': autoSubmitted};
  }

  // The tests list behind the attempt.
  @override
  Future<List<dynamic>> getPendingTests() async => const [];
  @override
  Future<List<dynamic>> getStudentCompletedTests() async => const [];
}

void main() {
  late _FakeApi api;
  late GoRouter router;

  Future<void> openAttemptAndAnswer(WidgetTester tester) async {
    api = _FakeApi();
    router = GoRouter(
      initialLocation: '/tests',
      routes: [
        GoRoute(
          path: '/tests',
          builder: (_, __) => const Scaffold(body: Text('Tests list')),
          routes: [
            GoRoute(
              path: 'attempt',
              builder: (_, __) => const TestAttemptScreen(testId: 7),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp.router(
          theme: AppTheme.lightTheme, routerConfig: router),
    ));
    router.push('/tests/attempt');
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right 1'));
    await tester.pump();
  }

  testWidgets('leaving without the dialog submits the answers given so far',
      (tester) async {
    await openAttemptAndAnswer(tester);

    // What the browser's Back does: the page is replaced, PopScope is skipped.
    router.go('/tests');
    await tester.pumpAndSettle();

    expect(find.text('Tests list'), findsOneWidget);
    expect(api.submits, hasLength(1));
    expect(api.submits.single.$1, {'1': 'A'});
    expect(api.submits.single.$2, isTrue, reason: 'it was not the Submit button');
  });

  testWidgets('a system back still asks first, and submits once',
      (tester) async {
    await openAttemptAndAnswer(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Are you sure?'), findsOneWidget);
    expect(api.submits, isEmpty);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Tests list'), findsOneWidget);
    expect(api.submits, hasLength(1), reason: 'leaving must not submit again');
    expect(api.submits.single.$1, {'1': 'A'});
  });
}
