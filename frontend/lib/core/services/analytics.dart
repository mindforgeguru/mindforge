import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin facade over FirebaseAnalytics. Mirrors CrashReporter: collection
/// disabled in debug, all plugin calls swallow errors so telemetry can never
/// crash the app.
class Analytics {
  static FirebaseAnalytics get _a => FirebaseAnalytics.instance;

  /// Single observer instance — pass to GoRouter so every navigation emits a
  /// `screen_view` event automatically.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);

  static Future<void> init() async {
    try {
      await _a.setAnalyticsCollectionEnabled(!kDebugMode);
    } catch (_) {}
  }

  static Future<void> setUser({required int userId, required String role}) async {
    try {
      await _a.setUserId(id: userId.toString());
      await _a.setUserProperty(name: 'role', value: role);
    } catch (_) {}
  }

  static Future<void> clearUser() async {
    try {
      await _a.setUserId(id: null);
      await _a.setUserProperty(name: 'role', value: null);
    } catch (_) {}
  }

  static Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    try {
      await _a.logEvent(name: name, parameters: params);
    } catch (_) {}
  }
}
