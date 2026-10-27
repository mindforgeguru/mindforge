import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/utils/currency.dart';

void main() {
  test('Indian grouping and paise', () {
    expect(formatInr(0.50), '₹0.50');          // paise kept, not rounded to ₹1
    expect(formatInr(40000), '₹40,000');        // whole rupees, no decimals
    expect(formatInr(9999999), '₹99,99,999');   // Indian grouping (lakh)
    expect(formatInr(10052000), '₹1,00,52,000');// crore grouping
    expect(formatInr(1234.5), '₹1,234.50');     // paise shown
    expect(formatInr(0), '₹0');
  });
}
