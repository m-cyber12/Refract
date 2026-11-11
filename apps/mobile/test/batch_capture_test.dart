import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/import/import_page.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/features/import/batch_capture_page.dart';
import 'package:refract/features/import/capture_file.dart';

class _BatchRepo implements RefractRepository {
  final calls = <String>[];
  Map<String, dynamic>? approved;
  @override Future<Map<String, dynamic>> capture(String action, Map<String, dynamic> payload) async {
    calls.add(action);
    if (action == 'preview') { return {'format': payload['format'], 'review_hash': 'review', 'sha256': 'a' * 64,
      'byte_len': 3, 'block_count': 1, 'excerpt': 'excerpt', 'source_url': null, 'warnings': <String>[], 'duplicate': null}; }
    if (action == 'enqueue') { approved = Map<String, dynamic>.from(payload['draft'] as Map); return {'id': payload['id']}; }
    return {'status': 'completed', 'result_item_id': 'saved'};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Picker implements FilePicker {
  FilePickerResult? result;
  int cleanups = 0;
  bool? cleared = true;
  @override dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #pickFiles) {
      expect(call.namedArguments[#allowMultiple], true);
      expect(call.namedArguments[#withData], false);
      expect(call.namedArguments[#withReadStream], true);
      return Future<FilePickerResult?>.value(result);
    }
    if (call.memberName == #clearTemporaryFiles) { cleanups++; return Future<bool?>.value(cleared); }
    return super.noSuchMethod(call);
  }
}
PlatformFile file(String name, List<int> bytes) => PlatformFile(name: name, size: bytes.length, readStream: Stream.value(bytes));

void main() {
  test('Batch selection keeps bytes, uses bounded streams and never accepts a partial selection', () async {
    final picker = _Picker();
    final first = utf8.encode('\uFEFFone\r\n');
    final binary = [37, 80, 68, 70, 255];
    picker.result = FilePickerResult([file('one.txt', first), file('two.pdf', binary)]);
    final selected = await pickCaptureFiles(picker: picker, requireCleanup: true);
    expect(selected!.length, 2); expect(selected.first.byteLength, first.length);
    expect(utf8.encode(selected.first.file.text!), first); expect(base64Decode(selected.last.file.pdfBase64!), binary);
    expect(picker.cleanups, 1);
    picker.result = FilePickerResult([file('good.txt', [65]), file('bad.txt', [255])]);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true), throwsFormatException);
    picker.result = FilePickerResult([file('a.txt', [65, 66]), file('b.txt', [67, 68])]);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true, maxBytes: 3), throwsFormatException);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true, maxCount: 1), throwsFormatException);
    picker.result = FilePickerResult([PlatformFile(name: 'understated.txt', size: 1, readStream: Stream.value([65, 66, 67, 68, 69]))]);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true, maxBytes: 4), throwsFormatException);
    picker.result = FilePickerResult([file('fresh.txt', [65])]);
    picker.cleared = false;
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true), throwsFormatException);
    expect(picker.cleanups, 6);
  });
  test('Stalled provider stream fails atomically, cancels subscription and requests cleanup', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () { cancelled = true; });
    final picker = _Picker()..result = FilePickerResult([
      file('first.txt', [65]),
      PlatformFile(name: 'stalled.txt', size: 1, readStream: controller.stream),
    ]);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true, idleTimeout: const Duration(milliseconds: 30)), throwsFormatException);
    expect(cancelled, true); expect(picker.cleanups, 1);
    await controller.close();
  });
  test('Expired aggregate read budget rejects selection and requests cleanup', () async {
    final picker = _Picker()..result = FilePickerResult([file('first.txt', [65])]);
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true, readBudget: Duration.zero), throwsFormatException);
    expect(picker.cleanups, 1);
  });
  testWidgets('Batch reviews files individually and keeps drafts until explicit discard', (tester) async {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    const one = BatchEntry(file: CaptureFile(name: 'a.txt', format: 'text', text: 'one'), byteLength: 3);
    const two = BatchEntry(file: CaptureFile(name: 'b.txt', format: 'text', text: 'two'), byteLength: 3);
    var selections = 0;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => BatchCapturePage(inbox: inbox, pick: (count, bytes) async {
        selections++; expect(count, 16); expect(bytes, 24 * 1024 * 1024); return [one, two];
      })),
      GoRoute(path: '/import', builder: (_, state) => Scaffold(body: Text('Review ${(state.extra as BatchEntry).file.name}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router)); await tester.pumpAndSettle();
    expect(inbox.entries, isEmpty);
    await tester.tap(find.byKey(const Key('batch-select'))); await tester.pumpAndSettle();
    expect(selections, 1); expect(inbox.entries.length, 2);
    await tester.scrollUntilVisible(find.text('Review this file').first, 100);
    await tester.tap(find.text('Review this file').first); await tester.pumpAndSettle();
    expect(find.text('Review a.txt'), findsOneWidget); expect(inbox.entries.length, 2);
    router.pop(); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Discard batch draft').first, 100);
    await tester.tap(find.text('Discard batch draft').first); await tester.pumpAndSettle();
    expect(inbox.entries, [two]); expect(inbox.byteLength, 3);
  });
  testWidgets('A batch item uses independent review and save while originals remain in queue', (tester) async {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    const one = BatchEntry(file: CaptureFile(name: 'one.txt', format: 'text', text: 'one'), byteLength: 3);
    const two = BatchEntry(file: CaptureFile(name: 'two.txt', format: 'text', text: 'two'), byteLength: 3);
    inbox.add([one, two]); final repo = _BatchRepo();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => BatchCapturePage(inbox: inbox)),
      GoRoute(path: '/import', builder: (_, state) => ImportPage(initialFile: (state.extra as BatchEntry).file)),
      GoRoute(path: '/reader/:id', builder: (_, __) => const Scaffold(body: Text('Saved reader'))),
    ]); addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review this file').first, 120);
    await tester.tap(find.text('Review this file').first); await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    final text = find.byKey(const Key('capture-text'));
    await tester.scrollUntilVisible(text, 120, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    await tester.enterText(text, 'edited'); tester.testTextInput.hide(); await tester.pumpAndSettle();
    final preview = find.byKey(const Key('capture-preview'));
    await tester.scrollUntilVisible(preview, 120, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    await tester.tap(preview); await tester.pumpAndSettle(); expect(repo.calls, ['preview']);
    final save = find.byKey(const Key('capture-save'));
    await tester.scrollUntilVisible(save, 120, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    await tester.tap(save); await tester.pumpAndSettle(); expect(repo.calls, ['preview']);
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(repo.calls, ['preview', 'enqueue', 'run']); expect(repo.approved?['text'], 'edited');
    expect(find.text('Saved reader'), findsOneWidget);
    expect(inbox.entries.map((entry) => entry.file.text).toList(), ['one', 'two']);
  });
  testWidgets('Discard all requires confirmation and never affects later arrivals', (tester) async {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    const first = BatchEntry(file: CaptureFile(name: 'first.txt', format: 'text', text: 'first'), byteLength: 5);
    const later = BatchEntry(file: CaptureFile(name: 'later.txt', format: 'text', text: 'later'), byteLength: 5);
    inbox.add([first]);
    await tester.pumpWidget(MaterialApp(home: BatchCapturePage(inbox: inbox))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batch-discard-all'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Keep drafts')); await tester.pumpAndSettle();
    expect(inbox.entries, [first]);
    await tester.tap(find.byKey(const Key('batch-discard-all'))); await tester.pumpAndSettle();
    inbox.add([later]); await tester.pump();
    await tester.tap(find.text('Discard drafts')); await tester.pumpAndSettle();
    expect(inbox.entries, [later]);
  });
  test('Batch inbox checks count and byte budgets even for injected results', () {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    const entry = BatchEntry(file: CaptureFile(name: 'a.txt', format: 'text', text: 'a'), byteLength: 1);
    inbox.add(List.filled(16, entry));
    expect(() => inbox.add([entry]), throwsFormatException); expect(inbox.entries.length, 16);
    final another = BatchInbox(); addTearDown(another.dispose);
    expect(() => another.add([BatchEntry(file: entry.file, byteLength: 24 * 1024 * 1024 + 1)]), throwsFormatException);
    expect(another.entries, isEmpty);
    another.add([entry]); final snapshot = another.entries; another.add([entry]);
    another.removeSelected(snapshot); expect(another.entries, [entry]);
  });
}
