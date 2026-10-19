import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// One box with one ring per chapter, used on the student and parent
/// dashboards so they can see which teacher is teaching which chapter and how
/// far along it is. Each row comes from the grade-scoped presentations endpoint
/// (`/student/presentations` or `/parent/child/presentations`) and carries
/// `chapter_name`, `teacher_username`, `current_slide_index`, `total_slides`.
class ChapterRingsBox extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String title;

  const ChapterRingsBox({
    super.key,
    required this.rows,
    this.title = 'Class progress',
  });

  // A stable palette so each chapter ring keeps its colour across rebuilds.
  static const List<Color> _palette = <Color>[
    Color(0xFF8B5CF6), // purple
    Color(0xFFF97316), // orange
    Color(0xFF14B8A6), // teal
    Color(0xFFEC4899), // pink
    Color(0xFF06B6D4), // cyan
    Color(0xFFEAB308), // yellow
    Color(0xFF22C55E), // green
    Color(0xFFEF4444), // red
  ];

  @override
  Widget build(BuildContext context) {
    // One ring per chapter. Sort by chapter name so the order is stable.
    final chapters = [...rows]..sort((a, b) =>
        (a['chapter_name']?.toString() ?? '')
            .compareTo(b['chapter_name']?.toString() ?? ''));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.slideshow_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No chapters in progress',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            )
          else
            Wrap(
              spacing: 18,
              runSpacing: 16,
              children: [
                for (var i = 0; i < chapters.length; i++)
                  _ChapterRing(
                    row: chapters[i],
                    color: _palette[i % _palette.length],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChapterRing extends StatelessWidget {
  final Map<String, dynamic> row;
  final Color color;
  const _ChapterRing({required this.row, required this.color});

  @override
  Widget build(BuildContext context) {
    final chapter = row['chapter_name']?.toString() ?? 'Chapter';
    final teacher = row['teacher_username']?.toString() ?? '';
    final total = (row['total_slides'] as num?)?.toInt() ?? 0;
    final done = (row['current_slide_index'] as num?)?.toInt() ?? 0;
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final pctLabel = '${(pct * 100).round()}%';

    return SizedBox(
      width: 92,
      child: Column(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: CustomPaint(
              painter: _RingPainter(progress: pct, color: color),
              child: Center(
                child: Text(
                  pctLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            chapter,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.15,
            ),
          ),
          if (teacher.isNotEmpty)
            Text(
              teacher,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
