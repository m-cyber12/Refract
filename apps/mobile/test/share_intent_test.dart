import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/share_intent.dart';
import 'package:refract/features/import/shared_drafts_page.dart';

void main() {
  const channel = MethodChannel('dev.refract/share-test');
  late List<Map<String, dynamic>> native;
  late ShareIntentChannel inbox;
  late List<String> calls;
  bool failAck = false;
  Map<String, dynamic> text(String id, String text) => {'id': id, 'name': 'Shared text or address', 'format': 'text', 'bytes': Uint8List.fromList(utf8.encode(text))};
  setUp(() {
    native = []; calls = []; failAck = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'peekShare') return {'draft': native.isEmpty ? null : native.first};
      if (call.method == 'ackShare') {
        if (failAck) throw PlatformException(code: 'uncertain_ack');
        if (native.isNotEmpty && native.first['id'] == call.arguments) native.removeAt(0);
      }
      return null;
    });
    inbox = ShareIntentChannel(channel: channel);
  });
  tearDown(() {
    inbox.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  testWidgets('Cold-start pull accepts queued items before a page subscribes; binary bytes and BOM stay exact', (tester) async {
    final pdf = Uint8List.fromList([37, 80, 68, 70, 255, 0, 128]);
    native.addAll([text('cold-text', '\uFEFF# Source 東京'), {'id': 'cold-pdf', 'name': 'source.pdf', 'format': 'pdf', 'bytes': pdf}]);
    inbox.init(); inbox.init(); await tester.pumpAndSettle();
    expect(native, isEmpty); expect(inbox.drafts.length, 2);
    expect(inbox.drafts.first.file!.text, '\uFEFF# Source 東京');
    expect(base64Decode(inbox.drafts.last.file!.pdfBase64!), pdf);
    expect(calls.where((v) => v == 'ackShare').length, 2);
    await tester.pumpWidget(MaterialApp(home: SharedDraftsPage(inbox: inbox))); await tester.pumpAndSettle();
    expect(find.text('source.pdf'), findsOneWidget); expect(find.text('Review this draft'), findsNWidgets(2));
    // Delivery and opening history never call the capture repository.
    expect(calls.toSet(), {'peekShare', 'ackShare'});
  });
  testWidgets('Resume receives a later share without replacing an existing draft', (tester) async {
    native.add(text('first', 'First draft')); inbox.init(); await tester.pumpAndSettle();
    native.add(text('second', 'https://example.test/private?token=local'));
    inbox.didChangeAppLifecycleState(AppLifecycleState.resumed); await tester.pumpAndSettle();
    expect(inbox.drafts.map((d) => d.file!.text), ['First draft', 'https://example.test/private?token=local']);
    expect(inbox.drafts.last.file!.format, 'text'); // No fetch or assumed URL parser.
  });
  testWidgets('Uncertain native ack is retried without duplicate delivery, even after discard', (tester) async {
    native.add(text('same-id', 'One share')); failAck = true; inbox.init(); await tester.pumpAndSettle();
    expect(inbox.drafts.length, 1); expect(native.length, 1);
    await inbox.pull(); expect(inbox.drafts.length, 1);
    inbox.remove('same-id'); await tester.pumpAndSettle(); expect(inbox.drafts, isEmpty);
    failAck = false; await inbox.pull(); expect(native, isEmpty); expect(inbox.drafts, isEmpty);
  });
  testWidgets('Bounded inbox leaves excess native input unacknowledged, then pulls after discard', (tester) async {
    native.addAll(List.generate(17, (n) => text('item-$n', 'Source $n')));
    inbox.init(); await tester.pumpAndSettle(); expect(inbox.drafts.length, 16); expect(native.single['id'], 'item-16'); expect(inbox.notice, contains('full'));
    inbox.remove('item-0'); await tester.pumpAndSettle(); expect(inbox.drafts.length, 16); expect(native, isEmpty); expect(inbox.drafts.last.file!.text, 'Source 16');
  });
  testWidgets('Malformed UTF-8, oversized inputs and native errors remain visible but cannot be reviewed', (tester) async {
    native.addAll([
      {'id': 'bad-utf8', 'format': 'text', 'bytes': Uint8List.fromList([255])},
      {'id': 'too-large', 'format': 'text', 'bytes': Uint8List(2 * 1024 * 1024 + 1)},
      {'id': 'provider-denied', 'error': 'Provider access expired. Share again.'},
    ]);
    inbox.init(); await tester.pumpAndSettle(); expect(inbox.drafts.length, 3); expect(inbox.drafts.every((d) => d.file == null), true);
    await tester.pumpWidget(MaterialApp(home: SharedDraftsPage(inbox: inbox))); await tester.pumpAndSettle();
    expect(find.text('Review this draft'), findsNothing); expect(find.text('Provider access expired. Share again.'), findsOneWidget);
    await tester.tap(find.text('Discard draft').first); await tester.pumpAndSettle(); expect(inbox.drafts.length, 2);
  });
  testWidgets('Review uses route extra, not source-bearing URLs; incoming shares do not navigate', (tester) async {
    native.add(text('secret', 'PRIVATE source ?token=local'));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, state) => SharedDraftsPage(inbox: inbox)), GoRoute(path: '/import', builder: (_, state) => Scaffold(body: Text((state.extra as SharedDraft).file!.text!)))]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router)); inbox.init(); await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    await tester.scrollUntilVisible(find.text('Review this draft'), 100); await tester.tap(find.text('Review this draft')); await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(), isNot(contains('PRIVATE'))); expect(find.text('PRIVATE source ?token=local'), findsOneWidget);
    native.add(text('later', 'Do not replace open draft')); await inbox.pull(); await tester.pumpAndSettle();
    expect(find.text('PRIVATE source ?token=local'), findsOneWidget); expect(router.routeInformationProvider.value.uri.toString(), isNot(contains('Do not replace')));
  });
}
