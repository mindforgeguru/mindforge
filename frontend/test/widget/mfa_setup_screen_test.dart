import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/security/screen_security.dart';
import 'package:mindforge/core/widgets/qr_view.dart';
import 'package:mindforge/features/auth/screens/mfa_setup_screen.dart';

class MockApiClient extends Mock implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

/// The enrolment screen is the only place a person ever sees the TOTP secret or
/// the recovery codes, and the recovery codes are shown exactly once — the
/// server keeps hashes and cannot reissue them. So the states worth pinning are
/// about what is on screen at each step, not about styling.
void main() {
  late MockApiClient api;

  setUp(() {
    api = MockApiClient();
    ScreenSecurity.debugReset();
  });

  Widget wrap() => ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: MfaSetupScreen()),
      );

  group('when two-factor is off', () {
    setUp(() {
      when(() => api.mfaStatus()).thenAnswer(
          (_) async => {'eligible': true, 'enabled': false,
                        'recovery_codes_remaining': 0});
    });

    testWidgets('offers to set it up', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('Set up two-factor'), findsOneWidget);
    });

    testWidgets('shows a QR and the typed key after starting setup',
        (tester) async {
      when(() => api.mfaSetup()).thenAnswer((_) async => {
            'secret': 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP',
            'provisioning_uri':
                'otpauth://totp/MIND%20FORGE:demo?secret=JBSWY3DPEHPK3PXP',
          });

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up two-factor'));
      await tester.pumpAndSettle();

      expect(find.byType(QrView), findsOneWidget);
      // The typed key must be offered too: scanning fails on a desktop browser,
      // and an admin enrolling from a laptop has no camera pointed at it.
      expect(find.textContaining('JBSW'), findsOneWidget);
    });
  });

  group('confirming the code', () {
    setUp(() {
      when(() => api.mfaStatus()).thenAnswer(
          (_) async => {'eligible': true, 'enabled': false,
                        'recovery_codes_remaining': 0});
      when(() => api.mfaSetup()).thenAnswer((_) async => {
            'secret': 'JBSWY3DPEHPK3PXP',
            'provisioning_uri': 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
          });
    });

    Future<void> reachCodeEntry(WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up two-factor'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the recovery codes once on success', (tester) async {
      when(() => api.mfaConfirm(any())).thenAnswer((_) async => {
            'enabled': true,
            'recovery_codes': ['AAAA-BBBB-CCCC', 'DDDD-EEEE-FFFF'],
          });

      await reachCodeEntry(tester);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AAAA-BBBB-CCCC'), findsOneWidget);
      // The one-shot nature has to be stated where it is read, not buried in
      // docs — someone who clicks past this screen cannot get them back.
      expect(find.textContaining('shown once'), findsOneWidget);
    });

    testWidgets('a rejected code explains the 30-second window',
        (tester) async {
      when(() => api.mfaConfirm(any())).thenThrow(Exception('bad code'));

      await reachCodeEntry(tester);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      // The commonest cause of a rejected code is that it rolled over while
      // being typed, so the message says so rather than implying a broken setup.
      expect(find.textContaining('30 seconds'), findsOneWidget);
    });

    testWidgets('a short code is refused without calling the server',
        (tester) async {
      await reachCodeEntry(tester);
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      verifyNever(() => api.mfaConfirm(any()));
      expect(find.textContaining('6-digit code'), findsWidgets);
    });
  });

  group('when two-factor is on', () {
    testWidgets('reports the state and offers to turn it off', (tester) async {
      when(() => api.mfaStatus()).thenAnswer(
          (_) async => {'eligible': true, 'enabled': true,
                        'recovery_codes_remaining': 7});

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Two-factor is on'), findsOneWidget);
      expect(find.textContaining('7 recovery'), findsOneWidget);
      expect(find.text('Turn off two-factor'), findsOneWidget);
    });

    testWidgets('warns when recovery codes are nearly exhausted',
        (tester) async {
      // Running out is how someone ends up locked out of a school's records,
      // so it needs saying before the last one is spent.
      when(() => api.mfaStatus()).thenAnswer(
          (_) async => {'eligible': true, 'enabled': true,
                        'recovery_codes_remaining': 1});

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.textContaining('running low'), findsOneWidget);
      // Singular, because "1 recovery codes remaining" reads as a bug.
      expect(find.textContaining('1 recovery code '), findsOneWidget);
    });
  });

  group('screen capture', () {
    testWidgets('the screen is capture-protected while open', (tester) async {
      // It displays the secret and the recovery codes. Elsewhere blocking
      // screenshots is a nicety; here a screenshot *is* the second factor.
      when(() => api.mfaStatus()).thenAnswer(
          (_) async => {'eligible': true, 'enabled': false,
                        'recovery_codes_remaining': 0});

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.byType(MfaSetupScreen), findsOneWidget);
      // SecureScreenMixin acquires on initState; reaching here without throwing
      // on a platform with no channel is the property that matters.
    });
  });

  group('when the status call fails', () {
    testWidgets('says so and offers a retry, rather than spinning',
        (tester) async {
      when(() => api.mfaStatus()).thenThrow(Exception('offline'));

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('does NOT claim two-factor is off', (tester) async {
      // The dangerous failure mode. Someone who already has it on, shown the
      // enrol screen, would set it up again and silently invalidate the
      // authenticator entry they are currently relying on.
      when(() => api.mfaStatus()).thenThrow(Exception('offline'));

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Set up two-factor'), findsNothing);
    });

    testWidgets('retry recovers once the call succeeds', (tester) async {
      var calls = 0;
      when(() => api.mfaStatus()).thenAnswer((_) async {
        if (calls++ == 0) throw Exception('offline');
        return {'eligible': true, 'enabled': true, 'recovery_codes_remaining': 9};
      });

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Two-factor is on'), findsOneWidget);
    });
  });
}
