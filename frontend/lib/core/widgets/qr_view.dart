import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Draws a QR code from a string.
///
/// Uses the pure-Dart `qr` encoder plus a painter rather than a QR *widget*
/// package. That is a deliberate trade: this app holds children's records and
/// the dependency surface was deliberately narrowed, so ~40 lines of painting
/// beats pulling in a widget library for one screen.
///
/// Only used for the two-factor enrolment code, which is short enough that the
/// encoder never needs a high version.
class QrView extends StatelessWidget {
  final String data;
  final double size;

  const QrView({super.key, required this.data, this.size = 200});

  @override
  Widget build(BuildContext context) {
    // `errorCorrectLevel.M` is the level authenticator apps expect, and
    // typeNumber auto-sizes to the payload — an otpauth:// URI with a 32-char
    // secret sits comfortably inside it.
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(code);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _QrPainter(qrImage),
        // A QR is meaningless to a screen reader, so describe what it is for
        // rather than leaving an unlabelled graphic.
        child: Semantics(
          label: 'QR code for setting up two-factor authentication',
          image: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  const _QrPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final modules = image.moduleCount;
    // Painted on an explicit white ground, not the page background: scanners
    // need the light/dark contrast, and a dark app theme would otherwise put
    // dark modules on a dark field and make the code unreadable.
    final ground = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, ground);

    final cell = size.width / modules;
    final dark = Paint()..color = Colors.black;
    for (var x = 0; x < modules; x++) {
      for (var y = 0; y < modules; y++) {
        if (image.isDark(y, x)) {
          // +0.5 on the extent closes the hairline gaps that rounding leaves
          // between cells, which some scanners read as broken modules.
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.image != image;
}
