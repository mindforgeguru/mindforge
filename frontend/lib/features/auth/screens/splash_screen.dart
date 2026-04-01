import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final AnimationController _wordCtrl;
  late final AnimationController _tagCtrl;
  late final AnimationController _expCtrl;
  late final AnimationController _exitCtrl;

  // ── Animations ──────────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _wordOpacity;
  late final Animation<Offset> _wordSlide;
  late final Animation<double> _tagOpacity;
  late final Animation<double> _expOpacity;
  late final Animation<Offset> _expSlide;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _wordCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _tagCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _expCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));

    _logoScale = Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl, curve: const Interval(0.0, 0.45)));

    _wordOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _wordCtrl, curve: Curves.easeOut));
    _wordSlide =
        Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _wordCtrl, curve: Curves.easeOutCubic));

    _tagOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _tagCtrl, curve: Curves.easeOut));

    _expOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _expCtrl, curve: Curves.easeOut));
    _expSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _expCtrl, curve: Curves.easeOutCubic));

    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Stagger in
    await Future.delayed(const Duration(milliseconds: 150));
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 450));
    _wordCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 350));
    _tagCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 350));
    _expCtrl.forward();

    // Hold for a moment, then fade out
    await Future.delayed(const Duration(milliseconds: 1400));
    await _exitCtrl.forward();

    if (mounted) context.go(RouteNames.login);
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _wordCtrl.dispose();
    _tagCtrl.dispose();
    _expCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Responsive values — CSS vw/vh equivalents
    final c1 = R.vw(context, 56);   // large top-left circle  (~220px @ 390)
    final c2 = R.vw(context, 38);   // top-right circle       (~150px @ 390)
    final c3 = R.vw(context, 23);   // bottom-left circle     (~90px @ 390)
    final c4 = R.vw(context, 51);   // large bottom-right     (~200px @ 390)
    final logoSz = R.fluid(context, 100, min: 72, max: 120);
    final titleFs = R.fluid(context, 26, min: 20, max: 32);
    final tagFs = R.fluid(context, 11, min: 9, max: 14);
    final badgeFs = R.fluid(context, 11, min: 9, max: 13);
    final badgeSubFs = R.fluid(context, 10, min: 8, max: 12);

    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (context, child) =>
          Opacity(opacity: _exitOpacity.value, child: child),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Stack(
          children: [
            // ── Decorative circles — sized as % of viewport width (vw) ──
            Positioned(
              top: -c1 * 0.27,
              left: -c1 * 0.27,
              child: _Circle(size: c1, opacity: 0.05),
            ),
            Positioned(
              top: R.vh(context, 10),
              right: -c2 * 0.27,
              child: _Circle(size: c2, opacity: 0.04),
            ),
            Positioned(
              bottom: R.vh(context, 13),
              left: R.vw(context, 8),
              child: _Circle(size: c3, opacity: 0.04),
            ),
            Positioned(
              bottom: -c4 * 0.25,
              right: -c4 * 0.15,
              child: _Circle(size: c4, opacity: 0.05),
            ),

            // ── Centered content ────────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo ──────────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _logoCtrl,
                    builder: (_, child) => Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    ),
                    child: Container(
                      width: logoSz,
                      height: logoSz,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(logoSz * 0.15),
                      ),
                      padding: EdgeInsets.all(logoSz * 0.08),
                      child: Image.asset('assets/images/logo.png',
                          fit: BoxFit.contain),
                    ),
                  ),

                  SizedBox(height: R.sp(context, 24)),

                  // ── MIND FORGE wordmark ───────────────────────────────
                  AnimatedBuilder(
                    animation: _wordCtrl,
                    builder: (_, child) => SlideTransition(
                      position: _wordSlide,
                      child:
                          Opacity(opacity: _wordOpacity.value, child: child),
                    ),
                    child: Text(
                      'MIND FORGE',
                      style: GoogleFonts.poppins(
                        fontSize: titleFs,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnDark,
                        letterSpacing: 5,
                      ),
                    ),
                  ),

                  SizedBox(height: R.sp(context, 7)),

                  // ── Tagline ───────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _tagCtrl,
                    builder: (_, child) =>
                        Opacity(opacity: _tagOpacity.value, child: child),
                    child: Text(
                      'AI ASSISTED LEARNING',
                      style: GoogleFonts.poppins(
                        fontSize: tagFs,
                        color: AppColors.textOnDark.withValues(alpha: 0.65),
                        letterSpacing: 3,
                      ),
                    ),
                  ),

                  SizedBox(height: R.sp(context, 32)),

                  // ── 30 Years badge ────────────────────────────────────
                  AnimatedBuilder(
                    animation: _expCtrl,
                    builder: (_, child) => SlideTransition(
                      position: _expSlide,
                      child:
                          Opacity(opacity: _expOpacity.value, child: child),
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: R.sp(context, 20),
                        vertical: R.sp(context, 10),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1),
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: R.fluid(context, 18, min: 14, max: 22),
                            color: Colors.white.withOpacity(0.85),
                          ),
                          SizedBox(width: R.sp(context, 10)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '25+ YEARS OF EXCELLENCE',
                                style: GoogleFonts.poppins(
                                  fontSize: badgeFs,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textOnDark,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              SizedBox(height: R.sp(context, 2)),
                              Text(
                                'Trusted education since 1997',
                                style: TextStyle(
                                  fontSize: badgeSubFs,
                                  color: Colors.white.withOpacity(0.6),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

class _Circle extends StatelessWidget {
  final double size;
  final double opacity;
  const _Circle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      );
}
