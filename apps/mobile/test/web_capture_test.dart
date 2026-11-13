import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/import/web_capture_page.dart';

class WebRepo implements RefractRepository {
  final calls = <String>[];
  bool deleteSelected = true;
  final requests = <Map<String, dynamic>>[];
  @override Future<Map<String, dynamic>> web(String action, Map<String, dynamic> payload) async {
    calls.add(action); requests.add(payload);
    if (action == 'start') return {'status': 'approval', 'id': 'session', 'ticket': 'first', 'address': 'https://public.com/', 'http': false, 'destination_change': false};
    if (action == 'advance' && payload['ticket'] == 'first') return {'status': 'approval', 'id': 'session', 'ticket': 'second', 'address': 'http://other.com/', 'http': true, 'destination_change': true};
    if (action == 'advance') return {'status': 'staged', 'id': 'session'};
    if (action == 'delete_selected') return {'deleted': deleteSelected};
    if (action == 'list') return {'previews': <Map<String, dynamic>>[]};
    return {'status': 'closed'};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('Repeated start taps cannot stack consent dialogs or start multiple sessions', (tester) async {
    final repo = WebRepo();
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)], child: const MaterialApp(home: WebCapturePage(initialUrl: 'https://public.com/'))));
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('web-start'));
    await tester.tap(start); await tester.tap(start, warnIfMissed: false); await tester.pumpAndSettle();
    expect(find.text('Approve preview copy'), findsOneWidget); expect(repo.calls, isEmpty);
    await tester.tap(find.text('Approve preview copy')); await tester.pumpAndSettle();
    expect(repo.calls, ['start']); expect(find.text('Approve preview copy'), findsNothing);
    expect(find.byKey(const Key('web-advance')), findsOneWidget);
  });
  testWidgets('Rapid discard taps confirm and delete only once', (tester) async {
    final repo = WebRepo();
    final preview = <String, dynamic>{'id': 'preview', 'requested_url': 'https://public.com/a', 'final_url': 'https://public.com/b', 'byte_len': 8, 'sha256': 'hash', 'consent_ts': 42};
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo), webPreviewsProvider.overrideWith((ref) async => [preview])], child: const MaterialApp(home: WebPreviewsPage())));
    await tester.pumpAndSettle();
    final discard = find.text('Discard preview'); await tester.ensureVisible(discard);
    await tester.tap(discard); await tester.tap(discard, warnIfMissed: false); await tester.pumpAndSettle();
    expect(find.text('Discard this web preview copy?'), findsOneWidget); expect(repo.calls, isEmpty);
    await tester.tap(find.text('Discard copy')); await tester.pumpAndSettle();
    expect(repo.calls, ['delete_selected']); expect(repo.requests.single, preview);
  });
  testWidgets('Changed web preview is not discarded on stale confirmation', (tester) async {
    final repo = WebRepo()..deleteSelected = false;
    final preview = <String, dynamic>{'id': 'preview', 'requested_url': 'https://public.com/a', 'final_url': 'https://public.com/b', 'byte_len': 8, 'sha256': 'hash', 'consent_ts': 42};
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo), webPreviewsProvider.overrideWith((ref) async => [preview])], child: const MaterialApp(home: WebPreviewsPage())));
    await tester.pumpAndSettle(); await tester.ensureVisible(find.text('Discard preview'));
    await tester.tap(find.text('Discard preview')); await tester.pumpAndSettle();
    await tester.tap(find.text('Discard copy')); await tester.pumpAndSettle();
    expect(repo.calls, ['delete_selected']); expect(repo.requests.single, preview);
    expect(find.textContaining('Preview changed or is no longer present'), findsOneWidget);
  });
  testWidgets('Fetch requires staging consent and exact redirect approval; no automatic save', (tester) async {
    final repo = WebRepo();
    final router = GoRouter(initialLocation: '/', routes: [GoRoute(path: '/', builder: (_, __) => const WebCapturePage(initialUrl: 'https://public.com/')), GoRoute(path: '/web/previews', builder: (_, __) => const WebPreviewsPage())]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tester.tap(find.byKey(const Key('web-start'))); await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tester.tap(find.text('Not now')); await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tester.tap(find.byKey(const Key('web-start'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Approve preview copy')); await tester.pumpAndSettle();
    expect(repo.calls, ['start']); expect(repo.requests.first['stage_approved'], true);
    await tester.ensureVisible(find.byKey(const Key('web-advance'))); await tester.tap(find.byKey(const Key('web-advance'))); await tester.pumpAndSettle();
    expect(repo.calls, ['start', 'advance']);
    expect(find.textContaining('unencrypted'), findsOneWidget);
    expect(find.textContaining('changes host or port'), findsOneWidget);
    expect(repo.requests.last['ticket'], 'first');
    await tester.ensureVisible(find.byKey(const Key('web-advance'))); await tester.tap(find.byKey(const Key('web-advance'))); await tester.pumpAndSettle();
    expect(repo.calls, ['start', 'advance', 'advance']);
    expect(repo.requests.last['ticket'], 'second'); expect(repo.requests.last['http'], true); expect(repo.requests.last['destination_change'], true);
    expect(find.textContaining('not a library save'), findsOneWidget);
  });
}
