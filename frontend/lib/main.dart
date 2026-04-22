import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/constants.dart';
import 'core/providers/badge_provider.dart';

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

  await Firebase.initializeApp();
  await NotificationService.initialize();

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
