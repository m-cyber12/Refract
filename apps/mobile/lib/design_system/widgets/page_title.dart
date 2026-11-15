import 'package:flutter/material.dart';
import 'prism_mark.dart';

/// Compact identity for top-level and detail screens; the title remains text.
class RefractPageTitle extends StatelessWidget {
  const RefractPageTitle(this.title, {super.key});
  final String title;

  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    const PrismMark(size: 23),
    const SizedBox(width: 10),
    Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
  ]);
}
