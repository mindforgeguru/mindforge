import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Logo: scale + fade in
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  // Capsule: slide up + fade in (delayed)
  late AnimationController _capsuleCtrl;
  late Animation<double> _capsuleSlide;
  late Animation<double> _capsuleOpacity;

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

    // ── Capsule slides up (700ms, starts after logo finishes)
    _capsuleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _capsuleSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
        CurvedAnimation(parent: _capsuleCtrl, curve: Curves.easeOut));
    _capsuleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _capsuleCtrl, curve: Curves.easeIn));

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
    // 2. Short pause
    await Future.delayed(const Duration(milliseconds: 300));
    // 3. Capsule slides up
    await _capsuleCtrl.forward();
    // 4. Hold for a moment
    await Future.delayed(const Duration(milliseconds: 1800));
    // 5. Fade everything out
    await _exitCtrl.forward();
    // 6. Navigate
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      context.go(RouteNames.login);
    }
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _capsuleCtrl.dispose();
    _exitCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final logoSize = (sw * 0.38).clamp(120.0, 180.0);

    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (_, child) =>
          Opacity(opacity: _exitOpacity.value, child: child),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Hansal logo: fades in with logo ───────────────────
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, child) => Opacity(
                  opacity: _logoOpacity.value,
                  child: child,
                ),
                child: Image.asset(
                  'assets/images/hansal_logo.png',
                  width: logoSize * 0.8,
                  height: logoSize * 0.8,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 10),

              // ── Capsule: slide up + fade in ───────────────────────
              AnimatedBuilder(
                animation: _capsuleCtrl,
                builder: (_, child) => Opacity(
                  opacity: _capsuleOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, _capsuleSlide.value),
                    child: child,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: const Color(0xFF606060).withOpacity(0.3),
                        width: 1),
                    color: const Color(0xFFB8B8B8).withOpacity(0.25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          size: 17,
                          color: const Color(0xFF404040).withOpacity(0.8)),
                      const SizedBox(width: 9),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '25+ YEARS OF EXCELLENCE',
                            style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF303030),
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Trusted education since 1997',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              color: const Color(0xFF505050),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

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
    );
  }
}
