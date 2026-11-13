import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/settings/settings_page.dart';

class _Repo implements RefractRepository {
  int exports = 0;
  @override String export() { exports++; return '{"items":[]}'; }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Partial plaintext JSON requires explicit consent and guards repeated export', (tester) async {
    final repo = _Repo();
    final write = Completer<String>();
    var writes = 0;
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: SettingsPage(writeExport: (json) { writes++; return write.future; }))));
    await tester.scrollUntilVisible(find.text('Write partial plaintext JSON'), 160, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Write partial plaintext JSON')); await tester.pumpAndSettle();
    expect(find.textContaining('not an encrypted backup'), findsOneWidget);
    expect(find.textContaining('up to 10,000 items'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(repo.exports, 0); expect(writes, 0);
    await tester.tap(find.text('Write partial plaintext JSON')); await tester.pumpAndSettle();
    await tester.tap(find.text('Write plaintext JSON')); await tester.pump();
    expect(repo.exports, 1); expect(writes, 1);
    await tester.tap(find.text('Write partial plaintext JSON')); await tester.pump();
    expect(repo.exports, 1); expect(writes, 1);
    write.complete('/local/export.json'); await tester.pumpAndSettle();
    expect(find.textContaining('This is not a full backup'), findsOneWidget);
  });
  testWidgets('Partial JSON write failures are reported without claiming success', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: MaterialApp(home: SettingsPage(writeExport: (_) async => throw StateError('write failed')))));
    await tester.scrollUntilVisible(find.text('Write partial plaintext JSON'), 160, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Write partial plaintext JSON')); await tester.pumpAndSettle();
    await tester.tap(find.text('Write plaintext JSON')); await tester.pumpAndSettle();
    expect(find.textContaining('JSON export failed'), findsOneWidget);
  });
}
