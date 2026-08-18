import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'school_logo_provider.dart';
import '../../features/admin/providers/admin_provider.dart';
import '../../features/parent/providers/parent_provider.dart';
import '../../features/student/providers/student_provider.dart';
import '../../features/student/providers/xp_provider.dart';
import '../../features/teacher/providers/database_provider.dart';
import '../../features/teacher/providers/presentation_provider.dart';
import '../../features/teacher/providers/teacher_provider.dart';

/// Every provider holding data that belongs to *one* signed-in user.
///
/// The app runs a single root `ProviderScope` for its whole lifetime, and
/// logging out does not tear it down — on web there is no page reload at all.
/// Most of these are plain (non-`autoDispose`) providers, so without an
/// explicit reset their values outlive the session that fetched them and the
/// next user to sign in on the same device sees the previous user's timetable,
/// homework, grades and fees.
///
/// Deliberately excluded:
///  * `sharedPreferencesProvider` — infrastructure, not session data.
///  * `currentPaletteProvider` — pure derived state; recomputes on its own when
///    the providers it watches are invalidated.
final List<ProviderOrFamily> sessionScopedProviders = <ProviderOrFamily>[
  // ── Admin ──────────────────────────────────────────────────────────────
  adminTeachersProvider,
  pendingUsersProvider,
  allUsersProvider,
  feeStructuresProvider,
  paymentInfoProvider,
  feeSummariesProvider,
  timetableConfigProvider,
  academicYearsProvider,
  currentAcademicYearProvider,
  adminSetupStatusProvider,

  // ── Parent ─────────────────────────────────────────────────────────────
  parentChildAttendanceProvider,
  parentFacultyProvider,
  parentChildAttendanceSummaryProvider,
  parentChildTimetableProvider,
  parentChildGradesProvider,
  parentChildOnlineGradesProvider,
  parentChildOfflineGradesProvider,
  parentChildTestsProvider,
  parentChildFeesProvider,
  parentHomeworkProvider,
  parentChildHomeworkCompletionsProvider,
  parentBroadcastsProvider,
  parentDashboardSummaryProvider,

  // ── Student ────────────────────────────────────────────────────────────
  studentAttendanceProvider,
  studentAttendanceSummaryProvider,
  facultyProvider,
  classAttendanceLeaderboardProvider,
  studentTimetableProvider,
  studentProfileProvider,
  studentGradeProvider,
  studentGradesProvider,
  studentOnlineGradesProvider,
  studentOfflineGradesProvider,
  pendingTestsProvider,
  offlineTestsProvider,
  completedTestsProvider,
  testReviewProvider,
  studentHomeworkProvider,
  studentHomeworkCompletionsProvider,
  studentFeesProvider,
  studentBroadcastsProvider,
  studentDashboardSummaryProvider,

  // ── Student XP / gamification ──────────────────────────────────────────
  studentXpProvider,
  leaderboardProvider,
  themesProvider,

  // ── Teacher ────────────────────────────────────────────────────────────
  teacherAttendanceDatesProvider,
  teacherAttendanceProvider,
  studentsInGradeProvider,
  teacherTimetableProvider,
  teachersListProvider,
  teacherTimetableConfigProvider,
  myTimetableProvider,
  teacherGradesProvider,
  teacherTestsProvider,
  testSubmissionsProvider,
  testGradesProvider,
  selectedGradeProvider,
  teacherHomeworkProvider,
  teacherHomeworkCompletionsProvider,
  teacherBroadcastsProvider,
  teacherDashboardSummaryProvider,
  teacherTodayWorkflowProvider,

  // ── Teacher database / presentations ───────────────────────────────────
  oldTestPapersProvider,
  chapterDocumentsProvider,
  chapterNamesProvider,
  syllabusProvider,
  presentationListProvider,
  presentationDetailProvider,
  availableChaptersProvider,
  presentationLibraryProvider,

  // ── Cross-role ─────────────────────────────────────────────────────────
  currentSchoolLogoProvider,
];

/// Drops every cached value that belonged to the outgoing session.
///
/// Pass `container.invalidate` or `ref.invalidate`. Call this whenever the
/// signed-in identity changes — including on logout, so nothing sits in memory
/// waiting for the next user.
void resetSessionCaches(void Function(ProviderOrFamily) invalidate) {
  for (final provider in sessionScopedProviders) {
    invalidate(provider);
  }
}
