import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// MindForge logo — combines the brand image with MIND FORGE wordmark.
/// [size] controls the overall scale; [dark] flips to light colors for
/// use on dark backgrounds.
class MindForgeLogo extends StatelessWidget {
  final double size;
  final bool dark; // true = cream text on dark bg, false = plum text on light bg
  final bool showTagline;

  const MindForgeLogo({
    super.key,
    this.size = 1.0,
    this.dark = false,
    this.showTagline = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = dark ? AppColors.textOnDark : AppColors.textPrimary;
    final taglineColor =
        dark ? AppColors.textOnDark.withValues(alpha: 0.65) : AppColors.textSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo image
        Container(
          width: 80 * size,
          height: 80 * size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12 * size),
          ),
          padding: EdgeInsets.all(6 * size),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: 10 * size),

        // MIND FORGE wordmark
        Text(
          'MIND FORGE',
          style: GoogleFonts.poppins(
            fontSize: 22 * size,
            fontWeight: FontWeight.w800,
            color: textColor,
            letterSpacing: 1.2 * size,
          ),
        ),

        if (showTagline) ...[
          SizedBox(height: 4 * size),
          Text(
            'AI Assisted Learning',
            style: GoogleFonts.poppins(
              fontSize: 10 * size,
              fontWeight: FontWeight.w400,
              color: taglineColor,
              letterSpacing: 0.4 * size,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact inline logo for AppBar titles — stacked MIND / FORGE wordmark.
class MindForgeAppBarTitle extends StatelessWidget {
  const MindForgeAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(3),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MIND',
              style: GoogleFonts.specialElite(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnDark,
                letterSpacing: 2,
                height: 1.1,
              ),
            ),
            Text(
              'FORGE',
              style: GoogleFonts.specialElite(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textOnDark,
                letterSpacing: 2,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fixed bottom footer with logo + brand name.
/// Use as [Scaffold.bottomNavigationBar].
class MindForgeFooter extends StatelessWidget {
  const MindForgeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(36),
        topRight: Radius.circular(36),
      ),
      child: Container(
        height: 75 + bottom,
        decoration: const BoxDecoration(
          color: AppColors.background,
        ),
        child: Stack(
          children: [
            // Decorative circles matching header
            Positioned(
              top: -20,
              left: -20,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.22),
                ),
              ),
            ),
            Positioned(
              top: -15,
              right: 60,
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.22),
                ),
              ),
            ),
            Positioned(
              bottom: -10,
              right: -10,
              child: Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.22),
                ),
              ),
            ),
            // Content
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: 10, bottom: bottom),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'MIND FORGE',
                          style: GoogleFonts.specialElite(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            letterSpacing: 3.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          size: 13,
                          color: AppColors.primary.withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '30+ YEARS OF EXCELLENCE',
                          style: GoogleFonts.specialElite(
                            fontSize: 12,
                            color: AppColors.primary.withValues(alpha: 0.7),
                            letterSpacing: 2,
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
    );
  }
}
