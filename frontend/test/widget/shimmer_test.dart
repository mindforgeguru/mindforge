import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/widgets/shimmer_list.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  group('ShimmerCards', () {
    testWidgets('renders the correct number of ShimmerCard children', (tester) async {
      await tester.pumpWidget(_wrap(
        const SingleChildScrollView(child: ShimmerCards(count: 3)),
      ));

      expect(find.byType(ShimmerCard), findsNWidgets(3));
    });

    testWidgets('count=0 renders no cards', (tester) async {
      await tester.pumpWidget(_wrap(
        const SingleChildScrollView(child: ShimmerCards(count: 0)),
      ));

      expect(find.byType(ShimmerCard), findsNothing);
    });

    testWidgets('scrollable: does not overflow a bounded box shorter than '
        'its natural height', (tester) async {
      // The fees loading placeholder — 3 cards of 140 px plus 16 px margin
      // each = 468 px natural — sits under a TabBar in a ~455 px pane. As a
      // plain Column (mainAxisSize.max) that overflows by 13 px and Flutter
      // asserts. `scrollable: true` clips instead. Reproduce the exact bound.
      await tester.pumpWidget(_wrap(
        const SizedBox(
          height: 455,
          child: ShimmerCards(count: 3, cardHeight: 140, scrollable: true),
        ),
      ));

      // A RenderFlex overflow surfaces as a thrown FlutterError captured by the
      // test binding; takeException() returns null when none was thrown.
      expect(tester.takeException(), isNull);
      expect(find.byType(ShimmerCard), findsNWidgets(3));
    });
  });

  group('ShimmerList', () {
    testWidgets('renders itemCount rows by default', (tester) async {
      await tester.pumpWidget(_wrap(
        const ShimmerList(itemCount: 4),
      ));

      // Each row is a Container inside a ListView
      expect(find.byType(ShimmerList), findsOneWidget);
    });
  });
}
