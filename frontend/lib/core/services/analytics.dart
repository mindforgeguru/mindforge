import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Thin facade over FirebaseAnalytics. Mirrors CrashReporter: collection
/// disabled in debug, all plugin calls swallow errors so telemetry can never
/// crash the app.
///
/// Firebase is not configured for the web build (firebase_options.dart
/// throws on `kIsWeb`), so on web every call is a no-op. Accessing
/// `FirebaseAnalytics.instance` from a static initialiser would throw at
/// class-load time before main() can guard with its try/catch, so we
/// build the observer lazily and substitute a no-op on web.
class Analytics {
  /// Touch the underlying plugin lazily and only off the web build.
  static FirebaseAnalytics? get _a => kIsWeb ? null : FirebaseAnalytics.instance;

  static NavigatorObserver? _observer;

  /// Single observer instance — pass to GoRouter so every navigation emits a
  /// `screen_view` event automatically. Returns a plain [NavigatorObserver]
  /// (no-op) on web so router setup doesn't trigger Firebase JS interop.
  static NavigatorObserver get observer {
    if (_observer != null) return _observer!;
    if (kIsWeb) {
      _observer = NavigatorObserver();
    } else {
      _observer = FirebaseAnalyticsObserver(
        analytics: FirebaseAnalytics.instance,
      );
    }
    return _observer!;
  }

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _a?.setAnalyticsCollectionEnabled(!kDebugMode);
    } catch (_) {}
  }

  static Future<void> setUser({required int userId, required String role}) async {
    try {
      await _a?.setUserId(id: userId.toString());
      await _a?.setUserProperty(name: 'role', value: role);
    } catch (_) {}
  }

  static Future<void> clearUser() async {
    try {
      await _a?.setUserId(id: null);
      await _a?.setUserProperty(name: 'role', value: null);
    } catch (_) {}
  }

  static Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    try {
      await _a?.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  static Future<void> logScreenView(String screenName) async {
    try {
      await _a?.logScreenView(screenName: screenName);
    } catch (_) {}
  }
}
