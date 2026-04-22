import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level handler required by FCM for background/terminated messages.
/// Must be a top-level function (not a class method) annotated with this pragma.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages from FCM data-only payloads are handled here.
  // No UI operations — just store if needed. For now we do nothing because
  // the notification will be shown by the system automatically when the app
  // is in the background (FCM handles that natively for notification payloads).
}

class NotificationService {
  NotificationService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'mindforge_alerts';
  static const _channelName = 'Mindforge Alerts';

  // Routes emitted when a notification is tapped while app is running.
  static final _routeController = StreamController<String>.broadcast();
  static Stream<String> get routeStream => _routeController.stream;

  // Route from a notification that launched a killed app (consumed once).
  static String? _launchRoute;
  static String? consumeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> initialize() async {
    if (kIsWeb) return; // FCM on web uses a different path; skip for now.

    // Register the background handler.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Create the Android notification channel with high importance so
    // heads-up banners appear when the app is in the foreground.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialise flutter_local_notifications (used for foreground display).
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings =
        InitializationSettings(android: androidInit, iOS: darwinInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) {
          _routeController.add(route);
        }
      },
    );

    // Ask for permission (iOS / Android 13+).
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Show a local heads-up banner when a notification arrives in foreground.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      final android = message.notification?.android;
      if (notification != null && android != null) {
        final route = message.data['route'] as String?;
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: route,
        );
      }
    });

    // App was in background and user tapped the notification.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = message.data['route'] as String?;
      if (route != null && route.isNotEmpty) {
        _routeController.add(route);
      }
    });

    // App was terminated and notification tap launched it.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final route = initial.data['route'] as String?;
      if (route != null && route.isNotEmpty) {
        _launchRoute = route;
      }
    }
  }

  /// Returns the FCM registration token for this device.
  /// Returns null on web or if permission was denied.
  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    try {
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Subscribe to token refresh events and call [onToken] with the new token.
  static void onTokenRefresh(void Function(String token) onToken) {
    if (kIsWeb) return;
    _messaging.onTokenRefresh.listen(onToken);
  }
}
