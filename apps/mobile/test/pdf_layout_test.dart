import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/reader/pdf_layout.dart';

class _Repo implements RefractRepository {
  final calls = <Map<String, dynamic>>[];
  Completer<void>? gate;
  bool damaged = false;
  @override Future<Map<String, dynamic>> capture(String action, Map<String, dynamic> payload) async {
    calls.add({'action': action, ...payload});
    if (gate != null) await gate!.future;
    if (damaged) throw StateError('damaged');
    return {'source_type': 'pdf', 'bytes_base64': base64Encode([1, 2, 3]), 'byte_len': 3};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=');

void main() {
  testWidgets('Local PDF rendering requires approval and supports bounded page navigation', (tester) async {
    final repo = _Repo(); final pages = <int>[];
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PdfLayoutViewer(itemId: 'one', render: (bytes, index) async {
        expect(bytes, [1, 2, 3]); pages.add(index); return {'png': _png, 'pages': 2, 'index': index};
      }))))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-pdf-layout'))); await tester.pumpAndSettle();
    expect(repo.calls, isEmpty); await tester.tap(find.text('Not now')); await tester.pumpAndSettle();
    expect(repo.calls, isEmpty); expect(pages, isEmpty);
    await tester.tap(find.byKey(const Key('open-pdf-layout'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Render locally')); await tester.pumpAndSettle();
    expect(repo.calls.single['id'], 'one'); expect(repo.calls.single['approved'], true);
    expect(find.text('Page 1 of 2'), findsOneWidget); expect(pages, [0]);
    await tester.tap(find.text('Next page')); await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget); expect(pages, [0, 1]);
    await tester.tap(find.text('Close layout')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-pdf-layout')), findsOneWidget);
  });
  testWidgets('Damaged original is never sent to the renderer', (tester) async {
    final repo = _Repo()..damaged = true; var renders = 0;
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: Scaffold(body: PdfLayoutViewer(itemId: 'one', render: (bytes, index) async { renders++; return {}; })))));
    await tester.tap(find.byKey(const Key('open-pdf-layout'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Render locally')); await tester.pumpAndSettle();
    expect(renders, 0); expect(find.textContaining('could not be rendered'), findsOneWidget);
  });
  testWidgets('Item change during read does not render another item', (tester) async {
    final repo = _Repo()..gate = Completer<void>(); var renders = 0;
    Widget view(String id) => ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: Scaffold(body: PdfLayoutViewer(itemId: id, render: (bytes, index) async { renders++; return {'png': _png, 'pages': 1, 'index': 0}; }))));
    await tester.pumpWidget(view('one')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-pdf-layout'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Render locally')); await tester.pump();
    await tester.pumpWidget(view('two')); await tester.pump();
    repo.gate!.complete(); await tester.pumpAndSettle();
    expect(renders, 0); expect(find.text('Page 1 of 1'), findsNothing);
  });
}
