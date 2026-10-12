import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/admin/screens/timetable_screen.dart';

// The timetable setup screen pre-fills period timings for a new school and
// for each period added with the slider. The pre-filled day used to have two
// one-hour holes in it — 09:00–09:45, then 10:45 — because a period that
// ended at :45 pushed the next one a whole hour on.
String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

List<String> _day(int periods) {
  final out = <String>[];
  TimeOfDay? previousEnd;
  for (var i = 0; i < periods; i++) {
    final p = defaultPeriodAfter(previousEnd);
    out.add('${_fmt(p.start)}-${_fmt(p.end)}');
    previousEnd = p.end;
  }
  return out;
}

void main() {
  test('the first period is 09:00 to 09:45', () {
    final p = defaultPeriodAfter(null);
    expect(_fmt(p.start), '09:00');
    expect(_fmt(p.end), '09:45');
  });

  test('a default day runs back to back with no holes', () {
    expect(_day(6), [
      '09:00-09:45',
      '09:45-10:30',
      '10:30-11:15',
      '11:15-12:00',
      '12:00-12:45',
      '12:45-13:30',
    ]);
  });

  test('a new period starts when the one before it ends, whatever that is', () {
    for (final end in const [
      TimeOfDay(hour: 9, minute: 45),
      TimeOfDay(hour: 10, minute: 20),
      TimeOfDay(hour: 11, minute: 0),
      TimeOfDay(hour: 13, minute: 59),
    ]) {
      final next = defaultPeriodAfter(end);
      expect(_fmt(next.start), _fmt(end));
      final minutes = (next.end.hour * 60 + next.end.minute) -
          (next.start.hour * 60 + next.start.minute);
      expect(minutes, 45, reason: 'after ${_fmt(end)}');
    }
  });

  test('a period that would cross midnight wraps instead of overflowing', () {
    final p = defaultPeriodAfter(const TimeOfDay(hour: 23, minute: 30));
    expect(_fmt(p.start), '23:30');
    expect(_fmt(p.end), '00:15');
  });
}
