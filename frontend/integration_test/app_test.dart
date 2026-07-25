import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mindforge/main.dart' as app;

// Admin credentials. Defaults are the account documented in
// docs/local-test-accounts.md — `demo_admin` exists in each of the local dev
// schools, so it also exercises resolving a username within one school.
//
// The old default (`admin` / 300573) came from
// backend/scripts/seed_integration_test_users.py, which predates multi-tenancy
// and no longer matches the local database: that MPIN now returns 401. Override
// both for a differently-seeded stack.
// ignore: do_not_use_environment
const _adminUser = String.fromEnvironment('ADMIN_USER',
    defaultValue: 'demo_admin');
// ignore: do_not_use_environment
const _adminMpin = String.fromEnvironment('ADMIN_MPIN', defaultValue: '847362');

// School to sign into. Multi-tenancy (2026-07-22) made the login form require
// one, and the seeded local accounts (admin / chinmay_sir / dummy8 /
// dummy8_dad) all live in school id 1, "Hansel & Gretel". Override with
// --dart-define=SCHOOL_NAME=... when pointing at a differently-seeded stack.
// ignore: do_not_use_environment
const _schoolName =
    String.fromEnvironment('SCHOOL_NAME', defaultValue: 'Hansel & Gretel');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Phone-sized viewport for unit-test mode only. On a real device /
  // simulator the binding is LiveTestWidgetsFlutterBinding and the device's
  // real viewport is used — forcing physicalSize there causes hit-tests to
  // land off-screen (the widget tree still uses the real size for layout,
  // but tester.tap's hit-test uses the overridden frame).
  const _phoneSize = Size(390.0, 844.0); // iPhone 14 logical points
  // Runtime binding-type guard: under `flutter test` the binding is not a
  // LiveTestWidgetsFlutterBinding, but its static type makes the analyzer
  // think this check is always false. Keep it — it governs the phone-size
  // override below.
  // ignore: unnecessary_type_check
  final bool _isUnitTestBinding = binding is! LiveTestWidgetsFlutterBinding;

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

  /// Start the app, then take error reporting back from it.
  ///
  /// `main()` installs Crashlytics as both `FlutterError.onError` and
  /// `PlatformDispatcher.onError` (main.dart:63-64) before calling runApp().
  /// Inside a widget test that displaces the binding's own reporter, so a
  /// framework error is shipped to Crashlytics instead of being recorded as a
  /// test failure. The binding then trips
  ///
  ///     'package:flutter_test/src/binding.dart': Failed assertion:
  ///     '_pendingExceptionDetails != null': A test overrode
  ///     FlutterError.onError but either failed to return it to its original
  ///     state, or had unexpected additional errors that it could not handle.
  ///
  /// — an assertion that names this exact situation and, crucially, replaces
  /// whatever actually went wrong with a message about error handling. That is
  /// why the admin-login failure had no visible cause for so long.
  ///
  /// Restoring both handlers once the app has mounted puts real failures back
  /// in front of the test framework. Do not call `app.main()` directly.
  Future<void> launchApp(WidgetTester tester) async {
    final flutterOnError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;

    app.main();

    // `main()` is async — it awaits Firebase, Crashlytics, Analytics and
    // SharedPreferences before runApp(), so the first frame has no MaterialApp
    // and the handler override has not happened yet either. Pump until the app
    // is actually up, then reclaim.
    for (int i = 0; i < 60 && find.byType(MaterialApp).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    FlutterError.onError = flutterOnError;
    PlatformDispatcher.instance.onError = platformOnError;
  }

  /// `pumpAndSettle` with a short timeout instead of the 10-minute default.
  ///
  /// A never-settling tree is a bug worth surfacing in seconds, not a stall
  /// worth waiting ten minutes for. The default turned a failing run into a
  /// 13-minute hang that printed nothing until it was killed, which made every
  /// diagnosis cycle unaffordable. 20 s is far beyond any real animation here
  /// (the longest is the ~4.2 s splash, which is pumped manually anyway).
  ///
  /// Note this *throws* on timeout rather than continuing, so a hang now
  /// becomes a legible test failure pointing at the exact await.
  Future<void> settle(WidgetTester tester,
      [Duration step = const Duration(milliseconds: 100)]) {
    return tester.pumpAndSettle(step, EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20));
  }

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
    await settle(tester);
  }

  /// Choose a school in the login form.
  ///
  /// Required since multi-tenancy landed: `login_screen.dart` bails out with
  /// "Please select your school." and never calls the API while the picker is
  /// unset, so a login attempt without this silently does nothing and any
  /// assertion about the *result* of logging in waits forever.
  ///
  /// Tolerates builds with no picker (single-school deployments pre-select and
  /// the backend resolves the sole school itself), but fails loudly if the
  /// picker is there and the expected school is missing — that means the
  /// backend is unreachable or unseeded, which is worth distinguishing from a
  /// genuine UI failure.
  Future<void> selectSchool(WidgetTester tester) async {
    final dropdown = find.byType(DropdownButtonFormField<int>);
    if (dropdown.evaluate().isEmpty) return;

    // getSchools() is an async network call from the login screen's initState;
    // its options aren't in the tree until it returns, and pumpAndSettle does
    // not wait on the network in a live test. A dropdown captures its items
    // when opened, so if the schools haven't loaded yet, reopening is the only
    // way to pick them up — poll by close-and-reopen until the option appears.
    for (int attempt = 0; attempt < 15; attempt++) {
      await tester.tap(dropdown.first);
      await settle(tester);

      final option = find.text(_schoolName);
      if (option.evaluate().isNotEmpty) {
        // `.last` targets the item inside the opened menu: a selected school
        // also renders its name in the closed field, so it can match twice.
        await tester.tap(option.last);
        await settle(tester);
        return;
      }

      // Options not loaded yet: dismiss the menu (modal barrier), wait, reopen.
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }

    fail('School "$_schoolName" never appeared in the picker (15 attempts). '
        'Is the backend up at the LOCAL_DEV address and seeded? Override with '
        '--dart-define=SCHOOL_NAME=...');
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

  /// Tap the Login button, scrolling it into view first.
  ///
  /// The school picker added roughly a field's worth of height to the form and
  /// pushed the button just past the bottom edge — it resolved to
  /// `Offset(201.0, 874.3)` against a render tree of `Size(402.0, 874.0)`, i.e.
  /// off-screen by a third of a pixel. `tap()` then warns and misses instead of
  /// failing outright, so the test hangs waiting for a login that never
  /// started. Scrolling first keeps this robust against further layout growth.
  Future<void> tapLogin(WidgetTester tester) async {
    final button = find.byType(ElevatedButton).first;
    await tester.ensureVisible(button);
    await settle(tester);
    await tester.tap(button);
  }

  /// Type username, enter MPIN, tap Login, wait up to 8s for network + nav.
  Future<void> doLogin(WidgetTester tester,
      {required String username, required String mpin}) async {
    await passSplash(tester);
    await selectSchool(tester);

    final usernameField = find.widgetWithText(TextField, 'Username');
    expect(usernameField, findsOneWidget);
    await tester.enterText(usernameField, username);
    await tester.pump();

    await enterMpin(tester, mpin);

    await tapLogin(tester);

    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  // ── Test 1: Splash → Login ─────────────────────────────────────────────────
  testWidgets('Splash screen shows then transitions to login', (tester) async {
    // launchApp already pumps until the app mounts, so this asserts the
    // outcome rather than racing main()'s async startup.
    await launchApp(tester);
    expect(find.byType(MaterialApp), findsOneWidget);
    await passSplash(tester);
    expect(find.text('MIND FORGE'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
  });

  // ── Test 2: Request Access tab ─────────────────────────────────────────────
  testWidgets('Request Access tab shows registration form', (tester) async {
    await launchApp(tester);
    await passSplash(tester);

    await tester.tap(find.text('Request Access'));
    await settle(tester);

    expect(find.text('Register as'), findsWidgets);
  });

  // ── Test 3: MPIN delete clears last digit ─────────────────────────────────
  testWidgets('MPIN delete button clears last digit', (tester) async {
    await launchApp(tester);
    await passSplash(tester);

    await tapDigit(tester, '1');
    await tapDigit(tester, '2');
    await tapDigit(tester, '3');

    expect(find.text('⌫'), findsOneWidget);
    await tester.tap(find.text('⌫'));
    await tester.pump();

    expect(find.text('MIND FORGE'), findsOneWidget);
    // Drain any pending frames before the test exits
    await settle(tester, const Duration(seconds: 1));
  });

  // ── Test 4: Wrong credentials → error snackbar ────────────────────────────
  testWidgets('Wrong credentials shows error snackbar', (tester) async {
    await launchApp(tester);
    await passSplash(tester);
    // Without this the form short-circuits on "Please select your school."
    // and never reaches the API, so the credential error under test never
    // appears and this asserts on the wrong snackbar entirely.
    await selectSchool(tester);

    final usernameField = find.widgetWithText(TextField, 'Username');
    expect(usernameField, findsOneWidget);
    await tester.enterText(usernameField, 'wronguser');
    await tester.pump();

    await enterMpin(tester, '000000');
    await tapLogin(tester);

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
    await launchApp(tester);
    await doLogin(tester, username: _adminUser, mpin: _adminMpin);

    expect(find.text('Fees'), findsWidgets);
    expect(find.text('Timetable'), findsWidgets);
    expect(find.text('Users'), findsWidgets);
  });
}
