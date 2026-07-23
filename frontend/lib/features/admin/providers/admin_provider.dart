import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/fees.dart';
import '../../../core/models/timetable.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/school_logo_provider.dart';
import '../../auth/providers/auth_provider.dart';

final adminTeachersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getAdminTeachers();
  return raw.cast<Map<String, dynamic>>();
});

final pendingUsersProvider =
    FutureProvider<List<UserModel>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getPendingUsers()
      .timeout(const Duration(seconds: 20));
  return raw
      .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// Parameter: (role, grade) — use Dart record for structural equality
final allUsersProvider =
    FutureProvider.family<List<UserModel>, (String?, int?)>(
        (ref, params) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getAllUsers(role: params.$1, grade: params.$2);
  return raw
      .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final feeStructuresProvider =
    FutureProvider.family<List<FeeStructureModel>, String?>(
        (ref, academicYear) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getFeeStructures(academicYear: academicYear);
  return raw
      .map((e) => FeeStructureModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final paymentInfoProvider =
    FutureProvider<List<PaymentInfoModel>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getPaymentInfo();
  return raw
      .map((e) => PaymentInfoModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final feeSummariesProvider =
    FutureProvider.family<List<dynamic>, String>(
        (ref, academicYear) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  return api.getFeeSummaries(academicYear);
});

final timetableConfigProvider =
    FutureProvider<TimetableConfigModel?>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;
  final api = ref.watch(apiClientProvider);
  final raw = await api.getTimetableConfig();
  if (raw == null) return null;
  return TimetableConfigModel.fromJson(raw);
});

final academicYearsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getAcademicYears();
  return raw.cast<Map<String, dynamic>>();
});

final currentAcademicYearProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;
  final api = ref.watch(apiClientProvider);
  return api.getCurrentAcademicYear()
      .timeout(const Duration(seconds: 20));
});

/// One-time school setup progress, derived from the existing providers. The
/// five bootstrapping tasks must be finished in order — academic year →
/// timetable → fees → bank/payment → logo — before the admin dashboard unlocks.
class AdminSetupStatus {
  final bool academicYearDone;
  final bool timetableDone;
  final bool feesDone;
  final bool paymentDone;
  final bool logoDone;

  const AdminSetupStatus({
    required this.academicYearDone,
    required this.timetableDone,
    required this.feesDone,
    required this.paymentDone,
    required this.logoDone,
  });

  /// Task completion flags in workflow order.
  List<bool> get steps =>
      [academicYearDone, timetableDone, feesDone, paymentDone, logoDone];

  /// Index (0–4) of the first incomplete task, or 5 when everything is done.
  int get currentStep {
    for (var i = 0; i < steps.length; i++) {
      if (!steps[i]) return i;
    }
    return steps.length;
  }

  bool get allComplete => currentStep == steps.length;
}

/// Combines the setup providers into a single status. Watching each `.future`
/// makes this re-derive whenever any of them is invalidated (e.g. after a task
/// is saved), so the road advances immediately.
final adminSetupStatusProvider = FutureProvider<AdminSetupStatus>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) {
    return const AdminSetupStatus(
      academicYearDone: false,
      timetableDone: false,
      feesDone: false,
      paymentDone: false,
      logoDone: false,
    );
  }

  // Passing null as the academic year returns every fee structure for the
  // school, so "any fee structure exists" is a year-independent check.
  final year = await ref.watch(currentAcademicYearProvider.future);
  final config = await ref.watch(timetableConfigProvider.future);
  final fees = await ref.watch(feeStructuresProvider(null).future);
  final payments = await ref.watch(paymentInfoProvider.future);
  final logoUrl = await ref.watch(currentSchoolLogoProvider.future);

  return AdminSetupStatus(
    academicYearDone: year != null,
    timetableDone: config != null,
    feesDone: fees.isNotEmpty,
    paymentDone: payments.isNotEmpty,
    logoDone: logoUrl != null,
  );
});
