import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/teacher/screens/auto_presentation_list_screen.dart';

// The Auto Presentations screen lists only the decks a teacher has adopted.
// A deck that has just been generated sits in the school library until
// someone adopts it — so the teacher who uploaded it came back to "No
// presentations yet. Upload a chapter PDF…", as if the upload had been lost.
Future<void> _pump(WidgetTester tester,
    {required int libraryCount, VoidCallback? onBrowse}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PresentationsEmptyState(
        libraryCount: libraryCount,
        onBrowseLibrary: onBrowse ?? () {},
      ),
    ),
  ));
}

void main() {
  testWidgets('an empty library invites an upload and offers no library link',
      (tester) async {
    await _pump(tester, libraryCount: 0);

    expect(find.text('No presentations yet.'), findsOneWidget);
    expect(find.textContaining('Upload a chapter PDF'), findsOneWidget);
    expect(find.text('Browse library'), findsNothing);
  });

  testWidgets('decks waiting in the library are pointed out, not denied',
      (tester) async {
    var browsed = 0;
    await _pump(tester, libraryCount: 3, onBrowse: () => browsed++);

    expect(find.text('No presentations yet.'), findsNothing);
    expect(find.text('Nothing in progress.'), findsOneWidget);
    expect(find.textContaining('3 presentations in the school library'),
        findsOneWidget);

    await tester.tap(find.text('Browse library'));
    expect(browsed, 1);
  });

  testWidgets('one deck is not "1 presentations"', (tester) async {
    await _pump(tester, libraryCount: 1);
    expect(find.textContaining('1 presentation in the school library'),
        findsOneWidget);
  });
}
