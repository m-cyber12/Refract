import 'package:flutter/material.dart';

/// Wordmark derived from the supplied brand artwork; readable by assistive tech.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.width = 112});
  final double width;
  @override Widget build(BuildContext context) => Semantics(
    label: 'REFRACT',
    child: Image.asset('assets/brand/refract-wordmark.png', width: width,
      color: Theme.of(context).colorScheme.onSurface, excludeFromSemantics: true),
  );
}
