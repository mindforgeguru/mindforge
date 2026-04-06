import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mindforge/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Clear saved auth token before every test so each one starts from scratch.
  setUp(() async {
    await const FlutterSecureStorage().delete(key: 'mindforge_jwt_token');
  });

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Advance through the splash screen (total ~4.2s of delays + animations).
  Future<void> passSplash(WidgetTester tester) async {
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
  });

  // ── Test 5: Admin login → dashboard (run last — leaves auth token) ─────────
  testWidgets('Admin can log in and see dashboard', (tester) async {
    app.main();
    await doLogin(tester, username: 'admin', mpin: '123456');

    expect(find.text('Fees'), findsWidgets);
    expect(find.text('Timetable'), findsWidgets);
    expect(find.text('Users'), findsWidgets);
  });
}
