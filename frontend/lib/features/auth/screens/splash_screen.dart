import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/school_logo_provider.dart';
import '../../../core/utils/constants.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Logo: scale + fade in
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  // Exit: fade out everything
  late AnimationController _exitCtrl;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ── Logo animates in (900ms)
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn));

    // ── Exit fade out (400ms)
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Logo fades + scales in
    await _logoCtrl.forward();
    // 2. Hold for a moment
    await Future.delayed(const Duration(milliseconds: 1800));
    // 3. Fade everything out
    await _exitCtrl.forward();
    // 4. Navigate
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      context.go(RouteNames.login);
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _exitCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final logoSize = (sw * 0.25).clamp(80.0, 120.0);
    final schoolLogo = ref.watch(currentSchoolLogoProvider).valueOrNull;

    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (_, child) =>
          Opacity(opacity: _exitOpacity.value, child: child),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // White splash: dark status-bar icons (the app default is white).
        value: SystemUiOverlayStyle.dark
            .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── School logo, when a signed-in school is remembered.
              //    It used to be Hansel & Gretel's logo and "25+ years ·
              //    since 1997" for every school. ───────────────────────
              if (schoolLogo != null) ...[
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, child) => Opacity(
                    opacity: _logoOpacity.value,
                    child: child,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: schoolLogo,
                    width: logoSize * 0.8,
                    height: logoSize * 0.8,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── MindForge Logo: scale + fade in ───────────────────
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, child) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: child,
                  ),
                ),
                child: Image.asset(
                  'assets/images/splash_logo.png',
                  width: logoSize,
                  height: logoSize,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
