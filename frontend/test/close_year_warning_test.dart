import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/features/admin/widgets/close_year_warning.dart';

void main() {
  // J-25: Close Year said nothing about unpaid fees or open tests.
  test('names unpaid fees and open tests', () {
    final w = closeYearWarning({
      'unpaid_students': 63,
      'unpaid_total': 2500000,
      'open_tests': 2,
    })!;
    expect(w, contains('63 students still owe ₹25,00,000'));
    expect(w, contains('2 tests are still open'));
  });

  test('singular wording', () {
    final w = closeYearWarning(
        {'unpaid_students': 1, 'unpaid_total': 500, 'open_tests': 1})!;
    expect(w, contains('1 student still owes ₹500'));
    expect(w, contains('1 test is still open'));
  });

  test('nothing outstanding, no warning', () {
    expect(closeYearWarning({'unpaid_students': 0, 'open_tests': 0}), isNull);
    expect(closeYearWarning({'year_label': '2026-27'}), isNull);
    expect(closeYearWarning(null), isNull);
  });
}
