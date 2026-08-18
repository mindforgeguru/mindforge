import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/providers/session_reset.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';

class MockApiClient extends Mock implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

Map<String, dynamic> _hw(int id, String title) => {
      'id': id,
      'teacher_id': 2,
      'grade': 10,
      'subject': 'Mathematics',
      'title': title,
      'description': null,
      'homework_type': 'written',
      'test_id': null,
      'due_date': null,
      'created_at': '2026-08-18T11:01:54.858940Z',
      'review_complete': false,
    };

Map<String, dynamic> _bc(int id, String title) => {
      'id': id,
      'sender_id': 2,
      'sender_username': 'chinmay_sir',
      'title': title,
      'message': 'm',
      'target_type': 'all',
      'target_grade': null,
      'created_at': '2026-08-18T11:02:17.107353Z',
    };

void main() {
  // A single browser page load = a single root ProviderScope. Logging out and
  // back in as a different user does NOT tear that container down, so any
  // non-autoDispose FutureProvider keeps serving the previous session's data.
  //
  // Reproduces: teacher creates homework/broadcast, student logs in on the same
  // page load and sees nothing new.
  group('data providers across an account switch', () {
    late MockApiClient api;
    late ProviderContainer container;

    setUp(() {
      api = MockApiClient();
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
    });

    test('studentHomeworkProvider refetches after a session change', () async {
      // First session: nothing assigned yet.
      when(() => api.getStudentHomework()).thenAnswer((_) async => []);
      expect(await container.read(studentHomeworkProvider.future), isEmpty);

      // Teacher assigns homework, then the student session restarts.
      when(() => api.getStudentHomework())
          .thenAnswer((_) async => [_hw(51, 'test')]);
      resetSessionCaches(container.invalidate);

      final after = await container.read(studentHomeworkProvider.future);
      expect(after, hasLength(1),
          reason: 'stale homework served from the previous session');
      expect(after.single.title, 'test');
    });

    test('studentBroadcastsProvider refetches after a session change',
        () async {
      when(() => api.getStudentBroadcasts()).thenAnswer((_) async => []);
      expect(await container.read(studentBroadcastsProvider.future), isEmpty);

      when(() => api.getStudentBroadcasts())
          .thenAnswer((_) async => [_bc(33, 'testing')]);
      resetSessionCaches(container.invalidate);

      final after = await container.read(studentBroadcastsProvider.future);
      expect(after, hasLength(1),
          reason: 'stale broadcasts served from the previous session');
    });

    test('studentTimetableProvider refetches after a session change', () async {
      const date = '2026-08-18';
      when(() => api.getStudentTimetable(date: date))
          .thenAnswer((_) async => []);
      expect(
          await container.read(studentTimetableProvider(date).future), isEmpty);

      when(() => api.getStudentTimetable(date: date)).thenAnswer((_) async => [
            {
              'id': 89,
              'grade': 10,
              'slot_date': date,
              'period_number': 1,
              'subject': 'Mathematics',
              'teacher_id': 11,
              'teacher_username': 'hansal_sir',
              'start_time': '03:00',
              'end_time': '04:00',
              'is_holiday': false,
              'comment': 'THEORY',
            }
          ]);
      resetSessionCaches(container.invalidate);

      final after = await container.read(studentTimetableProvider(date).future);
      expect(after, hasLength(1),
          reason: 'stale timetable served from the previous session');
    });
  });
}
