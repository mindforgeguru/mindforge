import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/admin/providers/admin_provider.dart';
import 'package:mindforge/features/admin/widgets/setup_road_card.dart';

AdminSetupStatus _status({
  bool ay = false,
  bool tt = false,
  bool fees = false,
  bool pay = false,
  bool logo = false,
}) =>
    AdminSetupStatus(
      academicYearDone: ay,
      timetableDone: tt,
      feesDone: fees,
      paymentDone: pay,
      logoDone: logo,
    );

Widget _wrap(AdminSetupStatus status) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SetupRoadCard(status: status)),
        ),
      ),
    );

void main() {
  group('SetupRoadCard', () {
    testWidgets('renders the five task labels + Close Year cap', (tester) async {
      await tester.pumpWidget(_wrap(_status()));
      await tester.pump();

      expect(find.text('Academic Year'), findsOneWidget);
      expect(find.text('Timetable'), findsOneWidget);
      expect(find.text('Fee Details'), findsOneWidget);
      expect(find.text('Bank / Payment'), findsOneWidget);
      expect(find.text('School Logo'), findsOneWidget);
      // 'Close Year' appears twice: the road cap label + the legend entry.
      expect(find.text('Close Year'), findsNWidgets(2));
    });

    testWidgets('fresh school: car on step 1, four locks incl. Close Year cap',
        (tester) async {
      await tester.pumpWidget(_wrap(_status()));
      await tester.pump();

      // Car on academic year; steps 2-5 locked + the Close-Year cap locked = 5.
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      // Close Year is locked (no event_busy icon shown yet).
      expect(find.byIcon(Icons.event_busy_rounded), findsNothing);
    });

    testWidgets('all five done: Close Year unlocks, dashboard-complete copy',
        (tester) async {
      await tester.pumpWidget(_wrap(
          _status(ay: true, tt: true, fees: true, pay: true, logo: true)));
      await tester.pump();

      expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.directions_car_rounded), findsNothing);
      // Close Year is now actionable (event_busy), nothing locked.
      expect(find.byIcon(Icons.event_busy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(find.text('Setup complete — tap any step to edit.'),
          findsOneWidget);
    });

    testWidgets('four of five done: logo is the car, Close Year still locked',
        (tester) async {
      await tester
          .pumpWidget(_wrap(_status(ay: true, tt: true, fees: true, pay: true)));
      await tester.pump();

      expect(find.byIcon(Icons.check_rounded), findsNWidgets(4)); // first four
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget); // logo
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget); // Close Year cap
      expect(find.byIcon(Icons.event_busy_rounded), findsNothing);
    });
  });
}
