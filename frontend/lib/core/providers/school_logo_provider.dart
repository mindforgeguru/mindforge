import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';

/// The signed-in user's school from the public school list (null for the
/// owner or before sign-in). No dedicated read endpoint needed.
final currentSchoolProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.token == null || auth.schoolId == null) return null;
  final api = ref.watch(apiClientProvider);
  final schools = await api.getSchools();
  for (final s in schools) {
    if (s['id'] == auth.schoolId) return s;
  }
  return null;
});

/// The logged-in user's school logo URL (null when none uploaded). Shared by
/// every role's side nav so the school logo appears app-wide above the
/// MindForge logo.
final currentSchoolLogoProvider = FutureProvider<String?>((ref) async {
  final school = await ref.watch(currentSchoolProvider.future);
  final url = school?['logo_url'] as String?;
  return (url != null && url.isNotEmpty) ? url : null;
});
