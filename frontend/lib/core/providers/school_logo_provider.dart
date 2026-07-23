import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';

/// The logged-in user's school logo URL (null when none uploaded). Shared by
/// every role's side nav so the school logo appears app-wide above the
/// MindForge logo. Derived from the public school list — no dedicated read
/// endpoint needed.
final currentSchoolLogoProvider = FutureProvider<String?>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.token == null || auth.schoolId == null) return null;
  final api = ref.watch(apiClientProvider);
  final schools = await api.getSchools();
  for (final s in schools) {
    if (s['id'] == auth.schoolId) {
      final url = s['logo_url'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    }
  }
  return null;
});
