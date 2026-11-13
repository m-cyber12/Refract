import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/features/reader/reader_page.dart';

void main() {
  Widget view(String id, {int? block}) => MaterialApp(home: Scaffold(body: PdfDocumentViews(
    itemId: id, focusBlock: block,
    original: const Text('ORIGINAL VIEW'), extracted: const Text('TEXT VIEW'),
  )));
  testWidgets('Original view is first; extracted text requires a separate selection', (tester) async {
    await tester.pumpWidget(view('one')); await tester.pumpAndSettle();
    expect(find.text('ORIGINAL VIEW'), findsOneWidget);
    expect(find.text('TEXT VIEW'), findsNothing);
    await tester.tap(find.byKey(const Key('pdf-text-view'))); await tester.pumpAndSettle();
    expect(find.text('TEXT VIEW'), findsOneWidget);
    expect(find.text('ORIGINAL VIEW'), findsNothing);
    await tester.tap(find.byKey(const Key('pdf-original-view'))); await tester.pumpAndSettle();
    expect(find.text('ORIGINAL VIEW'), findsOneWidget);
  });
  testWidgets('Evidence links show text and changed item resets view', (tester) async {
    await tester.pumpWidget(view('one', block: 2)); await tester.pumpAndSettle();
    expect(find.text('TEXT VIEW'), findsOneWidget);
    await tester.pumpWidget(view('two')); await tester.pumpAndSettle();
    expect(find.text('ORIGINAL VIEW'), findsOneWidget);
    expect(find.text('TEXT VIEW'), findsNothing);
    await tester.pumpWidget(view('two', block: 9)); await tester.pumpAndSettle();
    expect(find.text('TEXT VIEW'), findsOneWidget);
  });
}
