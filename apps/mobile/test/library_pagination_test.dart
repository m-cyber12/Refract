import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/library/library_page.dart';

class _Repo implements RefractRepository {
  final offsets = <int>[];
  bool failSecond = false;
  final items = List.generate(55, (i) => Item(id: '$i', title: 'Document $i',
    sourceType: SourceType.text, importTs: 1, contentHash: 'hash',
    extractionConfidence: 1, status: ImportStatus.ready, blocks: []));
  @override List<Item> listItems({int limit = 50, int offset = 0}) {
    offsets.add(offset);
    if (failSecond && offset == 50) throw StateError('simulated');
    return items.skip(offset).take(limit).toList();
  }
  @override List<Item> searchPage(String query, {int limit = 51, int offset = 0}) =>
    items.skip(offset).take(limit).toList();
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Library pages beyond 50 and resets after search', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: const MaterialApp(home: LibraryPage())));
    await tester.pumpAndSettle();
    expect(find.text('Document 0'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    await tester.tap(find.text('Next')); await tester.pumpAndSettle();
    expect(find.text('Document 50'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(repo.offsets, contains(50));
    await tester.enterText(find.byType(TextField), 'query'); await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    await tester.tap(find.text('Next')); await tester.pumpAndSettle();
    expect(find.text('Document 50'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ''); await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Document 0'), findsOneWidget);
  });
  testWidgets('Library page errors can be retried or navigated back', (tester) async {
    final repo = _Repo()..failSecond = true;
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)],
      child: const MaterialApp(home: LibraryPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); await tester.pumpAndSettle();
    expect(find.textContaining('could not be loaded'), findsOneWidget);
    repo.failSecond = false;
    await tester.tap(find.text('Retry')); await tester.pumpAndSettle();
    expect(find.text('Document 50'), findsOneWidget);
    await tester.tap(find.text('Previous')); await tester.pumpAndSettle();
    expect(find.text('Document 0'), findsOneWidget);
  });
}
