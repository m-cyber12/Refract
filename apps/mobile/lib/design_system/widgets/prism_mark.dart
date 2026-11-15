import 'package:flutter/material.dart';

/// The supplied REFRACT monogram, tinted for the current surface.
class PrismMark extends StatelessWidget {
  const PrismMark({super.key, this.size = 32, this.beamColor});
  final double size;
  final Color? beamColor;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/refract-mark.png',
    width: size, height: size, fit: BoxFit.contain,
    color: beamColor ?? Theme.of(context).colorScheme.onSurface,
    excludeFromSemantics: true,
  );
}
