import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/fees.dart';
import '../../../core/models/timetable.dart';
import '../../../core/models/user.dart';
import '../../auth/providers/auth_provider.dart';

final pendingUsersProvider =
    FutureProvider<List<UserModel>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final api = ref.watch(apiClientProvider);
  final raw = await api.getPendingUsers();
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
  return api.getCurrentAcademicYear();
});
