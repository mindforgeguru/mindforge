import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Festive holiday banner shown in a dashboard timetable box (or workflow card)
/// when today is marked as a holiday. Shared across the student, parent and
/// teacher dashboards so the look stays consistent.
class HolidayBanner extends StatelessWidget {
  /// Optional holiday reason shown as the subtitle. When empty, a friendly
  /// default ("enjoy the day off") is used.
  final String reason;

  /// Outer margin. Defaults to the full-width timetable-box spacing; callers
  /// that embed it inside an already-padded card pass a tighter margin.
  final EdgeInsetsGeometry? margin;

  const HolidayBanner({super.key, this.reason = '', this.margin});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      final hPad = (sw * 0.04).clamp(12.0, 20.0);
      final emojiSize = (sw * 0.085).clamp(30.0, 40.0);
      final titleSize = (sw * 0.05).clamp(16.0, 22.0);
      final subSize = (sw * 0.032).clamp(11.0, 14.0);
      final hasReason = reason.trim().isNotEmpty;

      return Container(
        margin: margin ?? EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
        padding: EdgeInsets.symmetric(
          horizontal: (sw * 0.05).clamp(16.0, 24.0),
          vertical: (sw * 0.055).clamp(18.0, 26.0),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Faint oversized emoji watermark in the corner for a playful feel.
            Positioned(
              right: -6,
              top: -10,
              child: Opacity(
                opacity: 0.18,
                child: Text('☀️', style: TextStyle(fontSize: emojiSize * 1.8)),
              ),
            ),
            Row(
              children: [
                Container(
                  width: emojiSize * 1.7,
                  height: emojiSize * 1.7,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Text('🏖️', style: TextStyle(fontSize: emojiSize)),
                ),
                SizedBox(width: (sw * 0.04).clamp(12.0, 18.0)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Holiday! 🎉',
                        style: GoogleFonts.poppins(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasReason
                            ? reason.trim()
                            : 'No classes today — enjoy the day off!',
                        style: GoogleFonts.poppins(
                          fontSize: subSize,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
