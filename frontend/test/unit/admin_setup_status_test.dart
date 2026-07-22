import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/admin/providers/admin_provider.dart';

// The setup workflow gates the admin dashboard: tasks must be completed in
// strict order (academic year -> timetable -> fees -> bank/payment) and the
// "current step" is always the first incomplete task, so a later task can never
// appear reachable while an earlier one is unfinished.
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

void main() {
  group('AdminSetupStatus', () {
    test('fresh school: current step 0, not complete', () {
      final s = _status();
      expect(s.currentStep, 0);
      expect(s.allComplete, isFalse);
    });

    test('advances one step per completed task', () {
      expect(_status(ay: true).currentStep, 1);
      expect(_status(ay: true, tt: true).currentStep, 2);
      expect(_status(ay: true, tt: true, fees: true).currentStep, 3);
    });

    test('all four done: current step 4, complete', () {
      final s = _status(ay: true, tt: true, fees: true, pay: true);
      expect(s.currentStep, 4);
      expect(s.allComplete, isTrue);
    });

    test('out-of-order completion cannot skip: current step is the first gap',
        () {
      // Timetable somehow true but academic year false — the current step must
      // still point at academic year (step 0), never at the later done task.
      expect(_status(tt: true, pay: true).currentStep, 0);
      expect(_status(ay: true, fees: true).currentStep, 1);
    });

    test('steps expose the four flags in workflow order', () {
      expect(_status(ay: true, fees: true).steps, [true, false, true, false]);
    });
  });
}
