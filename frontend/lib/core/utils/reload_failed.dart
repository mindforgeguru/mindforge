import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Re-fetches only the providers whose last load failed.
///
/// Dashboard sections (XP, class progress, attendance, the school logo) hide
/// themselves when their request fails. Retry and pull-to-refresh used to
/// re-fetch only the summary, so after the server came back those sections
/// stayed missing until the app restarted. Providers that loaded fine are
/// left alone, so a refresh doesn't refetch everything.
void reloadFailed(
    WidgetRef ref, List<ProviderBase<AsyncValue<Object?>>> providers) {
  for (final p in providers) {
    if (ref.read(p).hasError) ref.invalidate(p);
  }
}
