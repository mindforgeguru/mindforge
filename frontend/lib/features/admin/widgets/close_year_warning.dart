import '../../../core/utils/currency.dart';

/// What Close Year would leave behind, from `/admin/academic-years/current`
/// (J-25). Null when nothing is outstanding.
String? closeYearWarning(Map<String, dynamic>? year) {
  if (year == null) return null;
  final unpaid = (year['unpaid_students'] as num?)?.toInt() ?? 0;
  final owed = (year['unpaid_total'] as num?) ?? 0;
  final openTests = (year['open_tests'] as num?)?.toInt() ?? 0;
  final lines = <String>[
    if (unpaid > 0)
      '${unpaid == 1 ? '1 student still owes' : '$unpaid students still owe'} '
          '${formatInr(owed)}. They drop off the Payments list once removed, '
          'so download the Pending Fees report (Reports) first.',
    if (openTests > 0)
      '${openTests == 1 ? '1 test is' : '$openTests tests are'} still open; '
          "students who haven't taken ${openTests == 1 ? 'it' : 'them'} "
          "won't be able to.",
  ];
  return lines.isEmpty ? null : lines.join('\n\n');
}
