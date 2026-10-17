import 'package:flutter/services.dart';

/// Lets a field hold only an unsigned decimal the backend will accept.
///
/// double.tryParse takes "NaN", "Infinity", "-500" and "1e9", and NaN slips
/// past `<= 0` and range checks. The backend's columns are NUMERIC(10, 2) for
/// fees and NUMERIC(6, 2) for marks, so anything at or above 10^8 / 10^4 was
/// refused there. An edit that would leave anything else is ignored.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter({required int maxWholeDigits, int decimals = 2})
      : _pattern = RegExp('^\\d{0,$maxWholeDigits}(\\.\\d{0,$decimals})?\$');

  /// Rupees: below 10^8, to the paisa.
  DecimalInputFormatter.money() : this(maxWholeDigits: 8);

  /// Marks: below 10^4, to two places.
  DecimalInputFormatter.marks() : this(maxWholeDigits: 4);

  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}
