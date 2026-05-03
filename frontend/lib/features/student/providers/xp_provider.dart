import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/xp.dart';
import '../../../core/theme/brand_palette.dart';
import '../../auth/providers/auth_provider.dart';

/// Current student's XP snapshot. Refreshed by `ref.invalidate` from the
/// dashboard's WebSocket listener whenever a `level_up` or other XP-relevant
/// event arrives — there's no auto-poll.
final studentXpProvider = FutureProvider<StudentXPDetails>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getMyXp();
  return StudentXPDetails.fromJson(raw);
});

/// Leaderboard scoped to 'class' | 'grade' | 'school'. Family on scope so
/// the three tabs of the leaderboard screen each get their own cache entry.
final leaderboardProvider =
    FutureProvider.family<LeaderboardResponse, String>((ref, scope) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getLeaderboard(scope: scope, limit: 50);
  return LeaderboardResponse.fromJson(raw);
});

/// Cosmetic theme catalogue + lock state for the current student.
/// Refreshed manually by the picker after a select.
final themesProvider = FutureProvider<ThemeListResponse>((ref) async {
  final api = ref.watch(apiClientProvider);
  final raw = await api.getThemes();
  return ThemeListResponse.fromJson(raw);
});

/// Resolved palette for the active user.
///
/// - Students: derived from their `selectedTheme` on `studentXpProvider`.
/// - Teachers / parents / admins / not-logged-in: always the default
///   `mindForge` palette. We do not call `studentXpProvider` for these
///   roles because `/api/xp/me` is student-only (would 403).
final currentPaletteProvider = Provider<BrandPalette>((ref) {
  final role = ref.watch(authProvider).role;
  if (role != 'student') return BrandPalettes.mindForge;

  final xpAsync = ref.watch(studentXpProvider);
  final id = xpAsync.maybeWhen(
    data: (xp) => xp.selectedTheme,
    orElse: () => null,
  );
  return BrandPalettes.byId(id);
});
