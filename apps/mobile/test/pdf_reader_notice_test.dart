import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/features/reader/reader_page.dart';

void main() {
  testWidgets('Empty PDF reader does not invent a capture history', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PdfReaderNotice(hasText: false))));
    expect(find.text('PDF text unavailable'), findsOneWidget);
    expect(find.text('Original page layout is not displayed in this reader.'), findsOneWidget);
    expect(find.textContaining('No text blocks are available'), findsOneWidget);
    expect(find.textContaining('capture history and PDF validity cannot be determined'), findsOneWidget);
    expect(find.textContaining('Original-only capture:'), findsNothing);
    expect(find.textContaining('PDF text extraction only:'), findsNothing);
  });
  testWidgets('PDF reader with blocks warns of incomplete extraction without claiming verification', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PdfReaderNotice(hasText: true))));
    expect(find.text('Extracted PDF text'), findsOneWidget);
    expect(find.text('Original page layout is not displayed in this reader.'), findsOneWidget);
    expect(find.textContaining('may be incomplete'), findsOneWidget);
    expect(find.textContaining('authenticity are not verified'), findsOneWidget);
    expect(find.textContaining('No text blocks are available'), findsNothing);
  });
}
