import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/recall/recall_page.dart';

Map<String, dynamic> fixture({bool empty = false}) => {
  'query': 'AI privacy', 'mode': 'find', 'answer': empty ? 'I could not find sufficient evidence in the scanned library.' : 'Found one matching source.',
  'answer_kind': 'extractive_evidence', 'model_used': false, 'encoder': 'local-concepts-hash-v1', 'scanned_items': 2,
  'hits': empty ? [] : [{
    'item_id': 'a', 'title': 'Privacy source', 'source_type': 'text', 'captured_ts': 100, 'score': 0.6,
    'reasons': ['Local concept-vector / passage match'], 'supporting_passages': [],
    'evidence': {'item_id': 'a', 'title': 'Privacy source', 'source_url': 'https://example.org/a', 'block_idx': 3, 'quote': 'GDPR protects personal information.', 'kind': 'direct_quote'},
  }],
  'connections': [], 'timeline': [], 'limitations': ['No neural model is running.'],
};

void main() {
  test('Recall response preserves real source IDs, block references and labels', () {
    final result = RecallResponse.fromJson(fixture());
    expect(result.hits.single.evidence.blockIdx, 3);
    expect(result.hits.single.evidence.kind, 'direct_quote');
    expect(result.hits.single.evidence.sourceUrl, 'https://example.org/a');
    expect(result.modelUsed, false);
    expect(result.hits.single.score, 0.6);
    final metadata = RecallEvidence.fromJson({'item_id': 'b', 'title': 'Unparsed document', 'source_url': null, 'block_idx': null, 'quote': 'Unparsed document', 'kind': 'metadata_only'});
    expect(metadata.blockIdx, isNull);
    expect(metadata.kind, 'metadata_only');
  });

  testWidgets('Natural-language Recall sends the request and opens cited source block', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, state) => const RecallPage()),
      GoRoute(path: '/reader/:id', builder: (_, state) => Scaffold(body: Text('Source ${state.pathParameters['id']} block ${state.uri.queryParameters['block']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      projectsProvider.overrideWith((ref) async => []),
      recallProvider.overrideWith((ref, json) async { requests.add(jsonDecode(json) as Map<String, dynamic>); return RecallResponse.fromJson(fixture()); }),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('recall-query')), 'Find that article about AI privacy');
    await tester.tap(find.byKey(const ValueKey('recall-run')));
    await tester.pumpAndSettle();
    expect(requests.single['query'], 'Find that article about AI privacy');
    expect(requests.single['mode'], 'find');
    await tester.scrollUntilVisible(find.text('Open supporting source'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('GDPR protects personal information.'), findsOneWidget);
    expect(find.textContaining('VERBATIM SOURCE EXCERPT'), findsOneWidget);
    await tester.tap(find.text('Open supporting source'));
    await tester.pumpAndSettle();
    expect(find.text('Source a block 3'), findsOneWidget);
  });

  testWidgets('Reading context traverses related sources and missing evidence is explicit', (tester) async {
    Map<String, dynamic>? request;
    await tester.pumpWidget(ProviderScope(overrides: [
      projectsProvider.overrideWith((ref) async => []),
      recallProvider.overrideWith((ref, json) async { request = jsonDecode(json) as Map<String, dynamic>; return RecallResponse.fromJson(fixture(empty: true)); }),
    ], child: const MaterialApp(home: RecallPage(contextItemId: 'reading-source'))));
    await tester.pumpAndSettle();
    expect(request?['context_item_id'], 'reading-source');
    expect(request?['mode'], 'connections');
    await tester.scrollUntilVisible(find.textContaining('could not find sufficient evidence'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('could not find sufficient evidence'), findsOneWidget);
    expect(find.text('Open supporting source'), findsNothing);
  });

  testWidgets('Recall errors are not disguised as no results', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      projectsProvider.overrideWith((ref) async => []),
      recallProvider.overrideWith((ref, json) async => throw StateError('index unavailable')),
    ], child: const MaterialApp(home: RecallPage(contextItemId: 'a'))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('index unavailable'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Recall could not complete'), findsOneWidget);
  });
}
