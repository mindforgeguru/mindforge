import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:mindforge/core/models/xp.dart';
import 'package:mindforge/core/models/homework.dart';
import 'package:mindforge/core/providers/badge_provider.dart';
import 'package:mindforge/core/providers/school_logo_provider.dart';
import 'package:mindforge/core/theme/app_theme.dart';
import 'package:mindforge/features/auth/providers/auth_provider.dart';
import 'package:mindforge/features/parent/providers/parent_provider.dart';
import 'package:mindforge/features/parent/screens/dashboard_screen.dart';
import 'package:mindforge/features/parent/screens/homework_screen.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';
import 'package:mindforge/features/student/providers/xp_provider.dart';
import 'package:mindforge/features/student/screens/dashboard_screen.dart';
import 'package:mindforge/features/student/screens/broadcasts_screen.dart';
import 'package:mindforge/features/student/screens/homework_screen.dart';
import 'package:mindforge/features/teacher/providers/teacher_provider.dart';
import 'package:mindforge/features/teacher/screens/broadcast_screen.dart';
import 'package:mindforge/features/teacher/screens/homework_screen.dart';

// The API now accepts up to its column limits — a 300-character homework title,
// a 2,000-character notice, a 100-character subject — and teachers paste URLs
// and long unbroken words. This renders the student and parent screens that show
// them, at phone widths, with content at those limits. An overflow is a reported
// FlutterError in a widget test, so any regression fails here.

final _word = 'Supercalifragilisticexpialidocious' * 8; // 272, no spaces
final _url = 'https://example.com/${'a' * 270}';
const _subject =
    'Mathematics and Applied Statistics for Competitive Examinations with Extra Practice';

final _homeworkJson = <Map<String, dynamic>>[
  {
    'id': 1, 'teacher_id': 2, 'grade': 8, 'subject': _subject,
    'title': _word, 'description': _url, 'homework_type': 'written',
    'test_id': null, 'due_date': '2026-10-20', 'created_at': '2026-10-17T05:00:00Z',
  },
  {
    'id': 2, 'teacher_id': 2, 'grade': 8, 'subject': 'maths',
    'title': ('Read chapter seven carefully and answer every question in full ' * 5)
        .substring(0, 300),
    'description': 'x ' * 999, 'homework_type': 'written',
    'test_id': null, 'due_date': null, 'created_at': '2026-10-17T05:00:00Z',
  },
];
final _homework = _homeworkJson.map(HomeworkModel.fromJson).toList();

final _broadcastJson = <Map<String, dynamic>>[
  {
    'id': 1, 'sender_id': 2, 'sender_username': 'teacher_with_a_rather_long_username_x',
    'title': _word.substring(0, 200), 'message': ('$_url ' * 6).trim(),
    'target_type': 'grade', 'target_grade': 8, 'created_at': '2026-10-17T05:00:00Z',
  },
];
final _broadcasts = _broadcastJson.map(BroadcastModel.fromJson).toList();

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

class _FakeWebSocketClient extends WebSocketClient {
  @override
  Stream<Map<String, dynamic>> connect(int userId, String token) => const Stream.empty();
  @override
  void forceReconnect() {}
  @override
  void disconnect() {}
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.api, super.ws, super.storage, String role) {
    state = AuthState(token: 'test-token', role: role, userId: 7,
        username: 'a_rather_long_username_for_a_$role');
  }
}

Map<String, dynamic> _summary() => {
      'timetable': _slots, 'child_timetable': _slots,
      'homework': [for (final h in _homeworkJson) h],
      'broadcasts': [for (final b in _broadcastJson) b],
      'grades': _grades, 'child_grades': _grades,
    };

final _slots = [
  for (final p in [1, 2, 3])
    {'id': p, 'grade': 8, 'slot_date': '2026-10-17', 'period_number': p,
     'subject': _subject, 'teacher_id': 2,
     'teacher_username': 'teacher_with_a_rather_long_username_x',
     'start_time': '09:00:00', 'end_time': '09:45:00', 'is_holiday': false,
     'comment': _word},
];

final _grades = [
  for (final i in [1, 2, 3, 4, 5, 6])
    {'id': i, 'student_id': 7, 'teacher_id': 2, 'subject': _subject,
     'chapter': _word.substring(0, 200), 'test_id': null, 'marks_obtained': 7.0,
     'max_marks': 10.0, 'percentage': 70.0, 'grade_type': 'manual',
     'created_at': '2026-10-17T05:00:00Z'},
];

Future<void> _pump(WidgetTester tester, Size size, String path, Widget screen,
    {String role = 'student'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(initialLocation: path, routes: [
    GoRoute(path: path, builder: (_, __) => screen),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_FakeApiClient()),
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentSchoolLogoProvider.overrideWith((ref) async => null),
      studentHomeworkProvider.overrideWith((ref) async => _homework),
      pendingTestsProvider.overrideWith((ref) async => []),
      offlineTestsProvider.overrideWith((ref) async => []),
      studentHomeworkCompletionsProvider.overrideWith((ref) async => {}),
      studentBroadcastsProvider.overrideWith((ref) async => _broadcasts),
      parentHomeworkProvider.overrideWith((ref) async => _homework),
      parentChildHomeworkCompletionsProvider.overrideWith((ref) async => {}),
      parentBroadcastsProvider.overrideWith((ref) async => _broadcasts),
      parentChildrenProvider.overrideWith((ref) async => []),
      teacherHomeworkProvider.overrideWith((ref, grade) async => _homework),
      teacherBroadcastsProvider.overrideWith((ref) async => _broadcasts),
      webSocketClientProvider.overrideWithValue(_FakeWebSocketClient()),
      authProvider.overrideWith((ref) => _TestAuthNotifier(ref.read(apiClientProvider),
          ref.read(webSocketClientProvider), const FlutterSecureStorage(), role)),
      parentDashboardSummaryProvider.overrideWith((ref, date) async => _summary()),
      parentChildAttendanceProvider.overrideWith((ref) async => []),
      studentDashboardSummaryProvider.overrideWith((ref, date) async => _summary()),
      studentAttendanceProvider.overrideWith((ref) async => []),
      studentGradeProvider.overrideWith((ref) async => 8),
      studentXpProvider.overrideWith((ref) async => StudentXPDetails.fromJson({
            'student_id': 7, 'total_xp': 300, 'current_level': 2,
            'current_level_title': 'Novice II', 'xp_into_level': 17,
            'xp_for_next_level': 237, 'next_level': 3, 'next_level_title': 'Novice III',
            'next_level_xp_required': 520, 'selected_theme': null,
            'recent_transactions': [],
          })),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _scrollAll(WidgetTester tester) async {
  final lists = find.byType(Scrollable);
  if (lists.evaluate().isEmpty) return;
  for (var i = 0; i < 6; i++) {
    await tester.drag(lists.last, const Offset(0, -400), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final size in const [Size(390, 844), Size(360, 740), Size(320, 640)]) {
    final w = size.width.toInt();

    testWidgets('student homework copes with long content at $w px', (tester) async {
      await _pump(tester, size, '/student/homework', const StudentHomeworkScreen());
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('student notices cope with long content at $w px', (tester) async {
      await _pump(tester, size, '/student/broadcasts', const StudentBroadcastsScreen());
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('student dashboard copes with long content at $w px', (tester) async {
      await _pump(tester, size, '/student', const StudentDashboardScreen());
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('parent dashboard copes with long content at $w px', (tester) async {
      await _pump(tester, size, '/parent', const ParentDashboardScreen(), role: 'parent');
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('teacher homework copes with long content at $w px', (tester) async {
      await _pump(tester, size, '/teacher/homework', const TeacherHomeworkScreen(),
          role: 'teacher');
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('teacher announcements cope with long content at $w px', (tester) async {
      await _pump(tester, size, '/teacher/broadcast', const TeacherBroadcastScreen(),
          role: 'teacher');
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('parent homework and notices cope with long content at $w px',
        (tester) async {
      await _pump(tester, size, '/parent/homework', const ParentHomeworkScreen());
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Announcements'));
      await tester.pumpAndSettle();
      await _scrollAll(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
