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
