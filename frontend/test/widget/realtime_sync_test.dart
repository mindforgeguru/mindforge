import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:mindforge/core/widgets/realtime_sync.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';
import 'package:mindforge/features/parent/providers/parent_provider.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';
import 'package:mindforge/features/student/providers/xp_provider.dart';
import 'package:mindforge/features/teacher/providers/presentation_provider.dart';
import 'package:mindforge/features/teacher/providers/teacher_provider.dart';

/// Exhaustive coverage of [RealtimeSync]'s event → cache-invalidation mapping.
///
/// The backend half of the realtime fix has integration coverage
/// (`backend/tests_integration/test_realtime_delivery.py`, which proves an
/// event actually reaches a connected socket). This is the other half: given an
/// event arrives, does the client invalidate exactly the right caches?
///
/// That mapping is a long switch keyed on stringly-typed event names, per role.
/// A typo in a `case`, an event routed into the wrong role's branch, or a case
/// invalidating the wrong provider are all invisible to the analyzer and to
/// every other test. This exercises **every** event name each role handles and
/// asserts the *exact* set of tracked providers that refreshed — so a missing
/// invalidation (typo) and an over-broad one (wrong case) both fail.
///
/// How it observes: each tracked provider is overridden with a stub that bumps
/// a counter every time it (re)builds, and a `container.listen` keeps it alive
/// so an `invalidate` actually forces a rebuild. The stub is an `async` closure
/// that throws — `Future<Never>` satisfies `Future<T>` for any `T`, so one
/// shape works for every provider regardless of its model type, and the thrown
/// value is captured into `AsyncError` rather than surfacing as an uncaught
/// error. The test only cares that build ran, not what it returned.

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

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

/// `_restoreSession()` runs from the superclass constructor but returns early
/// when secure storage is empty (true under `flutter test`), so setting `state`
/// here is safe.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.api, super.ws, super.storage);
  void logInAs(String role) =>
      state = AuthState(token: 'test-token', role: role, userId: 1);
}

// ── Rebuild counters ────────────────────────────────────────────────────────

/// A build counter shared by all the stub overrides in one test.
class _Counters {
  final Map<String, int> _n = {};
  int bump(String key) => _n[key] = (_n[key] ?? 0) + 1;
  Map<String, int> snapshot() => Map.of(_n);
}

/// The value every stub provider "returns" — an async throw, captured into
/// AsyncError. Never observed; the counter bump before it is the point.
Never _stub() => throw Exception('realtime_sync_test stub — counts rebuilds only');

const _date = '2026-01-01';

// ── Harness ───────────────────────────────────────────────────────────────────

class _Rig {
  final _FakeWebSocketClient ws;
  final _Counters counters;
  // Held only to keep the keep-alive listeners from being collected for the
  // lifetime of the test; never read.
  // ignore: unused_field
  final List<ProviderSubscription> _keepAlive;
  _Rig(this.ws, this.counters, this._keepAlive);
}

/// Mounts [RealtimeSync], overrides + listens to every provider in [tracked],
/// and logs in as [role]. [tracked] maps a short key to the provider to watch;
/// its overrides must be supplied separately (they need the counter) via
/// [overrides]. [listen] attaches a keep-alive listener to each, using concrete
/// family arguments where needed.
Future<_Rig> _pumpRole(
  WidgetTester tester, {
  required String role,
  required _Counters counters,
  required List<Override> overrides,
  required List<ProviderSubscription> Function(ProviderContainer) listen,
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
        return const MaterialApp(home: RealtimeSync(child: SizedBox.shrink()));
      }),
    ),
  );
  await tester.pump();

  final subs = listen(container);
  (container.read(authProvider.notifier) as _TestAuthNotifier).logInAs(role);
  await tester.pump();
  await tester.pump();

  return _Rig(ws, counters, subs);
}

/// Emit [event], then assert that exactly [expected] (of [tracked]) refreshed,
/// and that the always-invalidated dashboard summary refreshed too.
Future<void> _expectRefresh(
  WidgetTester tester,
  _Rig rig, {
  required String event,
  required Set<String> tracked,
  required Set<String> expected,
}) async {
  final before = rig.counters.snapshot();
  rig.ws.emit({'event': event});
  await tester.pump();
  await tester.pump();
  final after = rig.counters.snapshot();

  int n(Map<String, int> m, String k) => m[k] ?? 0;
  final advanced = {
    for (final k in tracked)
      if (n(after, k) > n(before, k)) k,
  };

  expect(advanced, expected,
      reason: 'event "$event": expected exactly $expected to refresh, got '
          '$advanced. A missing entry is a typo in the case label; an extra '
          'entry is an over-broad or misrouted invalidation.');
  expect(n(after, 'dashboard'), greaterThan(n(before, 'dashboard')),
      reason: 'event "$event": the dashboard summary is invalidated for every '
          'event and must always refresh');
}

void main() {
  // ── Student ────────────────────────────────────────────────────────────────

  testWidgets('student: every handled event invalidates exactly its caches',
      (tester) async {
    final c = _Counters();
    const tracked = {
      'broadcasts', 'tests', 'xp', 'homework',
      'attendance', 'grades', 'fees', 'timetable',
    };

    final rig = await _pumpRole(
      tester,
      role: 'student',
      counters: c,
      overrides: [
        studentDashboardSummaryProvider.overrideWith((ref, _) async {
          c.bump('dashboard');
          _stub();
        }),
        studentBroadcastsProvider.overrideWith((ref) async {
          c.bump('broadcasts');
          _stub();
        }),
        pendingTestsProvider.overrideWith((ref) async {
          c.bump('tests');
          _stub();
        }),
        studentXpProvider.overrideWith((ref) async {
          c.bump('xp');
          _stub();
        }),
        studentHomeworkProvider.overrideWith((ref) async {
          c.bump('homework');
          _stub();
        }),
        studentAttendanceProvider.overrideWith((ref) async {
          c.bump('attendance');
          _stub();
        }),
        studentGradesProvider.overrideWith((ref, _) async {
          c.bump('grades');
          _stub();
        }),
        studentFeesProvider.overrideWith((ref) async {
          c.bump('fees');
          _stub();
        }),
        studentTimetableProvider.overrideWith((ref, _) async {
          c.bump('timetable');
          _stub();
        }),
      ],
      listen: (container) => [
        container.listen(studentDashboardSummaryProvider(_date), (_, __) {}),
        container.listen(studentBroadcastsProvider, (_, __) {}),
        container.listen(pendingTestsProvider, (_, __) {}),
        container.listen(studentXpProvider, (_, __) {}),
        container.listen(studentHomeworkProvider, (_, __) {}),
        container.listen(studentAttendanceProvider, (_, __) {}),
        container.listen(studentGradesProvider(null), (_, __) {}),
        container.listen(studentFeesProvider, (_, __) {}),
        container.listen(studentTimetableProvider(_date), (_, __) {}),
      ],
    );

    const expected = <String, Set<String>>{
      'message_broadcast': {'broadcasts'},
      'new_test_available': {'tests'},
      'test_status_changed': {'tests'},
      'test_completed': {'tests'},
      'level_up': {'xp'},
      'test_submitted': {'xp'},
      'homework_added': {'homework', 'xp'},
      'homework_completion_updated': {'homework', 'xp'},
      'attendance_updated': {'attendance', 'xp'},
      'grade_added': {'grades', 'xp'},
      'grade_deleted': {'grades', 'xp'},
      'fee_payment_recorded': {'fees'},
      'timetable_updated': {'timetable'},
      'timetable_config_updated': {'timetable'},
    };

    for (final entry in expected.entries) {
      await _expectRefresh(tester, rig,
          event: entry.key, tracked: tracked, expected: entry.value);
    }
  });

  // ── Teacher (and admin, which shares the branch) ─────────────────────────────

  testWidgets('teacher: every handled event invalidates exactly its caches',
      (tester) async {
    final c = _Counters();
    const tracked = {
      'broadcasts', 'tests', 'homework',
      'attendance', 'grades', 'presentation', 'timetable',
    };

    final rig = await _pumpRole(
      tester,
      role: 'teacher',
      counters: c,
      overrides: [
        teacherDashboardSummaryProvider.overrideWith((ref) async {
          c.bump('dashboard');
          _stub();
        }),
        teacherBroadcastsProvider.overrideWith((ref) async {
          c.bump('broadcasts');
          _stub();
        }),
        teacherTestsProvider.overrideWith((ref, _) async {
          c.bump('tests');
          _stub();
        }),
        teacherHomeworkProvider.overrideWith((ref, _) async {
          c.bump('homework');
          _stub();
        }),
        teacherAttendanceProvider.overrideWith((ref, _) async {
          c.bump('attendance');
          _stub();
        }),
        teacherGradesProvider.overrideWith((ref, _) async {
          c.bump('grades');
          _stub();
        }),
        presentationListProvider.overrideWith((ref) async {
          c.bump('presentation');
          _stub();
        }),
        teacherTimetableProvider.overrideWith((ref, _) async {
          c.bump('timetable');
          _stub();
        }),
      ],
      listen: (container) => [
        container.listen(teacherDashboardSummaryProvider, (_, __) {}),
        container.listen(teacherBroadcastsProvider, (_, __) {}),
        container.listen(teacherTestsProvider((null, 20)), (_, __) {}),
        container.listen(teacherHomeworkProvider(null), (_, __) {}),
        container.listen(teacherAttendanceProvider((8, _date)), (_, __) {}),
        container.listen(teacherGradesProvider((null, null)), (_, __) {}),
        container.listen(presentationListProvider, (_, __) {}),
        container.listen(teacherTimetableProvider((8, _date)), (_, __) {}),
      ],
    );

    const expected = <String, Set<String>>{
      'message_broadcast': {'broadcasts'},
      'auto_quiz_status': {'tests'},
      'new_test_available': {'tests'},
      'test_status_changed': {'tests'},
      'test_completed': {'tests'},
      'test_submitted': {'tests'},
      'homework_added': {'homework'},
      'homework_completion_updated': {'homework'},
      'attendance_updated': {'attendance'},
      'grade_added': {'grades'},
      'grade_deleted': {'grades'},
      'presentation_ready': {'presentation'},
      'timetable_updated': {'timetable'},
      'timetable_config_updated': {'timetable'},
    };

    for (final entry in expected.entries) {
      await _expectRefresh(tester, rig,
          event: entry.key, tracked: tracked, expected: entry.value);
    }
  });

  // ── Parent ───────────────────────────────────────────────────────────────────

  testWidgets('parent: every handled event invalidates exactly its caches',
      (tester) async {
    final c = _Counters();
    const tracked = {
      'broadcasts', 'tests', 'homework',
      'attendance', 'grades', 'fees', 'timetable',
    };

    final rig = await _pumpRole(
      tester,
      role: 'parent',
      counters: c,
      overrides: [
        parentDashboardSummaryProvider.overrideWith((ref, _) async {
          c.bump('dashboard');
          _stub();
        }),
        parentBroadcastsProvider.overrideWith((ref) async {
          c.bump('broadcasts');
          _stub();
        }),
        parentChildTestsProvider.overrideWith((ref) async {
          c.bump('tests');
          _stub();
        }),
        parentHomeworkProvider.overrideWith((ref) async {
          c.bump('homework');
          _stub();
        }),
        parentChildAttendanceProvider.overrideWith((ref) async {
          c.bump('attendance');
          _stub();
        }),
        parentChildGradesProvider.overrideWith((ref, _) async {
          c.bump('grades');
          _stub();
        }),
        parentChildFeesProvider.overrideWith((ref) async {
          c.bump('fees');
          _stub();
        }),
        parentChildTimetableProvider.overrideWith((ref, _) async {
          c.bump('timetable');
          _stub();
        }),
      ],
      listen: (container) => [
        container.listen(parentDashboardSummaryProvider(_date), (_, __) {}),
        container.listen(parentBroadcastsProvider, (_, __) {}),
        container.listen(parentChildTestsProvider, (_, __) {}),
        container.listen(parentHomeworkProvider, (_, __) {}),
        container.listen(parentChildAttendanceProvider, (_, __) {}),
        container.listen(parentChildGradesProvider(null), (_, __) {}),
        container.listen(parentChildFeesProvider, (_, __) {}),
        container.listen(parentChildTimetableProvider(_date), (_, __) {}),
      ],
    );

    const expected = <String, Set<String>>{
      'message_broadcast': {'broadcasts'},
      'new_test_available': {'tests'},
      'test_status_changed': {'tests'},
      'test_completed': {'tests'},
      'homework_added': {'homework'},
      'homework_completion_updated': {'homework'},
      'attendance_updated': {'attendance'},
      'grade_added': {'grades'},
      'child_grade_added': {'grades'},
      'child_grade_deleted': {'grades'},
      'fee_payment_recorded': {'fees'},
      'timetable_updated': {'timetable'},
      'timetable_config_updated': {'timetable'},
    };

    for (final entry in expected.entries) {
      await _expectRefresh(tester, rig,
          event: entry.key, tracked: tracked, expected: entry.value);
    }
  });

  // ── Role isolation ───────────────────────────────────────────────────────────

  testWidgets('a student session does not run the teacher branch',
      (tester) async {
    final c = _Counters();
    final rig = await _pumpRole(
      tester,
      role: 'student',
      counters: c,
      overrides: [
        studentDashboardSummaryProvider.overrideWith((ref, _) async {
          c.bump('dashboard');
          _stub();
        }),
        teacherTestsProvider.overrideWith((ref, _) async {
          c.bump('teacherTests');
          _stub();
        }),
        presentationListProvider.overrideWith((ref) async {
          c.bump('presentation');
          _stub();
        }),
      ],
      listen: (container) => [
        container.listen(studentDashboardSummaryProvider(_date), (_, __) {}),
        container.listen(teacherTestsProvider((null, 20)), (_, __) {}),
        container.listen(presentationListProvider, (_, __) {}),
      ],
    );

    // Both are teacher-only events.
    await _expectRefresh(tester, rig,
        event: 'auto_quiz_status', tracked: {'teacherTests', 'presentation'},
        expected: {});
    await _expectRefresh(tester, rig,
        event: 'presentation_ready', tracked: {'teacherTests', 'presentation'},
        expected: {});
  });

  testWidgets('an unknown event still refreshes the dashboard but nothing else',
      (tester) async {
    final c = _Counters();
    final rig = await _pumpRole(
      tester,
      role: 'student',
      counters: c,
      overrides: [
        studentDashboardSummaryProvider.overrideWith((ref, _) async {
          c.bump('dashboard');
          _stub();
        }),
        studentBroadcastsProvider.overrideWith((ref) async {
          c.bump('broadcasts');
          _stub();
        }),
      ],
      listen: (container) => [
        container.listen(studentDashboardSummaryProvider(_date), (_, __) {}),
        container.listen(studentBroadcastsProvider, (_, __) {}),
      ],
    );

    // The top-level dashboard invalidate runs before the switch, so an
    // unrecognised event still refreshes the dashboard and falls through
    // without touching anything else.
    await _expectRefresh(tester, rig,
        event: 'something_new_the_backend_added',
        tracked: {'broadcasts'},
        expected: {});
  });
}
