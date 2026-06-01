import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/xp_provider.dart';

/// Celebratory dialog shown when the WebSocket pushes a `level_up` event.
///
/// Use [show] (don't construct directly) — it wires up confetti lifecycle
/// and returns a future that resolves when the user dismisses.
class LevelUpDialog extends ConsumerStatefulWidget {
  final int newLevel;
  final String newTitle;
  final int totalXp;

  const LevelUpDialog({
    super.key,
    required this.newLevel,
    required this.newTitle,
    required this.totalXp,
  });

  /// Show the dialog above the current navigator (use the root navigator
  /// so the celebration is not clipped by an inner Navigator).
  static Future<void> show(
    BuildContext context, {
    required int newLevel,
    required String newTitle,
    required int totalXp,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => LevelUpDialog(
        newLevel: newLevel,
        newTitle: newTitle,
        totalXp: totalXp,
      ),
    );
  }

  @override
  ConsumerState<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends ConsumerState<LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confetti.play();
      _scale.forward();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _scale, curve: Curves.elasticOut);
    final palette = ref.watch(currentPaletteProvider);

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Confetti rains down from the top center, tinted to the active theme.
        ConfettiWidget(
          confettiController: _confetti,
          blastDirection: math.pi / 2, // straight down
          maxBlastForce: 25,
          minBlastForce: 8,
          emissionFrequency: 0.05,
          numberOfParticles: 24,
          gravity: 0.25,
          shouldLoop: false,
          colors: [
            palette.accent,
            palette.accentLight,
            palette.secondary,
            palette.secondaryLight,
            Colors.amber,
            Colors.white,
          ],
        ),
        Center(
          child: ScaleTransition(
            scale: scale,
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [palette.accent, palette.accentLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${widget.newLevel}',
                          style: GoogleFonts.poppins(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LEVEL UP!',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: palette.accent,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.newTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.totalXp} XP total',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Awesome!',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
