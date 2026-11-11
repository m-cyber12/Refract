import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/reader/original_export.dart';

class _Repo implements RefractRepository {
  final calls = <Map<String, dynamic>>[];
  bool damaged = false;
  @override Future<Map<String, dynamic>> capture(String action, Map<String, dynamic> payload) async {
    calls.add({'action': action, ...payload});
    if (damaged) throw const FormatException('original mismatch');
    final bytes = [37, 80, 68, 70, 0, 255];
    return {'source_type': 'pdf', 'bytes_base64': base64Encode(bytes), 'byte_len': bytes.length};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('No original is read until explicit approval; picker cancellation is not success', (tester) async {
    final repo = _Repo(); var saves = 0;
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: Scaffold(body: OriginalExportButton(itemId: 'item', extension: 'pdf', save: (bytes, name) async {
        saves++; expect(bytes, [37, 80, 68, 70, 0, 255]); expect(name, 'refract-original.pdf'); return null;
      })))));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('export-original'));
    await tester.tap(button); await tester.pumpAndSettle(); expect(repo.calls, isEmpty); expect(saves, 0);
    await tester.tap(find.text('Not now')); await tester.pumpAndSettle(); expect(repo.calls, isEmpty);
    await tester.tap(button); await tester.tap(button, warnIfMissed: false); await tester.pumpAndSettle();
    expect(find.text('Export a copy of the original?'), findsOneWidget);
    await tester.tap(find.text('Choose destination')); await tester.pumpAndSettle();
    expect(repo.calls, [{'action': 'read_original', 'id': 'item', 'approved': true}]); expect(saves, 1);
    expect(find.textContaining('No destination was confirmed'), findsOneWidget);
  });
  testWidgets('A damaged original never reaches the destination picker', (tester) async {
    final repo = _Repo()..damaged = true; var saves = 0;
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: Scaffold(body: OriginalExportButton(itemId: 'bad', extension: 'pdf', save: (bytes, name) async { saves++; return 'chosen'; })))));
    await tester.pumpAndSettle(); await tester.tap(find.byKey(const Key('export-original'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Choose destination')); await tester.pumpAndSettle();
    expect(saves, 0); expect(find.textContaining('could not be confirmed'), findsOneWidget);
  });
}
