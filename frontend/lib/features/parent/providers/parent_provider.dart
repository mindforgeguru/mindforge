import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/fees.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/test.dart';
import '../../../core/models/timetable.dart';

final parentChildAttendanceProvider =
    FutureProvider<List<AttendanceModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildAttendance(limit: 200);
  return raw
      .map((e) => AttendanceModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildAttendanceSummaryProvider =
    FutureProvider<AttendanceSummaryModel>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildAttendanceSummary();
  return AttendanceSummaryModel.fromJson(raw);
});

final parentChildTimetableProvider =
    FutureProvider.family<List<TimetableSlotModel>, String>(
        (ref, date) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildTimetable(date: date);
  return raw
      .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildGrades(subject: subject);
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildOnlineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildGrades(subject: subject, gradeType: 'online');
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildOfflineGradesProvider =
    FutureProvider.autoDispose.family<List<GradeModel>, String?>(
        (ref, subject) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildGrades(subject: subject, gradeType: 'offline');
  return raw
      .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentChildTestsProvider =
    FutureProvider<List<TestModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildTests();
  return raw.map((e) => TestModel.fromJson(e as Map<String, dynamic>)).toList();
});

final parentChildFeesProvider =
    FutureProvider.autoDispose<StudentFeeSummaryModel>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildFees();
  return StudentFeeSummaryModel.fromJson(raw);
});

// ── Homework ───────────────────────────────────────────────────────────────

final parentHomeworkProvider =
    FutureProvider<List<HomeworkModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getChildHomework();
  return raw
      .map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Broadcasts ─────────────────────────────────────────────────────────────

final parentBroadcastsProvider =
    FutureProvider<List<BroadcastModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getParentBroadcasts();
  return raw
      .map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Dashboard Summary ──────────────────────────────────────────────────────

final parentDashboardSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, date) async {
  final api = ref.watch(apiClientProvider);
  return api.getParentDashboardSummary(date: date);
});
