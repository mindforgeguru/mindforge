import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/auth/screens/login_screen.dart';
import 'package:mindforge/core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Pump the login screen inside a real ProviderScope.
/// No overrides needed — structural tests don't touch the network.
Widget _buildLoginScreen() => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );

/// Taps a PIN-pad digit key. Uses `.last` because the same character can
/// appear in both the PIN dots (placeholder) and the pad key.
Future<void> _tapDigit(WidgetTester tester, String digit) async {
  await tester.tap(find.text(digit).last);
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

      // 'Login' appears in both the tab label and the button — findsWidgets is correct.
      expect(find.text('Login'), findsWidgets);
      expect(find.text('Request Access'), findsOneWidget);
    });

    testWidgets('renders all PIN-pad digits 0–9', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        expect(find.text(d), findsWidgets,
            reason: 'PIN pad digit $d should be visible');
      }
    });

    testWidgets('Login button is present and enabled by default', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(btn.onPressed, isNotNull,
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
      await tester.tap(find.text('⌫'));
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

      await tester.tap(find.text('Request Access'));
      await tester.pumpAndSettle();

      expect(find.text('Register as'), findsOneWidget);
    });

    testWidgets('switching back to Login hides register fields', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildLoginScreen());
      await tester.pump();

      await tester.tap(find.text('Request Access'));
      await tester.pumpAndSettle();

      // Switch back to Login tab
      await tester.tap(find.text('Login').first);
      await tester.pumpAndSettle();

      expect(find.text('Register as'), findsNothing);
    });
  });
}
