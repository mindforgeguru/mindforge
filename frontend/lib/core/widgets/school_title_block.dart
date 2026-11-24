import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The school name and "AI Assisted Learning" tagline in the navy dashboard
/// header (teacher, student and parent).
///
/// The header has a fixed height. A name that wraps to two lines used to push
/// the tagline down into the overlapping avatar ("Sunrise Public School" on a
/// phone). When the name won't fit on one line it is set a little smaller on
/// two lines and the tagline is dropped, so the block keeps its height.
class SchoolTitleBlock extends StatelessWidget {
  final String name;
  final double titleFs;
  final double taglineFs;
  final double gap;

  const SchoolTitleBlock({
    super.key,
    required this.name,
    required this.titleFs,
    required this.taglineFs,
    required this.gap,
  });

  TextStyle _nameStyle(double size) => GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: 1.2,
        height: 1,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: _nameStyle(titleFs)),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final wraps = painter.didExceedMaxLines;
      painter.dispose();

      if (wraps) {
        return Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _nameStyle(titleFs * 0.82),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, maxLines: 1, style: _nameStyle(titleFs)),
          SizedBox(height: gap),
          Text(
            'AI Assisted Learning',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: taglineFs,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.72),
              letterSpacing: 0.4,
            ),
          ),
        ],
      );
    });
  }
}
