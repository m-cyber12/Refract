import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/reader/reader_page.dart';

void main() {
  Future<void> show(WidgetTester tester, Map<String, dynamic> data) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [captureDiagnosticsProvider('item').overrideWith((ref) async => data)],
      child: const MaterialApp(home: Scaffold(body: CaptureDiagnosticsPanel(itemId: 'item'))),
    ));
    await tester.pumpAndSettle();
  }
  testWidgets('legacy extraction history is unknown', (tester) async {
    await show(tester, {'available': false, 'warnings': <String>[]});
    expect(find.textContaining('extraction history is unknown'), findsOneWidget);
    expect(find.textContaining('No extraction warnings'), findsNothing);
  });
  testWidgets('empty diagnostics do not promise completeness', (tester) async {
    await show(tester, {'available': true, 'warnings': <String>[]});
    expect(find.textContaining('does not guarantee complete or accurate text'), findsOneWidget);
  });
  testWidgets('capture warning remains visible in the reader', (tester) async {
    await show(tester, {'available': true, 'warnings': ['1 of 2 PDF pages produced no extractable text.']});
    expect(find.textContaining('1 of 2 PDF pages'), findsOneWidget);
    expect(find.textContaining('may not describe every extraction problem'), findsOneWidget);
  });
}
