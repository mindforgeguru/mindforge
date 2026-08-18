import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots, screen recording and the recents-switcher thumbnail
/// while a sensitive screen is open.
///
/// Backed by Android's `FLAG_SECURE` (see MainActivity.kt). That is a **window**
/// flag — one switch for the whole app — so this cannot be scoped to a widget by
/// the platform. Instead it is reference-counted here: the flag goes on when the
/// first sensitive screen mounts and off only when the last one leaves. A plain
/// boolean breaks as soon as one secured screen opens another, because popping
/// the inner screen would unsecure the outer one while it is still visible.
///
/// Applied to fees and grades only. Securing the whole app would also stop a
/// parent screenshotting a timetable to send to their partner — ordinary use of
/// a school app, and not a threat worth breaking.
///
/// No-ops anywhere the channel isn't implemented (web, and iOS for now), so a
/// screen using it renders normally rather than throwing on the way in.
class ScreenSecurity {
  ScreenSecurity._();

  static const MethodChannel _channel =
      MethodChannel('com.mindforge.mindforge/screen_security');

  static int _depth = 0;

  /// Secure the window. Balance every call with [release].
  static Future<void> acquire() async {
    _depth += 1;
    if (_depth == 1) {
      await _setSecure(true);
    }
  }

  /// Drop this screen's claim; clears the flag when it was the last one.
  static Future<void> release() async {
    if (_depth == 0) {
      // Nothing to release. Guarded rather than allowed to go negative: a
      // negative count would make the *next* acquire fail to reach 1, and the
      // screen after that would render unprotected.
      return;
    }
    _depth -= 1;
    if (_depth == 0) {
      await _setSecure(false);
    }
  }

  static Future<void> _setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      // Expected on web and iOS — no handler is registered there.
    } catch (e) {
      // Never let a hardening measure take down the screen it protects.
      debugPrint('ScreenSecurity.setSecure($enabled) failed: $e');
    }
  }

  @visibleForTesting
  static void debugReset() => _depth = 0;
}

/// Mixin for a screen whose contents should not be capturable.
///
/// ```dart
/// class _FeesScreenState extends ConsumerState<FeesScreen>
///     with SecureScreenMixin { ... }
/// ```
///
/// Ties the flag to the widget's own lifecycle, so an unusual exit — a pop, a
/// tab switch, a deep-link replacing the route — still releases it.
mixin SecureScreenMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenSecurity.acquire();
  }

  @override
  void dispose() {
    ScreenSecurity.release();
    super.dispose();
  }
}

/// Wrapper for screens that are `StatelessWidget` / `ConsumerWidget`.
///
/// ```dart
/// Widget build(BuildContext context, WidgetRef ref) =>
///     SecureScreen(child: Scaffold(...));
/// ```
///
/// Same reference-counted flag as [SecureScreenMixin], reached without
/// converting a stateless screen to stateful purely to hold a lifecycle hook.
/// It renders its child unchanged, so it adds no layout of its own.
class SecureScreen extends StatefulWidget {
  final Widget child;
  const SecureScreen({super.key, required this.child});

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> with SecureScreenMixin {
  @override
  Widget build(BuildContext context) => widget.child;
}
