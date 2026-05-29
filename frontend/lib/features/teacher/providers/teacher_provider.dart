import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/test.dart';
import '../../../core/models/timetable.dart';
import '../../../core/models/user.dart';

// ── Attendance ─────────────────────────────────────────────────────────────
// Using a Dart record (int grade, String date) instead of Map so that
// FutureProvider.family gets structural equality — maps use identity equality
// and would cause a new fetch on every rebuild.

/// Returns distinct dates (YYYY-MM-DD strings) that have attendance for (grade, month).
/// month = "YYYY-MM"
final teacherAttendanceDatesProvider =
    FutureProvider.family<List<String>, (int, String)>(
        (ref, params) async {
  final api = ref.watch(apiClientProvider);
  return api.getTeacherAttendanceDates(params.$1, params.$2);
});

final teacherAttendanceProvider =
    FutureProvider.family<List<AttendanceModel>, (int, String)>(
        (ref, params) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherAttendance(params.$1, date: params.$2);
  return raw
      .map((e) => AttendanceModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final studentsInGradeProvider =
    FutureProvider.family<List<UserModel>, int>((ref, grade) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getStudentsInGrade(grade);
  final list = raw
      .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
      .toList();
  list.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
  return list;
});

// ── Timetable ──────────────────────────────────────────────────────────────

final teacherTimetableProvider =
    FutureProvider.family<List<TimetableSlotModel>, (int, String)>(
        (ref, params) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherTimetable(params.$1, date: params.$2);
  return raw
      .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final teachersListProvider =
    FutureProvider<List<UserModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeachers();
  return raw
      .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final teacherTimetableConfigProvider =
    FutureProvider<TimetableConfigModel?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherTimetableConfig();
  if (raw == null) return null;
  return TimetableConfigModel.fromJson(raw);
});

final myTimetableProvider =
    FutureProvider<List<TimetableSlotModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getMyTimetable();
  return raw
      .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Grades ─────────────────────────────────────────────────────────────────
// Using (String? subject, int? studentId) record for structural equality.

final teacherGradesProvider =
    FutureProvider.family<List<GradeModel>, (String?, int?)>(
        (ref, params) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherGrades(
    subject: params.$1,
    studentId: params.$2,
  );
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Tests ──────────────────────────────────────────────────────────────────

// Key: (grade, limit) — increase limit to trigger "Load More"
final teacherTestsProvider =
    FutureProvider.family<List<TestModel>, (int?, int)>((ref, params) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherTests(grade: params.$1, limit: params.$2);
  return raw
      .map((e) => TestModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final testSubmissionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>(
        (ref, testId) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTestSubmissions(testId);
  return raw.cast<Map<String, dynamic>>();
});

final testGradesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>(
        (ref, testId) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTestGrades(testId);
  return raw.cast<Map<String, dynamic>>();
});

// ── Selected grade state ───────────────────────────────────────────────────

final selectedGradeProvider = StateProvider<int>((ref) => 8);

// ── Homework ───────────────────────────────────────────────────────────────

final teacherHomeworkProvider =
    FutureProvider.family<List<HomeworkModel>, int?>(
        (ref, grade) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherHomework(grade: grade);
  return raw
      .map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Roster + per-student completion status for a single homework, plus the
/// attendance metadata the teacher screen uses to gate Submit and lock
/// absent rows.
final teacherHomeworkCompletionsProvider =
    FutureProvider.family<HomeworkCompletionsResponse, int>(
        (ref, homeworkId) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.listHomeworkCompletions(homeworkId);
  return HomeworkCompletionsResponse.fromJson(raw);
});

// ── Broadcasts ─────────────────────────────────────────────────────────────

final teacherBroadcastsProvider =
    FutureProvider<List<BroadcastModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTeacherBroadcasts();
  return raw
      .map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Dashboard Summary ──────────────────────────────────────────────────────

/// Brief retry loop that waits for the in-memory JWT cache to be primed
/// before letting a provider fire its API call. After login, the token is
/// set synchronously before the route transitions, so this exits on the
/// first iteration. The exception is the moment right after startup, when
/// Riverpod can warm a dashboard provider during the auth-restore window —
/// without this guard the first request goes out without a token and
/// returns 401.
Future<void> _waitForAuthToken(ApiClient api) async {
  for (int i = 0; i < 40 && api.cachedToken == null; i++) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

final teacherDashboardSummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  await _waitForAuthToken(api);
  // Use a Dart-level timeout because Dio's connectTimeout / receiveTimeout
  // are not reliably enforced on Flutter web (XMLHttpRequest backing).
  // 45 s is generous enough for a Railway cold start (~30 s) while still
  // surfacing a "Try Again" error rather than loading forever.
  return api.getTeacherDashboardSummary()
      .timeout(const Duration(seconds: 45));
});

// Per-grade daily workflow snapshot used by the dashboard's workflow card.
final teacherTodayWorkflowProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  await _waitForAuthToken(api);
  return api.getTeacherTodayWorkflow();
});
