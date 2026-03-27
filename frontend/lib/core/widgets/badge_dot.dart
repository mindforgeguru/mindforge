import 'package:flutter/material.dart';

/// Small red circle overlaid on top-right of a nav icon when there is
/// something new to see.
class BadgeDot extends StatelessWidget {
  final Widget child;
  final bool show;

  const BadgeDot({super.key, required this.child, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    final sw = MediaQuery.of(context).size.width;
    final dotSz = (sw * 0.028).clamp(9.0, 13.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -3,
          right: -3,
          child: Container(
            width: dotSz,
            height: dotSz,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
