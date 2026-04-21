import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/widgets/badge_dot.dart';

// Wrap without Scaffold to keep the widget tree minimal.
Widget _wrap(Widget w) =>
    MaterialApp(home: Center(child: SizedBox(width: 100, height: 100, child: w)));

// A Stack that is a direct descendant of BadgeDot means the badge is showing.
Finder _badgeDotStack() => find.descendant(
      of: find.byType(BadgeDot),
      matching: find.byType(Stack),
    );

void main() {
  group('BadgeDot', () {
    testWidgets('show=false: renders child, no Stack inside BadgeDot',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BadgeDot(show: false, child: Icon(Icons.notifications)),
      ));

      expect(find.byType(Icon), findsOneWidget);
      expect(_badgeDotStack(), findsNothing);
    });

    testWidgets('show=true: renders Stack inside BadgeDot', (tester) async {
      await tester.pumpWidget(_wrap(
        const BadgeDot(show: true, child: Icon(Icons.notifications)),
      ));

      expect(_badgeDotStack(), findsOneWidget);
    });

    testWidgets('show=true: renders a red circular Container (the dot)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BadgeDot(show: true, child: Icon(Icons.notifications)),
      ));

      final redDots = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(BadgeDot),
              matching: find.byType(Container),
            ),
          )
          .where((c) {
            final dec = c.decoration;
            return dec is BoxDecoration &&
                dec.shape == BoxShape.circle &&
                dec.color == Colors.red;
          })
          .toList();

      expect(redDots, isNotEmpty,
          reason: 'Badge dot should be a red circular Container');
    });

    testWidgets('toggling show true→false removes Stack inside BadgeDot',
        (tester) async {
      // Pump with show=true first
      await tester.pumpWidget(_wrap(
        const BadgeDot(show: true, child: Icon(Icons.notifications)),
      ));
      expect(_badgeDotStack(), findsOneWidget);

      // Re-pump with show=false — simulates the parent rebuilding with new state
      await tester.pumpWidget(_wrap(
        const BadgeDot(show: false, child: Icon(Icons.notifications)),
      ));
      expect(_badgeDotStack(), findsNothing);
    });
  });
}
