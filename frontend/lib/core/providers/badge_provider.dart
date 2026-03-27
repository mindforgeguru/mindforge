import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ─────────────────────────────────────────────────────────────────────
const _kStudentBroadcast = 'badge_student_broadcast';
const _kTeacherBroadcast = 'badge_teacher_broadcast';
const _kParentBroadcast  = 'badge_parent_broadcast';
const _kStudentTest      = 'badge_student_test';
const _kParentTest       = 'badge_parent_test';
const _kStudentGrade     = 'badge_student_grade';
const _kTeacherGrade     = 'badge_teacher_grade';

// ─── SharedPreferences provider ───────────────────────────────────────────────
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

// ─── Generic badge notifier ───────────────────────────────────────────────────
// state = last time the user "saw" this category.
// null means never seen → always show badge if data exists.

class BadgeNotifier extends StateNotifier<DateTime?> {
  final SharedPreferences _prefs;
  final String _key;

  BadgeNotifier(this._prefs, this._key)
      : super(_load(_prefs, _key));

  static DateTime? _load(SharedPreferences p, String k) {
    final s = p.getString(k);
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// Call when the user opens the relevant screen.
  void markSeen() {
    final now = DateTime.now();
    state = now;
    _prefs.setString(_key, now.toIso8601String());
  }
}

// ─── Notifier providers ───────────────────────────────────────────────────────

final studentBroadcastBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kStudentBroadcast);
});

final teacherBroadcastBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kTeacherBroadcast);
});

final parentBroadcastBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kParentBroadcast);
});

final studentTestBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kStudentTest);
});

final parentTestBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kParentTest);
});

final studentGradeBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kStudentGrade);
});

final teacherGradeBadgeNotifier =
    StateNotifierProvider<BadgeNotifier, DateTime?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BadgeNotifier(prefs, _kTeacherGrade);
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Returns true if [latest] is after [lastSeen] (or lastSeen is null).
bool _isNew(DateTime? lastSeen, DateTime? latest) {
  if (latest == null) return false;
  if (lastSeen == null) return true;
  return latest.isAfter(lastSeen);
}
