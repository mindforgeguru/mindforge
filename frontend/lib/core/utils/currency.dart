import 'package:intl/intl.dart';

/// Formats a rupee amount for display (J-11).
///
/// Two things the old `NumberFormat.currency(symbol: '₹', decimalDigits: 0)`
/// got wrong on the fee screens:
///  - it used the default (Western) grouping, so ₹99,99,999 showed as
///    ₹9,999,999 — wrong for an Indian audience;
///  - `decimalDigits: 0` rounded paise away, so a ₹0.50 payment read "₹1".
///
/// This uses the Indian locale's lakh/crore grouping and shows paise only when
/// the amount actually has them (₹40,000 stays clean; ₹0.50 stays ₹0.50).
String formatInr(num amount) {
  final hasPaise = (amount.abs() * 100).round() % 100 != 0;
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: hasPaise ? 2 : 0,
  ).format(amount);
}
