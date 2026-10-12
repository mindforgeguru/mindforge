import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/teacher/screens/dashboard_screen.dart';

// When the teacher dashboard says "Holiday!". It used to say it whenever the
// workflow had no grades to show — which is also what a school with no
// timetable yet looks like, on an ordinary working day.
Map<String, dynamic> _grade(int grade, {bool timetable = true, bool holiday = false}) =>
    {'grade': grade, 'timetable_created': timetable, 'is_holiday': holiday};

void main() {
  test('no grades at all is not a holiday', () {
    expect(workflowShowsHoliday({'grades': <dynamic>[]}), isFalse);
  });

  test('no grades is not a holiday even when an older server says so', () {
    expect(
      workflowShowsHoliday(
          {'is_holiday_for_teacher': true, 'grades': <dynamic>[]}),
      isFalse,
    );
  });

  test('grades still waiting for a timetable are not a holiday', () {
    expect(
      workflowShowsHoliday({
        'grades': [_grade(8, timetable: false), _grade(9, timetable: false)],
      }),
      isFalse,
    );
  });

  test('every timetabled grade on holiday is a holiday', () {
    expect(
      workflowShowsHoliday({
        'grades': [
          _grade(8, holiday: true),
          _grade(9, holiday: true),
          _grade(10, timetable: false),
        ],
      }),
      isTrue,
    );
  });

  test('one grade working means no school holiday', () {
    expect(
      workflowShowsHoliday({
        'grades': [_grade(8, holiday: true), _grade(9)],
      }),
      isFalse,
    );
  });
}
