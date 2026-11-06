import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:refract/design_system/widgets/prism_mark.dart';

void main() {
  testWidgets('Prism mark renders without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PrismMark())));
    expect(find.byType(PrismMark), findsOneWidget);
  });
}
