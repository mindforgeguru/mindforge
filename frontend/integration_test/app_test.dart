import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mindforge/main.dart' as app;

// Admin MPIN — pass via --dart-define=ADMIN_MPIN=xxxxxx if changed from default
// ignore: do_not_use_environment
const _adminMpin = String.fromEnvironment('ADMIN_MPIN', defaultValue: '300573');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Phone-sized viewport for unit-test mode only. On a real device /
  // simulator the binding is LiveTestWidgetsFlutterBinding and the device's
  // real viewport is used — forcing physicalSize there causes hit-tests to
  // land off-screen (the widget tree still uses the real size for layout,
  // but tester.tap's hit-test uses the overridden frame).
  const _phoneSize = Size(390.0, 844.0); // iPhone 14 logical points
  final bool _isUnitTestBinding =
      binding is! LiveTestWidgetsFlutterBinding;

  setUp(() async {
    // Clear saved auth token before every test so each one starts from
    // scratch. Wrapped in try-catch: on macOS the keychain requires a signed
    // app; in test mode the app falls back to "no stored token" automatically.
    try {
      await const FlutterSecureStorage().deleteAll();
    } catch (_) {
      // Ignore keychain errors on macOS test runner — app starts unauthenticated
    }
  });

  // NOTE: A `tearDown(() => binding.takeException())` hook was tried here to
  // stop one failing test from cascading to the rest of the file. It does NOT
  // work on `LiveTestWidgetsFlutterBinding` — `takeException()` asserts
  // `inTest == true` and the binding has already exited the test by the time
  // tearDown runs, so every test fails with `'inTest': is not true`. The
  // proper mitigation here is to make sure each test passes in the first
  // place (cascade only triggers after a failure).

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Advance through the splash screen (total ~4.2s of delays + animations).
  /// In unit-test mode (macOS desktop binding) we also pin a phone-sized
  /// viewport because the default 800×600 canvas clips the PIN pad. On real
  /// simulators we let the device's own viewport govern layout.
  Future<void> passSplash(WidgetTester tester) async {
    if (_isUnitTestBinding) {
      tester.view.physicalSize = _phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// Tap a single keypad digit.
  Future<void> tapDigit(WidgetTester tester, String digit) async {
    final matches = find.text(digit);
    expect(matches, findsWidgets, reason: 'Keypad digit "$digit" not found');
    await tester.tap(matches.last);
    await tester.pump(const Duration(milliseconds: 80));
  }

  Future<void> enterMpin(WidgetTester tester, String mpin) async {
    for (final d in mpin.split('')) {
      await tapDigit(tester, d);
    }
  }

  /// Type username, enter MPIN, tap Login, wait up to 8s for network + nav.
  Future<void> doLogin(WidgetTester tester,
      {required String username, required String mpin}) async {
    await passSplash(tester);

    final usernameField = find.widgetWithText(TextField, 'Username');
    expect(usernameField, findsOneWidget);
    await tester.enterText(usernameField, username);
    await tester.pump();

    await enterMpin(tester, mpin);

    await tester.tap(find.byType(ElevatedButton).first);

    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  // ── Test 1: Splash → Login ─────────────────────────────────────────────────
  testWidgets('Splash screen shows then transitions to login', (tester) async {
    app.main();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    await passSplash(tester);
    expect(find.text('MIND FORGE'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
  });

  // ── Test 2: Request Access tab ─────────────────────────────────────────────
  testWidgets('Request Access tab shows registration form', (tester) async {
    app.main();
    await passSplash(tester);

    await tester.tap(find.text('Request Access'));
    await tester.pumpAndSettle();

    expect(find.text('Register as'), findsWidgets);
  });

  // ── Test 3: MPIN delete clears last digit ─────────────────────────────────
  testWidgets('MPIN delete button clears last digit', (tester) async {
    app.main();
    await passSplash(tester);

    await tapDigit(tester, '1');
    await tapDigit(tester, '2');
    await tapDigit(tester, '3');

    expect(find.text('⌫'), findsOneWidget);
    await tester.tap(find.text('⌫'));
    await tester.pump();

    expect(find.text('MIND FORGE'), findsOneWidget);
    // Drain any pending frames before the test exits
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  // ── Test 4: Wrong credentials → error snackbar ────────────────────────────
  testWidgets('Wrong credentials shows error snackbar', (tester) async {
    app.main();
    await passSplash(tester);

    final usernameField = find.widgetWithText(TextField, 'Username');
    expect(usernameField, findsOneWidget);
    await tester.enterText(usernameField, 'wronguser');
    await tester.pump();

    await enterMpin(tester, '000000');
    await tester.tap(find.byType(ElevatedButton).first);

    // Pump until the snackbar appears (network responds), then assert immediately
    // before the default 4s snackbar duration elapses.
    bool snackbarFound = false;
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Invalid username or MPIN.').evaluate().isNotEmpty) {
        snackbarFound = true;
        break;
      }
    }
    expect(snackbarFound, isTrue,
        reason: 'Expected error snackbar to appear within 6s');
    // Still on login screen
    expect(find.text('MIND FORGE'), findsOneWidget);
    // Let snackbar animation + any pending frames drain fully
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  // ── Test 5: Admin login → dashboard (run last — leaves auth token) ─────────
  testWidgets('Admin can log in and see dashboard', (tester) async {
    app.main();
    await doLogin(tester, username: 'admin', mpin: _adminMpin);

    expect(find.text('Fees'), findsWidgets);
    expect(find.text('Timetable'), findsWidgets);
    expect(find.text('Users'), findsWidgets);
  });
}
