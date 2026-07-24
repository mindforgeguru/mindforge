import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:mindforge/core/models/homework.dart';
import 'package:mindforge/core/models/test.dart';
import 'package:mindforge/core/widgets/realtime_sync.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';
import 'package:mindforge/features/teacher/providers/teacher_provider.dart';

/// Coverage for [RealtimeSync]'s event → cache-invalidation mapping.
///
/// The backend half of the realtime fix has integration coverage
/// (`backend/tests_integration/test_realtime_delivery.py`, which proves an
/// event actually reaches a connected socket). This is the other half: given an
/// event *arrives*, does the client invalidate the right thing?
///
/// That mapping is a long switch keyed on stringly-typed event names, per role.
/// A typo, or an event routed to the wrong role's branch, is invisible to the
/// analyzer and to every existing test — the exact shape of the original bug,
/// where every unit was individually correct and the wiring between them was
/// not.
///
/// An invalidation is only observable if something is *listening*, so each test
/// mounts a Consumer that watches the target provider and counts rebuilds.

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeApiClient extends Fake implements ApiClient {
  // AuthNotifier assigns this in its constructor, so it must be a real field
  // rather than routed through noSuchMethod.
  @override
  void Function()? onUnauthorized;
}

/// A [WebSocketClient] whose stream the test drives directly.
class _FakeWebSocketClient extends WebSocketClient {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> connect(int userId, String token) =>
      _controller.stream;

  @override
  void forceReconnect() {}

  @override
  void disconnect() => _controller.close();

  void emit(Map<String, dynamic> event) => _controller.add(event);
}

/// Lets a test put auth into a logged-in state for a given role.
///
/// Safe to set `state` directly: `_restoreSession()` runs from the superclass
/// constructor but returns early when secure storage is empty or unavailable
/// (both true under `flutter test`), so it never overwrites what we set here.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.api, super.ws, super.storage);

  void logInAs(String role) =>
      state = AuthState(token: 'test-token', role: role, userId: 1);
}

// ── Harness ───────────────────────────────────────────────────────────────────

class _Harness {
  final _FakeWebSocketClient ws;
  final ProviderContainer container;
  int rebuilds;

  _Harness(this.ws, this.container, this.rebuilds);
}

/// Mounts [RealtimeSync] above a Consumer watching [target], logs in as [role],
/// and returns a handle for emitting events and reading the rebuild count.
Future<_Harness> _pump(
  WidgetTester tester, {
  required String role,
  required ProviderListenable<Object?> target,
  required List<Override> overrides,
  required int Function() readCount,
}) async {
  final ws = _FakeWebSocketClient();
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_FakeApiClient()),
        webSocketClientProvider.overrideWithValue(ws),
        authProvider.overrideWith((ref) => _TestAuthNotifier(
              ref.read(apiClientProvider),
              ref.read(webSocketClientProvider),
              const FlutterSecureStorage(),
            )),
        ...overrides,
      ],
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(
          home: RealtimeSync(
            child: Consumer(builder: (_, ref, __) {
              ref.watch(target);
              return const SizedBox.shrink();
            }),
          ),
        );
      }),
    ),
  );
  await tester.pump();

  // Logging in is what makes RealtimeSync open its subscription.
  (container.read(authProvider.notifier) as _TestAuthNotifier).logInAs(role);
  await tester.pump();
  await tester.pump();

  return _Harness(ws, container, readCount());
}

/// Emit an event and let the listener and any invalidation settle.
Future<void> _emit(WidgetTester tester, _FakeWebSocketClient ws,
    Map<String, dynamic> event) async {
  ws.emit(event);
  await tester.pump();
  await tester.pump();
}

void main() {
  // ── Student ────────────────────────────────────────────────────────────────

  testWidgets('student: message_broadcast refreshes the broadcast list',
      (tester) async {
    var builds = 0;
    final h = await _pump(
      tester,
      role: 'student',
      target: studentBroadcastsProvider,
      readCount: () => builds,
      overrides: [
        studentBroadcastsProvider.overrideWith((ref) async {
          builds++;
          return <BroadcastModel>[];
        }),
      ],
    );

    final before = builds;
    await _emit(tester, h.ws, {'event': 'message_broadcast', 'title': 'Hi'});

    expect(builds, greaterThan(before),
        reason: 'a broadcast must refresh the student broadcast list — this is '
            'the case that used to update only the dashboard behind the user');
  });

  testWidgets('student: homework_added refreshes the homework list',
      (tester) async {
    var builds = 0;
    final h = await _pump(
      tester,
      role: 'student',
      target: studentHomeworkProvider,
      readCount: () => builds,
      overrides: [
        studentHomeworkProvider.overrideWith((ref) async {
          builds++;
          return <HomeworkModel>[];
        }),
      ],
    );

    final before = builds;
    await _emit(tester, h.ws, {'event': 'homework_added', 'homework_id': 1});

    expect(builds, greaterThan(before));
  });

  testWidgets('student: an unrelated event does not refresh the broadcast list',
      (tester) async {
    var builds = 0;
    final h = await _pump(
      tester,
      role: 'student',
      target: studentBroadcastsProvider,
      readCount: () => builds,
      overrides: [
        studentBroadcastsProvider.overrideWith((ref) async {
          builds++;
          return <BroadcastModel>[];
        }),
      ],
    );

    final before = builds;
    await _emit(tester, h.ws, {'event': 'attendance_updated'});

    expect(builds, before,
        reason: 'attendance must not invalidate the broadcast list — without '
            'this the mapping could pass by invalidating everything');
  });

  // ── Teacher ────────────────────────────────────────────────────────────────

  testWidgets('teacher: auto_quiz_status refreshes the tests list',
      (tester) async {
    var builds = 0;
    final h = await _pump(
      tester,
      role: 'teacher',
      target: teacherTestsProvider((null, 20)),
      readCount: () => builds,
      overrides: [
        teacherTestsProvider.overrideWith((ref, params) async {
          builds++;
          return <TestModel>[];
        }),
      ],
    );

    final before = builds;
    await _emit(tester, h.ws, {'event': 'auto_quiz_status', 'test_id': 7});

    expect(builds, greaterThan(before),
        reason: 'the auto-quiz placeholder has to appear in the teacher Tests '
            'tab without a manual refresh');
  });

  // ── Role isolation ─────────────────────────────────────────────────────────

  testWidgets('a student session does not run the teacher branch',
      (tester) async {
    var builds = 0;
    final h = await _pump(
      tester,
      role: 'student',
      target: teacherTestsProvider((null, 20)),
      readCount: () => builds,
      overrides: [
        teacherTestsProvider.overrideWith((ref, params) async {
          builds++;
          return <TestModel>[];
        }),
      ],
    );

    final before = builds;
    await _emit(tester, h.ws, {'event': 'auto_quiz_status', 'test_id': 7});

    expect(builds, before,
        reason: 'auto_quiz_status is teacher-only; a student session must not '
            'touch teacher caches');
  });
}
