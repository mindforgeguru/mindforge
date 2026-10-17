import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/utils/decimal_input.dart';

// Every amount and marks field parsed its text with double.tryParse, which
// takes "NaN", "Infinity", "-500" and "1e9". NaN passed the `<= 0` and range
// checks, and the backend's columns stop at 10^8 (fees) and 10^4 (marks).
String? _type(TextInputFormatter f, String text) {
  final out = f.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
  );
  return out.text == text ? text : null;
}

void main() {
  group('money', () {
    final f = DecimalInputFormatter.money();
    test('takes whole and two-decimal amounts below 10^8', () {
      for (final ok in ['', '0', '5000', '99999999', '99999999.99', '12.5', '12.']) {
        expect(_type(f, ok), ok, reason: ok);
      }
    });
    test('refuses what would be rejected or mis-parsed', () {
      for (final bad in ['NaN', 'Infinity', '-500', '1e9', '100000000', '1.234', '8,5', 'abc', ' 5']) {
        expect(_type(f, bad), isNull, reason: bad);
      }
    });
  });

  group('marks', () {
    final f = DecimalInputFormatter.marks();
    test('takes marks below 10^4', () {
      for (final ok in ['', '0', '9999', '7.5', '9999.99']) {
        expect(_type(f, ok), ok, reason: ok);
      }
    });
    test('refuses the rest', () {
      for (final bad in ['10000', 'NaN', '-1', '8,5', '1e3']) {
        expect(_type(f, bad), isNull, reason: bad);
      }
    });
  });
}
