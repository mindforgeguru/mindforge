import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/admin/providers/admin_provider.dart';
import 'package:mindforge/features/admin/widgets/setup_road_card.dart';

AdminSetupStatus _status({
  bool ay = false,
  bool tt = false,
  bool fees = false,
  bool pay = false,
}) =>
    AdminSetupStatus(
      academicYearDone: ay,
      timetableDone: tt,
      feesDone: fees,
      paymentDone: pay,
    );

Widget _wrap(AdminSetupStatus status) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SetupRoadCard(status: status)),
      ),
    );

void main() {
  group('SetupRoadCard', () {
    testWidgets('always renders the four task labels', (tester) async {
      await tester.pumpWidget(_wrap(_status()));
      await tester.pump();

      expect(find.text('Academic Year'), findsOneWidget);
      expect(find.text('Timetable'), findsOneWidget);
      expect(find.text('Fee Details'), findsOneWidget);
      expect(find.text('Bank / Payment'), findsOneWidget);
    });

    testWidgets('fresh school: car on step 1, steps 2-4 locked, none done',
        (tester) async {
      await tester.pumpWidget(_wrap(_status()));
      await tester.pump();

      // Current step is a car; the three future steps are locked.
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.text('Finish these steps in order to open the dashboard.'),
          findsOneWidget);
    });

    testWidgets('mid-progress: one done, car on current, rest locked',
        (tester) async {
      // Academic year done -> current step is timetable.
      await tester.pumpWidget(_wrap(_status(ay: true)));
      await tester.pump();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget); // academic year
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget); // timetable
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2)); // fees + bank
    });

    testWidgets('all done: four checks, no car, no locks, complete copy',
        (tester) async {
      await tester
          .pumpWidget(_wrap(_status(ay: true, tt: true, fees: true, pay: true)));
      await tester.pump();

      expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.directions_car_rounded), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(find.text('Setup complete — tap any step to edit.'),
          findsOneWidget);
    });
  });
}
