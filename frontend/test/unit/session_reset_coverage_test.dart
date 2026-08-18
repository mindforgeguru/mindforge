import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Provider files whose contents are per-user session data.
const _providerFiles = <String>[
  'lib/features/admin/providers/admin_provider.dart',
  'lib/features/parent/providers/parent_provider.dart',
  'lib/features/student/providers/student_provider.dart',
  'lib/features/student/providers/xp_provider.dart',
  'lib/features/teacher/providers/database_provider.dart',
  'lib/features/teacher/providers/presentation_provider.dart',
  'lib/features/teacher/providers/teacher_provider.dart',
  'lib/core/providers/badge_provider.dart',
  'lib/core/providers/school_logo_provider.dart',
];

/// Providers that intentionally survive an account switch. Keep in sync with
/// the "Deliberately excluded" note in session_reset.dart.
const _exempt = <String>{
  // Infrastructure — the SharedPreferences instance itself, not session data.
  'sharedPreferencesProvider',
  // Pure derived state; recomputes when the providers it watches are reset.
  'currentPaletteProvider',
};

final _declaration = RegExp(r'^final ([a-zA-Z0-9_]+Provider)\b', multiLine: true);

void main() {
  // session_reset.dart lists providers by hand, so a provider added later can
  // quietly miss the reset and start leaking across accounts again. This walks
  // the source to make forgetting one a test failure rather than a bug report.
  test('every session-scoped provider is reset on an account switch', () {
    final resetSource =
        File('lib/core/providers/session_reset.dart').readAsStringSync();
    final listed = _declaration
        .allMatches(resetSource)
        .map((m) => m.group(1)!)
        .toSet();
    // The list itself is `final sessionScopedProviders` — not a provider.
    listed.remove('sessionScopedProviders');

    final missing = <String>[];
    for (final path in _providerFiles) {
      final source = File(path).readAsStringSync();
      for (final match in _declaration.allMatches(source)) {
        final name = match.group(1)!;
        if (_exempt.contains(name)) continue;
        if (!resetSource.contains(RegExp('\\b$name\\b'))) {
          missing.add('$name  ($path)');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'These providers cache per-user data but are not cleared when '
          'the signed-in user changes, so the next user to sign in on this '
          'device would read the previous user\'s data. Add them to '
          'sessionScopedProviders in lib/core/providers/session_reset.dart, '
          'or add them to _exempt here with a reason:\n'
          '  ${missing.join('\n  ')}',
    );
  });
}
