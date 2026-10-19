import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/fees.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/test.dart';
import '../../../core/models/timetable.dart';

// ── Which child ────────────────────────────────────────────────────────────
//
// A parent can have more than one child in the school. Every child provider
// below watches the selection and passes it on as `child_id`; null means "the
// first child", which is also what the server does without one.

/// The parent's linked children, oldest account first.
final parentChildrenProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getParentChildren();
  return raw.cast<Map<String, dynamic>>();
});

/// The child the parent screens are showing; null = the first.
final selectedChildIdProvider = StateProvider<int?>((ref) => null);

final parentChildAttendanceProvider =
    FutureProvider<List<AttendanceModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildAttendance(limit: 200, childId: childId);
  return raw
      .map((e) => AttendanceModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentFacultyProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getParentFaculty();
  return raw.cast<Map<String, dynamic>>();
});

final parentChildPresentationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildPresentations(childId: childId);
  return raw.cast<Map<String, dynamic>>();
});

final parentChildAttendanceSummaryProvider =
    FutureProvider<AttendanceSummaryModel>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildAttendanceSummary(childId: childId);
  return AttendanceSummaryModel.fromJson(raw);
});

final parentChildTimetableProvider =
    FutureProvider.family<List<TimetableSlotModel>, String>(
        (ref, date) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildTimetable(date: date, childId: childId);
  return raw
      .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildGrades(subject: subject, childId: childId);
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildOnlineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildGrades(subject: subject, gradeType: 'online', childId: childId);
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildOfflineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildGrades(subject: subject, gradeType: 'offline', childId: childId);
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildTestsProvider =
    FutureProvider<List<TestModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildTests(childId: childId);
  return raw.map((e) => TestModel.fromJson(e as Map<String, dynamic>)).toList();
});

final parentChildFeesProvider =
    FutureProvider.autoDispose<StudentFeeSummaryModel>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildFees(childId: childId);
  return StudentFeeSummaryModel.fromJson(raw);
});

// ── Homework ───────────────────────────────────────────────────────────────

final parentHomeworkProvider =
    FutureProvider<List<HomeworkModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildHomework(childId: childId);
  return raw
      .map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Map of homework_id → completed for the linked child. Mirror of
/// studentHomeworkCompletionsProvider so the parent UI can render the
/// same Complete / Incomplete / Pending badge.
final parentChildHomeworkCompletionsProvider =
    FutureProvider<Map<int, StudentHomeworkCompletion>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getChildHomeworkCompletions(childId: childId);
  return {
    for (final e in raw)
      (e['homework_id'] as int):
          StudentHomeworkCompletion.fromJson(e as Map<String, dynamic>),
  };
});

// ── Broadcasts ─────────────────────────────────────────────────────────────

final parentBroadcastsProvider =
    FutureProvider<List<BroadcastModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  final raw = await api.getParentBroadcasts(childId: childId);
  return raw
      .map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Dashboard Summary ──────────────────────────────────────────────────────

final parentDashboardSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, date) async {
  final api = ref.watch(apiClientProvider);
  final childId = ref.watch(selectedChildIdProvider);
  // Dart-level timeout prevents infinite hangs when Dio's receiveTimeout
  // is not reliably enforced (e.g. Railway cold starts, cellular reconnect).
  return api.getParentDashboardSummary(date: date, childId: childId)
      .timeout(const Duration(seconds: 45));
});
