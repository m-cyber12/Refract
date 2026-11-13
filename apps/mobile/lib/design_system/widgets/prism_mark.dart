import 'package:flutter/material.dart';

import '../tokens.dart';

/// The REFRACT prism mark: a single beam refracted into a small spectrum.
/// Geometric, minimal, recognizable at small sizes.
class PrismMark extends StatelessWidget {
  const PrismMark({super.key, this.size = 32, this.beamColor});

  final double size;
  final Color? beamColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PrismPainter(beamColor ?? RefractColors.softWhite),
    );
  }
}

class _PrismPainter extends CustomPainter {
  _PrismPainter(this.beamColor);

  final Color beamColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Incoming beam.
    final beam = Paint()
      ..color = beamColor
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, s * 0.28), Offset(s * 0.42, s * 0.5), beam);

    // Prism triangle.
    final prism = Paint()
      ..color = beamColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s * 0.45, s * 0.28)
      ..lineTo(s * 0.78, s * 0.74)
      ..lineTo(s * 0.30, s * 0.78)
      ..close();
    canvas.drawPath(path, prism);

    // Refracted spectrum.
    final spectrum = [
      RefractColors.prismCyan,
      RefractColors.spectralViolet,
      RefractColors.signalAmber,
    ];
    final fan = Paint()
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spectrum.length; i++) {
      fan.color = spectrum[i];
      final dy = (i - 1) * s * 0.09;
      canvas.drawLine(
        Offset(s * 0.62, s * 0.62),
        Offset(s, s * 0.60 + dy),
        fan,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PrismPainter oldDelegate) => oldDelegate.beamColor != beamColor;
}
