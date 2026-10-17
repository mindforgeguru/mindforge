import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/parent/providers/parent_provider.dart';
import 'package:mindforge/features/parent/widgets/child_switcher.dart';

// A parent with two children in the school had every screen fail. The API now
// takes a child; this is how the parent chooses one. One child: nothing shown,
// so most families see no change.
Future<ProviderContainer> _pump(
    WidgetTester tester, List<Map<String, dynamic>> children) async {
  final container = ProviderContainer(overrides: [
    parentChildrenProvider.overrideWith((ref) async => children),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: ChildSwitcher())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('one child: no switcher', (tester) async {
    await _pump(tester, [
      {'student_id': 7, 'username': 'asha', 'grade': 8},
    ]);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('two children: one chip each, the first selected', (tester) async {
    await _pump(tester, [
      {'student_id': 7, 'username': 'asha', 'grade': 8},
      {'student_id': 9, 'username': 'ravi', 'grade': 10},
    ]);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('asha · Grade 8'), findsOneWidget);
    expect(find.text('ravi · Grade 10'), findsOneWidget);
    final first = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    expect(first.selected, isTrue);
  });

  testWidgets('tapping a child selects them for every parent screen',
      (tester) async {
    final container = await _pump(tester, [
      {'student_id': 7, 'username': 'asha', 'grade': 8},
      {'student_id': 9, 'username': 'ravi', 'grade': 10},
    ]);
    await tester.tap(find.text('ravi · Grade 10'));
    await tester.pumpAndSettle();
    expect(container.read(selectedChildIdProvider), 9);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(chips[0].selected, isFalse);
    expect(chips[1].selected, isTrue);
  });
}
