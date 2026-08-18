import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/websocket_client.dart';
import '../providers/session_reset.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/parent/providers/parent_provider.dart';
import '../../features/student/providers/student_provider.dart';
import '../../features/student/providers/xp_provider.dart';
import '../../features/teacher/providers/presentation_provider.dart';
import '../../features/teacher/providers/teacher_provider.dart';

/// Applies backend WebSocket events to Riverpod caches for the whole app.
///
/// Mounted once above the router, so it keeps working no matter which screen
/// the user is on. Previously only the three dashboards subscribed, so an
/// event that arrived while the user sat on Broadcasts, Tests or Homework
/// refreshed the dashboard behind them and nothing else. Screens themselves
/// stay dumb: they `watch` their provider and re-render when this
/// invalidates it.
///
/// It deliberately does *not* own any UI. Event-driven dialogs (profile
/// changed, level up) stay on the dashboards, which have a Scaffold to show
/// them in.
///
/// The socket is subscribed directly rather than through a `StreamProvider`:
/// `ref.listen` on an `AsyncValue` skips emissions equal to the previous one,
/// which would silently swallow a repeated event (the same homework marked
/// complete twice, two identical broadcasts) — exactly the events this needs
/// to act on.
class RealtimeSync extends ConsumerStatefulWidget {
  final Widget child;
  const RealtimeSync({super.key, required this.child});

  @override
  ConsumerState<RealtimeSync> createState() => _RealtimeSyncState();
}

class _RealtimeSyncState extends ConsumerState<RealtimeSync>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _sub;
  int? _connectedUserId;
  /// Last identity seen, kept across logout so an account switch is detectable.
  int? _sessionUserId;
  String? _connectedToken;
  DateTime? _lastPausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncConnection());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  /// Opens (or re-opens) the subscription for whoever is currently logged in.
  /// A no-op when nothing changed, so it's safe to call on every rebuild.
  void _syncConnection() {
    final auth = ref.read(authProvider);
    final userId = auth.userId;
    final token = auth.token;

    // The signed-in identity changed — log out, a 401 wipe, or a straight
    // switch to another account. Drop everything the outgoing session cached:
    // the root ProviderScope lives as long as the app does (on web logging out
    // does not reload the page), and most data providers are not autoDispose,
    // so otherwise the next user to sign in here reads the previous user's
    // timetable, homework, grades and fees straight out of memory.
    //
    // Only an identity change counts. A JWT rotation keeps the same userId and
    // must not wipe the caches.
    if (_sessionUserId != null && userId != _sessionUserId) {
      // Deferred a frame so the router has swapped away from the outgoing
      // screens first. Invalidating while they're still mounted would have
      // them refetch with a cleared token and surface 401s on the way out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) resetSessionCaches(ref.invalidate);
      });
    } else if (_sessionUserId == null && userId != null) {
      // Signing in from a fully signed-out state — the only screen mounted
      // right now is the public login screen, so there's no stale-token 401
      // risk in resetting immediately. This case used to be skipped on the
      // assumption that the sign-out which preceded it already reset things,
      // but that reset is itself deferred by a frame (see above): a login
      // that completes before that frame renders — normal for an automated
      // flow, and possible for a human on a fast reconnect — would have the
      // about-to-mount dashboard read the outgoing session's still-cached
      // values. Resetting synchronously here, before any screen for this new
      // identity has had a chance to watch these providers, closes that race.
      resetSessionCaches(ref.invalidate);
    }
    _sessionUserId = userId;

    if (userId == null || token == null) {
      _sub?.cancel();
      _sub = null;
      _connectedUserId = null;
      _connectedToken = null;
      return;
    }
    if (_sub != null && userId == _connectedUserId && token == _connectedToken) {
      return;
    }

    _sub?.cancel();
    _connectedUserId = userId;
    _connectedToken = token;
    // `WebSocketClient.connect` hands back the same broadcast stream for an
    // unchanged user + token, so the dashboards' own subscriptions (which
    // exist only to show dialogs) share this one connection.
    _sub = ref.read(webSocketClientProvider).connect(userId, token).listen(
      (event) {
        if (!mounted) return;
        final type = event['event'] as String?;
        if (type != null) _apply(type);
      },
    );
  }

  /// Android Doze / iOS suspension can kill the socket without firing onDone,
  /// leaving a live-looking channel that silently drops events. After a real
  /// backgrounding, force a fresh socket and refetch the screen data.
  ///
  /// The dashboards do the same for their own summary provider; this covers
  /// the case where the app was backgrounded on any other screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    final pausedFor = _lastPausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_lastPausedAt!);
    if (pausedFor < const Duration(seconds: 30)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(webSocketClientProvider).forceReconnect();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Follow login, logout and JWT rotation.
    ref.listen<AuthState>(authProvider, (_, __) => _syncConnection());
    return widget.child;
  }

  void _apply(String type) {
    switch (ref.read(authProvider).role) {
      case 'student':
        _applyStudent(type);
        break;
      case 'teacher':
      case 'admin':
        _applyTeacher(type);
        break;
      case 'parent':
        _applyParent(type);
        break;
    }
  }

  // ── Per-role fan-out ──────────────────────────────────────────────────────
  // Each case lists every cache the event can change, not just the one the
  // screen that triggered it happens to show — the whole point is that the
  // user may be looking at any screen when the event lands.

  void _applyStudent(String type) {
    ref.invalidate(studentDashboardSummaryProvider);

    switch (type) {
      case 'message_broadcast':
        ref.invalidate(studentBroadcastsProvider);
        break;
      case 'new_test_available':
      case 'test_status_changed':
      case 'test_completed':
        ref.invalidate(pendingTestsProvider);
        ref.invalidate(offlineTestsProvider);
        ref.invalidate(completedTestsProvider);
        break;
      case 'level_up':
      case 'test_submitted':
        ref.invalidate(studentXpProvider);
        break;
      case 'homework_added':
      case 'homework_completion_updated':
        ref.invalidate(studentHomeworkProvider);
        ref.invalidate(studentHomeworkCompletionsProvider);
        ref.invalidate(studentXpProvider);
        break;
      case 'attendance_updated':
        ref.invalidate(studentAttendanceProvider);
        ref.invalidate(studentAttendanceSummaryProvider);
        ref.invalidate(studentXpProvider);
        break;
      case 'grade_added':
      case 'grade_deleted':
        ref.invalidate(studentGradesProvider);
        ref.invalidate(studentOnlineGradesProvider);
        ref.invalidate(studentOfflineGradesProvider);
        ref.invalidate(studentXpProvider);
        break;
      case 'fee_payment_recorded':
        ref.invalidate(studentFeesProvider);
        break;
      case 'timetable_updated':
      case 'timetable_config_updated':
        ref.invalidate(studentTimetableProvider);
        break;
    }
  }

  void _applyTeacher(String type) {
    ref.invalidate(teacherDashboardSummaryProvider);

    switch (type) {
      case 'message_broadcast':
        ref.invalidate(teacherBroadcastsProvider);
        break;
      // `auto_quiz_status` fires when a presentation period log spawns an
      // auto-quiz — once when the placeholder row is created and again when
      // generation finishes or fails.
      case 'auto_quiz_status':
      case 'new_test_available':
      case 'test_status_changed':
      case 'test_completed':
      case 'test_submitted':
        ref.invalidate(teacherTestsProvider);
        break;
      case 'homework_added':
      case 'homework_completion_updated':
        ref.invalidate(teacherHomeworkProvider);
        ref.invalidate(teacherHomeworkCompletionsProvider);
        ref.invalidate(teacherTodayWorkflowProvider);
        break;
      case 'attendance_updated':
        ref.invalidate(teacherAttendanceProvider);
        ref.invalidate(teacherAttendanceDatesProvider);
        ref.invalidate(teacherTodayWorkflowProvider);
        break;
      case 'grade_added':
      case 'grade_deleted':
        ref.invalidate(teacherGradesProvider);
        break;
      case 'presentation_ready':
        ref.invalidate(presentationListProvider);
        ref.invalidate(presentationDetailProvider);
        ref.invalidate(presentationLibraryProvider);
        break;
      case 'timetable_updated':
      case 'timetable_config_updated':
        ref.invalidate(teacherTimetableProvider);
        ref.invalidate(myTimetableProvider);
        ref.invalidate(teacherTimetableConfigProvider);
        ref.invalidate(teacherTodayWorkflowProvider);
        break;
    }
  }

  void _applyParent(String type) {
    ref.invalidate(parentDashboardSummaryProvider);

    switch (type) {
      case 'message_broadcast':
        ref.invalidate(parentBroadcastsProvider);
        break;
      case 'new_test_available':
      case 'test_status_changed':
      case 'test_completed':
        ref.invalidate(parentChildTestsProvider);
        break;
      case 'homework_added':
      case 'homework_completion_updated':
        ref.invalidate(parentHomeworkProvider);
        ref.invalidate(parentChildHomeworkCompletionsProvider);
        break;
      case 'attendance_updated':
        ref.invalidate(parentChildAttendanceProvider);
        ref.invalidate(parentChildAttendanceSummaryProvider);
        break;
      case 'grade_added':
      case 'child_grade_added':
      case 'child_grade_deleted':
        ref.invalidate(parentChildGradesProvider);
        ref.invalidate(parentChildOnlineGradesProvider);
        ref.invalidate(parentChildOfflineGradesProvider);
        break;
      case 'fee_payment_recorded':
        ref.invalidate(parentChildFeesProvider);
        break;
      case 'timetable_updated':
      case 'timetable_config_updated':
        ref.invalidate(parentChildTimetableProvider);
        break;
    }
  }
}
