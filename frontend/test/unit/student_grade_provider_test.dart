import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/features/student/providers/student_provider.dart';

class MockApiClient extends Mock implements ApiClient {
  @override
  void Function()? onUnauthorized;
}

// The "Grade 8" chip on the student dashboard and profile. It used to be read
// off the student's most recent attendance record, so a student nobody had
// marked yet — every new student, and everyone at the start of a year — had
// no grade on screen at all.
void main() {
  late MockApiClient api;
  late ProviderContainer container;

  setUp(() {
    api = MockApiClient();
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
  });

  test('a student with no attendance yet still has a grade', () async {
    when(() => api.getStudentProfile())
        .thenAnswer((_) async => {'grade': 8, 'parent_username': 'dad'});
    when(() => api.getStudentAttendance(
          skip: any(named: 'skip'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => []);

    expect(await container.read(studentGradeProvider.future), 8);
  });

  test('the grade comes from the profile, not from an old attendance record',
      () async {
    when(() => api.getStudentProfile())
        .thenAnswer((_) async => {'grade': 9, 'parent_username': 'dad'});
    when(() => api.getStudentAttendance(
          skip: any(named: 'skip'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [
          {
            'id': 1,
            'student_id': 5,
            'grade': 8,
            'date': '2026-03-02',
            'period': 1,
            'status': 'present',
          },
        ]);

    expect(await container.read(studentGradeProvider.future), 9);
  });

  test('no grade in the profile means no chip, not a crash', () async {
    when(() => api.getStudentProfile())
        .thenAnswer((_) async => {'grade': null, 'parent_username': null});

    expect(await container.read(studentGradeProvider.future), isNull);
  });
}
