import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin facade over FirebaseCrashlytics so callers don't import it directly.
/// Keeps the "no-op in debug" + "swallow plugin errors" rules in one place.
///
/// Crashlytics has no Flutter web plugin, so on web every call becomes a
/// no-op and the FirebaseCrashlytics plugin is never touched.
class CrashReporter {
  static FirebaseCrashlytics? get _c => kIsWeb ? null : FirebaseCrashlytics.instance;

  /// Call once after Firebase.initializeApp. Debug builds send nothing.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _c?.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (_) {}
  }

  static Future<void> setUser({required int userId, required String role}) async {
    try {
      await _c?.setUserIdentifier(userId.toString());
      await _c?.setCustomKey('role', role);
    } catch (_) {}
  }

  static Future<void> clearUser() async {
    try {
      await _c?.setUserIdentifier('');
    } catch (_) {}
  }

  /// Breadcrumb — visible in the report's "Logs" tab.
  static void log(String message) {
    try {
      _c?.log(message);
    } catch (_) {}
  }

  static Future<void> recordFlutterError(FlutterErrorDetails details) async {
    FlutterError.presentError(details);
    try {
      await _c?.recordFlutterError(details);
    } catch (_) {}
  }

  static Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false}) async {
    try {
      await _c?.recordError(error, stack, fatal: fatal);
    } catch (_) {}
  }
}
