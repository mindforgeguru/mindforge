import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/models/fees.dart';
import 'package:mindforge/core/providers/badge_provider.dart';
import 'package:mindforge/core/providers/school_logo_provider.dart';
import 'package:mindforge/core/theme/app_theme.dart';
import 'package:mindforge/features/parent/providers/parent_provider.dart';
import 'package:mindforge/features/parent/screens/fees_screen.dart';

// TEST_RECORD §10 item 16: "Parent Fees: RenderFlex overflowed by 13 pixels on
// the bottom at a 390 px viewport", seen in debug only, with the widget never
// pinned down. This renders the real screen with the real local data for
// dummy8_dad (three payment options with bank details, nothing paid yet) at
// 390 px and narrower, on both tabs. In a debug widget test an overflow is a
// reported FlutterError, so any regression fails here.

const _feesJson = r'''{
  "student_id": 26,
  "academic_year": "2026-27",
  "grade": 8,
  "total_fee": 30000.0,
  "total_paid": 0.0,
  "balance_due": 30000.0,
  "base_amount": 30000.0,
  "economics_fee": 0.0,
  "computer_fee": 0.0,
  "ai_fee": 0.0,
  "payments": [],
  "payment_options": [
    {
      "id": 1,
      "slot": 1,
      "label": "Hansal _sir",
      "bank_name": "hdfc",
      "branch": null,
      "account_holder": "Hansal jobanputra",
      "account_number": "1001",
      "ifsc": "HDFC1001",
      "upi_id": "hansal@hdfc",
      "qr_code_url": null,
      "updated_at": "2026-04-02T07:39:09.440569Z"
    },
    {
      "id": 2,
      "slot": 2,
      "label": "chinmay_sir",
      "bank_name": "icici",
      "branch": null,
      "account_holder": "chinmay Jobanputra",
      "account_number": "10002",
      "ifsc": "ICICI1001",
      "upi_id": "chinmay@icici",
      "qr_code_url": null,
      "updated_at": "2026-04-02T07:40:06.557251Z"
    },
    {
      "id": 3,
      "slot": 3,
      "label": "payal_maam",
      "bank_name": "kotak",
      "branch": null,
      "account_holder": "payal jobanputra",
      "account_number": "1007",
      "ifsc": "KOTAK007",
      "upi_id": "payal@kotak",
      "qr_code_url": null,
      "updated_at": "2026-04-02T07:41:06.480326Z"
    }
  ]
}''';

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

/// The real data, plus every optional fee and a payment history — the rows and
/// tiles the real account doesn't exercise (it has paid nothing yet).
Map<String, dynamic> _fuller() {
  final m = jsonDecode(_feesJson) as Map<String, dynamic>;
  return {
    ...m,
    'economics_fee': 5000.0,
    'computer_fee': 6000.0,
    'ai_fee': 4500.0,
    'total_fee': 45500.0,
    'total_paid': 25000.0,
    'balance_due': 20500.0,
    'payments': [
      for (final (i, amt) in [(1, 10000.0), (2, 10000.0), (3, 5000.0)].indexed)
        {
          'id': amt.$1,
          'student_id': m['student_id'],
          'amount': amt.$2,
          'paid_at': '2026-0${i + 6}-15T10:00:00Z',
          'updated_by_admin_id': 280,
          'notes': 'Instalment ${amt.$1} — paid at the school office by cheque',
        },
    ],
  };
}

Future<void> _pumpAt(WidgetTester tester, Size size,
    {Map<String, dynamic>? data, double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fees = StudentFeeSummaryModel.fromJson(
      data ?? jsonDecode(_feesJson) as Map<String, dynamic>);
  final router = GoRouter(
    initialLocation: '/parent/fees',
    routes: [
      GoRoute(path: '/parent/fees', builder: (_, __) => const ParentFeesScreen()),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_FakeApiClient()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      parentChildFeesProvider.overrideWith((ref) async => fees),
      currentSchoolLogoProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final variants = <String, Map<String, dynamic>? Function()>{
    'real data': () => null,
    'every fee + payment history': _fuller,
  };
  for (final MapEntry(key: name, value: data) in variants.entries) {
    for (final size in const [Size(390, 844), Size(360, 740), Size(320, 640)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}, $name';

      testWidgets('Summary tab lays out without overflow at $label', (tester) async {
        await _pumpAt(tester, size, data: data());
        expect(find.byType(ParentFeesScreen), findsOneWidget);
        // Scroll the summary so the payment history is built and laid out too.
        final list = find.byType(Scrollable).last;
        for (var i = 0; i < 6; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('Pay tab lays out without overflow at $label', (tester) async {
        await _pumpAt(tester, size, data: data());
        await tester.tap(find.text('Pay'));
        await tester.pumpAndSettle();
        // Scroll the whole list so every payment-option card is built and laid out.
        final list = find.byType(Scrollable).last;
        for (var i = 0; i < 8; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Large accessibility text is the realistic way a phone hits this: the label
  // and amount no longer fit side by side, so the label must wrap.
  testWidgets('Summary tab survives 1.5x text at 390 px with every fee',
      (tester) async {
    await _pumpAt(tester, const Size(390, 844), data: _fuller(), textScale: 1.5);
    final list = find.byType(Scrollable).last;
    for (var i = 0; i < 6; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
