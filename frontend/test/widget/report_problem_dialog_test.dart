import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/widgets/report_problem_dialog.dart';

// Seen on the simulator, 2026-10-10: Send on "Report a problem" always
// answered "Could not send. Please try again." and no request left the app.
// The dialog read the current route with GoRouterState.of(context) from its
// own context — but a dialog is pushed on the root navigator, above every
// GoRoute, so the lookup threw and the catch-all turned it into a send
// failure. Every role's report button was affected. These mount the dialog
// the way the app does: from a screen inside a real GoRouter.

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;

  final sent = <({String message, String? route})>[];
  Object? failWith;

  @override
  Future<void> submitFeedback({
    required String message,
    String? appVersion,
    String? route,
  }) async {
    if (failWith != null) throw failWith!;
    sent.add((message: message, route: route));
  }
}

class _Screen extends ConsumerWidget {
  const _Screen();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showReportProblemDialog(context, ref),
            child: const Text('open'),
          ),
        ),
      );
}

Future<_FakeApiClient> _open(WidgetTester tester) async {
  final api = _FakeApiClient();
  final router = GoRouter(
    initialLocation: '/teacher/tests',
    routes: [
      GoRoute(path: '/teacher/tests', builder: (_, __) => const _Screen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('Send submits the message with the screen it was opened from',
      (tester) async {
    final api = await _open(tester);

    await tester.enterText(find.byType(TextField), 'The quiz would not open');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.sent, hasLength(1));
    expect(api.sent.single.message, 'The quiz would not open');
    expect(api.sent.single.route, '/teacher/tests');
    expect(find.text('Report a problem'), findsNothing);
    expect(find.text('Thanks — your report was sent.'), findsOneWidget);
  });

  testWidgets('a server failure keeps the dialog and the text', (tester) async {
    final api = await _open(tester);
    api.failWith = Exception('500');

    await tester.enterText(find.byType(TextField), 'The quiz would not open');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Could not send. Please try again.'), findsOneWidget);
    expect(find.text('The quiz would not open'), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets('a message under three characters is not sent', (tester) async {
    final api = await _open(tester);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(api.sent, isEmpty);
    expect(find.text('Report a problem'), findsOneWidget);
  });
}
