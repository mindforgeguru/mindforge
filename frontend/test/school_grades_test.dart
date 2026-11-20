import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/providers/school_grades_provider.dart';

void main() {
  // #5: grade pickers offered 8, 9 and 10 to every school.
  test("a school's grades come from its grades_offered", () {
    expect(gradesOffered({'grades_offered': [9, 8]}), [8, 9]);
  });

  test('every supported grade until the school is known', () {
    expect(gradesOffered(null), [8, 9, 10]);
    expect(gradesOffered({'id': 1}), [8, 9, 10]);
    expect(gradesOffered({'grades_offered': []}), [8, 9, 10]);
  });

  test('a picker keeps an already-selected grade the school dropped', () {
    expect(pickableGrades([8, 9], keep: 10), [8, 9, 10]);
    expect(pickableGrades([8, 9], keep: 9), [8, 9]);
    expect(pickableGrades([8, 9]), [8, 9]);
  });
}
