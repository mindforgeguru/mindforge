import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:mindforge/core/utils/constants.dart';
import 'package:mindforge/core/widgets/privacy_data_section.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';

// Seen on the iPhone 17 Pro simulator, 2026-10-10: the parent's "Delete
// account?" dialog autofocuses its field, the keyboard opens, and the content
// — cascade warning, explanation, field — no longer fits: "BOTTOM OVERFLOWED
// BY 41 PIXELS", with the "Type your username below to confirm" line pushed
// under the field. In a debug widget test an overflow is a reported
// FlutterError, so opening the dialog over a keyboard-sized inset fails here.

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

class _FakeWebSocketClient extends WebSocketClient {
  @override
  Stream<Map<String, dynamic>> connect(int userId, String token) =>
      const Stream.empty();

  @override
  void forceReconnect() {}

  @override
  void disconnect() {}
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.api, super.ws, super.storage) {
    state = const AuthState(
        token: 'test-token', role: 'parent', userId: 25, username: 'dummy8_dad');
  }
}

Future<void> _openDialog(
  WidgetTester tester, {
  required Size size,
  required double keyboard,
  String? warning,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_FakeApiClient()),
        webSocketClientProvider.overrideWithValue(_FakeWebSocketClient()),
        authProvider.overrideWith((ref) => _TestAuthNotifier(
              ref.read(apiClientProvider),
              ref.read(webSocketClientProvider),
              const FlutterSecureStorage(),
            )),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PrivacyDataSection(deleteWarning: warning),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Delete my account'));
  await tester.pumpAndSettle();
}

void main() {
  // iPhone 17 Pro is 402 x 874 pt; its keyboard with the suggestion bar takes
  // about 336 pt. The smaller case is an iPhone SE-sized screen.
  for (final (name, size, keyboard) in [
    ('iPhone 17 Pro', const Size(402, 874), 336.0),
    ('small phone', const Size(320, 568), 260.0),
  ]) {
    testWidgets('parent delete dialog fits above the keyboard — $name',
        (tester) async {
      await _openDialog(tester,
          size: size,
          keyboard: keyboard,
          warning: PrivacyDataSection.parentCascadeWarning);

      expect(tester.takeException(), isNull);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(find.textContaining('linked student account'), findsOneWidget);
    });
  }

  testWidgets('Delete stays disabled until the username is typed exactly',
      (tester) async {
    await _openDialog(tester,
        size: const Size(402, 874),
        keyboard: 336,
        warning: PrivacyDataSection.parentCascadeWarning);

    FilledButton delete() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
    expect(delete().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'dummy8');
    await tester.pump();
    expect(delete().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'dummy8_dad');
    await tester.pump();
    expect(delete().onPressed, isNotNull);
  });

  // Also seen on the simulator: Cancel put the framework's red error screen up
  // ("'_dependents.isEmpty': is not true"). The caller disposed the dialog's
  // TextEditingController as soon as showDialog returned, while the dialog was
  // still animating out with a TextField attached to it.
  testWidgets('Cancel closes the dialog without a framework error',
      (tester) async {
    await _openDialog(tester,
        size: const Size(402, 874),
        keyboard: 336,
        warning: PrivacyDataSection.parentCascadeWarning);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Delete account?'), findsNothing);
    expect(find.text('Delete my account'), findsOneWidget);
  });

  // The student profile hides the delete tile, and until a privacy-policy URL
  // is configured there is no policy link either — which left a "Privacy &
  // Data" heading with nothing under it.
  testWidgets('no heading when the section has nothing to show',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrivacyDataSection(showDeleteButton: false),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Privacy & Data'),
        AppConstants.privacyPolicyUrl.isEmpty ? findsNothing : findsOneWidget);
    expect(find.text('Delete my account'), findsNothing);
    expect(find.text('About'), findsOneWidget);
  });
}
