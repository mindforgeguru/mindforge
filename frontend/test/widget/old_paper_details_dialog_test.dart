import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/features/teacher/widgets/old_paper_details_dialog.dart';

/// Setting an old test paper's grade, subject and chapter by hand.
///
/// Test generation only uses a paper whose grade and subject match exactly, so
/// the dialog insists on both and only offers the app's own lists.
void main() {
  late List<(int, String, String?)> saved;
  late Object? failWith;

  setUp(() {
    saved = [];
    failWith = null;
  });

  Future<bool?> open(WidgetTester tester,
      {int? grade, String? subject, String? chapter}) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => OldPaperDetailsDialog(
                paperName: 'paper.pdf',
                grade: grade,
                subject: subject,
                chapter: chapter,
                onSave: (g, s, c) async {
                  if (failWith != null) throw failWith!;
                  saved.add((g, s, c));
                },
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

  Future<void> choose(WidgetTester tester, String field, String option) async {
    await tester.tap(find.byKey(Key('old-paper-$field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('save stays disabled until grade and subject are both chosen',
      (tester) async {
    await open(tester);
    expect(saveButton(tester).onPressed, isNull);

    await choose(tester, 'grade', 'Grade 9');
    expect(saveButton(tester).onPressed, isNull);

    await choose(tester, 'subject', 'Chemistry');
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('saves the chosen values and closes', (tester) async {
    await open(tester);
    await choose(tester, 'grade', 'Grade 9');
    await choose(tester, 'subject', 'Chemistry');
    await tester.enterText(find.byKey(const Key('old-paper-chapter')), '  Acids  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, [(9, 'Chemistry', 'Acids')]);
    expect(find.byType(OldPaperDetailsDialog), findsNothing);
  });

  testWidgets('a blank chapter is sent as none', (tester) async {
    await open(tester, grade: 8, subject: 'Physics', chapter: 'Force');
    await tester.enterText(find.byKey(const Key('old-paper-chapter')), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, [(8, 'Physics', null)]);
  });

  testWidgets('pre-fills what the paper already has', (tester) async {
    await open(tester, grade: 10, subject: 'Biology', chapter: 'Cell Cycle');
    expect(find.text('Grade 10'), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('Cell Cycle'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('an off-list subject from an older AI scan does not crash',
      (tester) async {
    // DropdownButtonFormField asserts when its value isn't among the items.
    await open(tester, grade: 8, subject: 'Math');
    expect(tester.takeException(), isNull);
    expect(saveButton(tester).onPressed, isNull,
        reason: 'the teacher still has to pick a real subject');
  });

  testWidgets('a failed save shows why and keeps the dialog open',
      (tester) async {
    failWith = Exception('network down');
    await open(tester, grade: 8, subject: 'Physics');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(OldPaperDetailsDialog), findsOneWidget);
    expect(find.textContaining("Couldn't save"), findsOneWidget);
  });
}
