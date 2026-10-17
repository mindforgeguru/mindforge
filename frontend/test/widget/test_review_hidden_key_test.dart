import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';
import 'package:mindforge/features/student/screens/test_review_screen.dart';

// While a test is still open for the class the review carries no answer key
// (found 2026-10-17: a student who finished early could read every answer and
// pass them on). Without this, the screen compared each answer with an empty
// key and marked everything "Incorrect".
Map<String, dynamic> _review({required bool open}) => {
      'test_id': 1, 'title': 'Cells', 'subject': 'science', 'total_marks': 2.0,
      'score': 1.0,
      'answers_available_at': open ? '2026-10-18T10:00:00Z' : null,
      'student_answers': {'1': 'A', '2': 'photosynthesis'},
      'questions': [
        {'id': 1, 'type': 'mcq', 'marks': 1, 'question': 'Powerhouse of the cell?',
         'options': {'A': 'Mitochondria', 'B': 'Nucleus'}, if (!open) 'answer': 'A'},
        {'id': 2, 'type': 'fill_blank', 'marks': 1, 'question': 'Plants make food by ____.',
         if (!open) 'answer': 'photosynthesis'},
      ],
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> review) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [testReviewProvider.overrideWith((ref, id) async => review)],
    child: const MaterialApp(home: TestReviewScreen(testId: 1)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('while the test is open: no right or wrong, and a note saying when',
      (tester) async {
    await _pump(tester, _review(open: true));
    expect(find.text('Incorrect'), findsNothing);
    expect(find.text('Correct'), findsNothing);
    expect(find.text('Correct answer'), findsNothing);
    expect(find.text('Answered'), findsNWidgets(2));
    expect(find.textContaining('Correct answers appear when the test closes'), findsOneWidget);
    expect(find.text('photosynthesis'), findsOneWidget);
  });

  testWidgets('once closed: marked as before', (tester) async {
    await _pump(tester, _review(open: false));
    expect(find.text('Correct'), findsNWidgets(2));
    expect(find.textContaining('Correct answers appear'), findsNothing);
  });
}
