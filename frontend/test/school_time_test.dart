import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/utils/school_time.dart';

// The dashboards ask the server for "today" in school time (IST). A phone set
// to another timezone (a parent abroad) must still get the school's date.
//
// Falsified: make schoolNow() return DateTime.now() and the field check fails
// whenever the test machine isn't on IST (CI runs in UTC).
void main() {
  test('schoolNow carries IST wall-clock fields', () {
    final before = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final s = schoolNow();
    final after = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final asUtcFields = DateTime.utc(s.year, s.month, s.day, s.hour, s.minute, s.second, s.millisecond);
    expect(!asUtcFields.isBefore(before.subtract(const Duration(milliseconds: 1))), isTrue);
    expect(!asUtcFields.isAfter(after.add(const Duration(milliseconds: 1))), isTrue);
  });

  test('untilNextSchoolDay lands one minute past IST midnight', () {
    final d = untilNextSchoolDay();
    expect(d.inSeconds, greaterThan(0));
    expect(d, lessThanOrEqualTo(const Duration(hours: 24, minutes: 1)));
    final fire = DateTime.now().toUtc().add(d).add(const Duration(hours: 5, minutes: 30));
    expect(fire.hour, 0);
    expect(fire.minute, anyOf(0, 1));
  });
}
