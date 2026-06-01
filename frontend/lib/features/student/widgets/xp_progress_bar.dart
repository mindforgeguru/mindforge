import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_palette.dart';
import '../providers/xp_provider.dart';

/// Horizontal progress bar showing the current level number, the title for
/// the level, the XP earned within the level, and the XP needed for the
/// next one. Bar fill animates whenever [progress] changes.
///
/// Pass [progress] in [0..1]. At level cap (no next level), set [atCap]
/// true and the bar shows fully filled with a "MAX" badge.
///
/// Tinted by the student's selected theme via `currentPaletteProvider` —
/// callers can override with [paletteOverride] (used by the theme picker
/// to show a non-selected theme's preview).
class XPProgressBar extends ConsumerWidget {
  final int currentLevel;
  final String currentLevelTitle;
  final int xpIntoLevel;
  final int? xpForNextLevel;     // null when at cap
  final double progress;          // 0..1
  final bool compact;             // tighter version for the dashboard card
  final BrandPalette? paletteOverride;

  const XPProgressBar({
    super.key,
    required this.currentLevel,
    required this.currentLevelTitle,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.progress,
    this.compact = false,
    this.paletteOverride,
  });

  bool get atCap => xpForNextLevel == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BrandPalette palette =
        paletteOverride ?? ref.watch(currentPaletteProvider);
    final pad = compact ? 12.0 : 16.0;
    final barHeight = compact ? 10.0 : 14.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LevelBadge(level: currentLevel, compact: compact, palette: palette),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentLevelTitle,
                      style: GoogleFonts.poppins(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                      ),
                    ),
                    if (!compact) const SizedBox(height: 2),
                    Text(
                      atCap
                          ? 'Level cap reached'
                          : '$xpIntoLevel / ${xpForNextLevel!} XP to next level',
                      style: GoogleFonts.poppins(
                        fontSize: compact ? 11 : 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (atCap) _maxBadge(palette),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(barHeight / 2),
            child: SizedBox(
              height: barHeight,
              child: Stack(
                children: [
                  // Track
                  Container(color: AppColors.divider.withValues(alpha: 0.5)),
                  // Fill — animates between progress values
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [palette.accent, palette.accentLight],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maxBadge(BrandPalette palette) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'MAX',
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: palette.accentDark,
            letterSpacing: 1,
          ),
        ),
      );
}

class _LevelBadge extends StatelessWidget {
  final int level;
  final bool compact;
  final BrandPalette palette;
  const _LevelBadge({
    required this.level,
    required this.compact,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [palette.primary, palette.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          '$level',
          style: GoogleFonts.poppins(
            fontSize: compact ? 14 : 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
