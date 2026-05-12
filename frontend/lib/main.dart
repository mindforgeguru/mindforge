import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/services/analytics.dart';
import 'core/services/crash_reporter.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/constants.dart';
import 'core/providers/badge_provider.dart';
import 'features/student/providers/xp_provider.dart';

/// Makes every scroll view respond to trackpad and mouse wheel gestures,
/// not just touch. Applied once at the app root.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}


void main() async {
  usePathUrlStrategy(); // Clean URLs on web (no #)
  WidgetsFlutterBinding.ensureInitialized();

  // Cap the image cache so it doesn't grow unbounded as users navigate
  // between screens with profile photos, attachments, etc.
  // 100 images / 80 MB is generous but prevents the OOM-then-freeze pattern.
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 * 1024 * 1024;

  // Firebase core init is awaited so the FCM token is available by the time
  // the user logs in. It's fast (~100 ms) and safe to await.
  // NotificationService.initialize() is fire-and-forget because requesting
  // notification permission can show a system dialog that hangs on iOS simulator.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await CrashReporter.init();
    await Analytics.init();
    // Kick off permission request + listener setup in the background.
    NotificationService.initialize().catchError((e) {
      debugPrint('NotificationService init error: $e');
    });
  } catch (e) {
    debugPrint('Firebase.initializeApp error: $e');
  }

  // Framework + async errors → Crashlytics. PlatformDispatcher.onError catches
  // uncaught async errors without needing runZonedGuarded.
  FlutterError.onError = CrashReporter.recordFlutterError;
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporter.recordError(error, stack, fatal: true);
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MindForgeApp(),
    ),
  );
}

class MindForgeApp extends ConsumerStatefulWidget {
  const MindForgeApp({super.key});

  @override
  ConsumerState<MindForgeApp> createState() => _MindForgeAppState();
}

class _MindForgeAppState extends ConsumerState<MindForgeApp> {
  @override
  void initState() {
    super.initState();

    // Listen for notification taps that happen while the app is running.
    NotificationService.routeStream.listen((route) {
      final router = ref.read(appRouterProvider);
      router.go(route);
    });

    // If the app was launched from a killed state by a notification tap,
    // navigate once the router is ready (after the first frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchRoute = NotificationService.consumeLaunchRoute();
      if (launchRoute != null) {
        final router = ref.read(appRouterProvider);
        router.go(launchRoute);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Sync the runtime palette into AppColors. When the student picks a
    // different theme this rebuild fires, AppColors getters return the new
    // values, AppTheme.lightTheme recomputes from those getters, and every
    // descendant rebuilds with the swapped colors.
    final palette = ref.watch(currentPaletteProvider);
    AppColors.applyPalette(palette);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      scrollBehavior: _AppScrollBehavior(),
      routerConfig: router,
      // Clamp OS text scale so accessibility settings don't break layouts.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.1,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
