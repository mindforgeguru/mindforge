import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/features/auth/screens/login_screen.dart';
import 'package:mindforge/core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Stubs the one network call LoginScreen makes on init. getSchools() returns
/// an empty list synchronously so no real dio request (and its timeout timer)
/// is started during structural tests — a live timer outlives the widget and
/// trips flutter_test's "Timer still pending" invariant.
class _FakeApiClient extends Fake implements ApiClient {
  // Plain field, not routed through noSuchMethod: AuthNotifier assigns this in
  // its constructor, so the fake must accept the setter.
  @override
  void Function()? onUnauthorized;

  @override
  Future<List<Map<String, dynamic>>> getSchools() async => const [];
}

/// Answers every sign-in the way the backend does for an MFA-enrolled account
/// that sent no code: 401 with `mfa_required`. The real AuthNotifier turns that
/// into MfaRequiredException, which is what makes the screen show the prompt.
class _MfaRequiredApiClient extends _FakeApiClient {
  /// The (mfaCode, recoveryCode) pair of every sign-in attempt, in order.
  final attempts = <(String?, String?)>[];

  @override
  Future<Map<String, dynamic>> login(String username, String mpin,
      {int? schoolId, String? mfaCode, String? recoveryCode}) async {
    attempts.add((mfaCode, recoveryCode));
    final request = RequestOptions(path: '/auth/login');
    throw DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: request,
        statusCode: 401,
        // With a code the fake rejects it, so the screen stays put.
        data: {
          'detail': mfaCode == null && recoveryCode == null
              ? 'mfa_required'
              : 'Invalid code'
        },
      ),
    );
  }
}

/// Pump the login screen inside a ProviderScope with the network stubbed out.
Widget _buildLoginScreen({ApiClient? api}) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api ?? _FakeApiClient()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );

/// Taps a PIN-pad digit key.
Future<void> _tapDigit(WidgetTester tester, String digit) async {
  await tester.tap(find.byKey(LoginKeys.pinDigit(digit)));
  await tester.pump();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // The login screen is taller than Flutter's default 800×600 test canvas.
  // Set a phone-sized viewport so all elements (tabs, PIN pad) are on-screen.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('LoginScreen — structure', () {
    testWidgets('renders username TextField', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('renders Login and Request Access tabs', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.byKey(LoginKeys.loginTab), findsOneWidget);
      expect(find.byKey(LoginKeys.registerTab), findsOneWidget);
    });

    testWidgets('renders all PIN-pad digits 0–9', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        expect(find.byKey(LoginKeys.pinDigit(d)), findsOneWidget,
            reason: 'PIN pad digit $d should be visible');
      }
    });

    testWidgets('Login button is present and enabled by default', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      final btn = tester.widget<InkWell>(find.descendant(
        of: find.byKey(LoginKeys.submit),
        matching: find.byType(InkWell),
      ));
      expect(btn.onTap, isNotNull,
          reason: 'Button should be enabled when not loading');
    });

    testWidgets('no loading spinner shown on initial render', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('LoginScreen — PIN pad interaction', () {
    testWidgets('tapping digits fills PIN slots', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      // Tap three digits and verify the screen still renders correctly
      for (final d in ['1', '2', '3']) {
        await _tapDigit(tester, d);
      }

      // Screen is still there — no crash or navigation
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('tapping delete (⌫) does not crash', (tester) async {
      // Give the test viewport enough height so the PIN pad and delete key
      // are fully on-screen (the login screen is taller than the default 600px).
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await _tapDigit(tester, '5');
      await tester.tap(find.byKey(LoginKeys.pinDelete));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('LoginScreen — tab switching', () {
    testWidgets('switching to Request Access shows role dropdown', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.byKey(LoginKeys.registerTab));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginKeys.role), findsOneWidget);
    });

    testWidgets('switching back to Login hides register fields', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.byKey(LoginKeys.registerTab));
      await tester.pumpAndSettle();

      // Switch back to Login tab
      await tester.tap(find.byKey(LoginKeys.loginTab));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginKeys.role), findsNothing);
    });
  });

  group('LoginScreen — registration fields', () {
    // Regression: the wide/web layout (width >= 900) omitted the Phone and
    // Email fields, so desktop teacher/student sign-up was impossible — submit
    // requires a phone but there was no field to enter one.
    testWidgets('wide/web layout shows Phone & Email in Request Access',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      // The wide/web layout toggles register mode via this link (not a tab).
      await tester.ensureVisible(find.byKey(LoginKeys.modeToggle));
      await tester.tap(find.byKey(LoginKeys.modeToggle));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginKeys.role), findsOneWidget);
      expect(find.byKey(LoginKeys.phone), findsOneWidget);
      expect(find.byKey(LoginKeys.email), findsOneWidget);
    });
  });

  group('LoginScreen — two-factor prompt', () {
    // Same defect as the delete-account dialog (2026-10-10): the caller
    // disposed the prompt's TextEditingController as soon as showDialog
    // returned, while the dialog was still animating out with a TextField
    // attached to it — a red error screen in debug builds.
    Future<_MfaRequiredApiClient> openPrompt(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _MfaRequiredApiClient();
      await tester.pumpWidget(_buildLoginScreen(api: api));
      await tester.pump();

      await tester.enterText(find.byKey(LoginKeys.username), 'mfa_teacher');
      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await _tapDigit(tester, d);
      }
      await tester.tap(find.byKey(LoginKeys.submit));
      await tester.pumpAndSettle();

      expect(find.text('TWO-FACTOR AUTHENTICATION'), findsOneWidget);
      return api;
    }

    testWidgets('Cancel closes the prompt without a framework error',
        (tester) async {
      final api = await openPrompt(tester);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('TWO-FACTOR AUTHENTICATION'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(api.attempts, [(null, null)], reason: 'Cancel must not retry');
    });

    testWidgets('Verify retries the sign-in with the authenticator code',
        (tester) async {
      final api = await openPrompt(tester);

      await tester.enterText(find.byType(TextField).last, ' 654321 ');
      await tester.tap(find.text('VERIFY'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.attempts, [(null, null), ('654321', null)]);
    });

    testWidgets('the recovery toggle sends the entry as a recovery code',
        (tester) async {
      final api = await openPrompt(tester);

      await tester.tap(find.text("I don't have my phone"));
      await tester.pump();
      expect(find.text('Use my authenticator app instead'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'ABCD-EFGH-JKMN');
      await tester.tap(find.text('VERIFY'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.attempts, [(null, null), (null, 'ABCD-EFGH-JKMN')]);
    });
  });
}
