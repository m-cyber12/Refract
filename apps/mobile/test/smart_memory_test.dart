import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/memory/memory_page.dart';

void main() {
  final topicJson = <String, dynamic>{'id': 't1', 'name': 'privacy', 'origin': 'automatic', 'created_ts': 1700000000, 'pinned': false, 'item_count': 2};

  test('Smart Memory models decode native JSON shapes', () {
    final topic = Topic.fromJson(topicJson);
    expect(topic.itemCount, 2);
    expect(topic.pinned, false);
    final entity = EntityRecord.fromJson({'id': 'e1', 'name': '2026-03-01', 'kind': 'date', 'created_ts': 0, 'item_count': 1});
    expect(entity.kind, 'date');
    final rel = Relationship.fromJson({'id': 'r1', 'source_item_id': 'a', 'target_item_id': 'b', 'kind': 'same_topic', 'basis': 'shares privacy topic', 'confidence': 0.6, 'dismissed': false, 'created_ts': 0});
    expect(rel.confidence, 0.6);
    expect(rel.basis, isNotEmpty);
    final timeline = TimelineEntry.fromJson({'item_id': 'a', 'title': 'A', 'time_kind': 'publication', 'ts': 0, 'note': null});
    expect(timeline.timeKind, 'publication');
    expect(timeline.note, isNull);
    final evolution = TopicEvolution.fromJson({'topic': topicJson, 'stages': [{'from_ts': 0, 'to_ts': 1, 'item_count': 2, 'description': 'Two captured items', 'item_ids': ['a', 'b']}], 'summary': 'Capture history only.'});
    expect(evolution.stages.single.itemIds, ['a', 'b']);
    final project = Project.fromJson({'id': 'p1', 'name': 'Thesis', 'description': null, 'created_ts': 0, 'item_count': 2});
    expect(project.itemCount, 2);
    final report = OrganizeReport.fromJson({'item_id': 'a', 'topics': ['privacy'], 'entities': ['date: 2026-03-01'], 'relationships_suggested': 1});
    expect(report.relationshipsSuggested, 1);
  });

  testWidgets('Memory screen shows explicit timestamp kinds and topic controls', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      memoryTimelineProvider.overrideWith((ref) async => [TimelineEntry(itemId: 'a', title: 'Privacy note', timeKind: 'capture', ts: 1700000000), TimelineEntry(itemId: 'a', title: 'Privacy note', timeKind: 'event', ts: 1772323200, note: 'date extracted from content — candidate only')]),
      topicsProvider.overrideWith((ref) async => [Topic.fromJson(topicJson)]),
      entitiesProvider.overrideWith((ref) async => []),
      relationshipsProvider.overrideWith((ref) async => []),
      projectsProvider.overrideWith((ref) async => []),
    ], child: const MaterialApp(home: MemoryPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('UTC · capture'), findsOneWidget);
    expect(find.textContaining('UTC · event'), findsOneWidget);
    expect(find.textContaining('not verified facts'), findsOneWidget);
    await tester.tap(find.text('Topics'));
    await tester.pumpAndSettle();
    expect(find.text('privacy'), findsOneWidget);
    expect(find.textContaining('suggested category'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('topic-actions-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Merge into…'), findsOneWidget);
    expect(find.text('Reject category'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename topic'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Memory errors are visible rather than disguised as empty results', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      memoryTimelineProvider.overrideWith((ref) async => throw StateError('store unavailable')),
      topicsProvider.overrideWith((ref) async => []),
      entitiesProvider.overrideWith((ref) async => []),
      relationshipsProvider.overrideWith((ref) async => []),
      projectsProvider.overrideWith((ref) async => []),
    ], child: const MaterialApp(home: MemoryPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('store unavailable'), findsOneWidget);
  });
}
