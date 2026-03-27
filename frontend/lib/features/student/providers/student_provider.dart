import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/test.dart';
import '../../../core/models/timetable.dart';

final studentAttendanceProvider =
    FutureProvider.autoDispose<List<AttendanceModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentAttendance();
  return raw
      .map((e) => AttendanceModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final studentAttendanceSummaryProvider =
    FutureProvider.autoDispose<AttendanceSummaryModel>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentAttendanceSummary();
  return AttendanceSummaryModel.fromJson(raw);
});

final studentTimetableProvider =
    FutureProvider.autoDispose.family<List<TimetableSlotModel>, String>(
        (ref, date) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentTimetable(date: date);
  return raw
      .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Fetches the student's profile (grade + parent_username) from the backend.
final studentProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.getStudentProfile();
});

/// Derives the student's grade number from attendance records.
final studentGradeProvider = FutureProvider.autoDispose<int?>((ref) async {
  final attendance = await ref.watch(studentAttendanceProvider.future);
  if (attendance.isNotEmpty) return attendance.first.grade;
  return null;
});

final studentGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentGrades(subject: subject);
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final studentOnlineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentGrades(subject: subject, gradeType: 'online');
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final studentOfflineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw =
      await api.getStudentGrades(subject: subject, gradeType: 'offline');
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final pendingTestsProvider =
    FutureProvider.autoDispose<List<TestModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getPendingTests();
  return raw.map((e) => TestModel.fromJson(e as Map<String, dynamic>)).toList();
});

final offlineTestsProvider =
    FutureProvider.autoDispose<List<TestModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentOfflineTests();
  return raw.map((e) => TestModel.fromJson(e as Map<String, dynamic>)).toList();
});

final completedTestsProvider =
    FutureProvider.autoDispose<List<TestModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentCompletedTests();
  return raw.map((e) => TestModel.fromJson(e as Map<String, dynamic>)).toList();
});

final testReviewProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>(
        (ref, testId) async {
  final api = ref.watch(apiClientProvider);
  return api.getTestReview(testId);
});

// ── Homework ───────────────────────────────────────────────────────────────

final studentHomeworkProvider =
    FutureProvider.autoDispose<List<HomeworkModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentHomework();
  return raw
      .map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Broadcasts ─────────────────────────────────────────────────────────────

final studentBroadcastsProvider =
    FutureProvider.autoDispose<List<BroadcastModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentBroadcasts();
  return raw
      .map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
