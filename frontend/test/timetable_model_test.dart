import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/models/timetable.dart';

TimetableSlotModel _slot(String? start, String? end) =>
    TimetableSlotModel.fromJson({
      'id': 1,
      'grade': 8,
      'slot_date': '2026-10-28',
      'period_number': 1,
      'start_time': start,
      'end_time': end,
      'is_holiday': false,
    });

void main() {
  test('slot times drop the seconds the API sends (#6)', () {
    final s = _slot('09:00:00', '09:45:00');
    expect(s.startTime, '09:00');
    expect(s.endTime, '09:45');
  });

  test('already-short and missing times are kept', () {
    final s = _slot('09:00', null);
    expect(s.startTime, '09:00');
    expect(s.endTime, isNull);
  });
}
