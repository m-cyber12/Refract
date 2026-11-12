import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/core/share_intent.dart';
import 'package:refract/features/import/capture_file.dart';
import 'package:refract/features/import/import_page.dart';
import 'package:refract/features/import/web_capture_page.dart';

class _Repo implements RefractRepository {
  final calls = <String>[];
  final webCalls = <String>[];
  @override Future<Map<String, dynamic>> web(String action, Map<String, dynamic> payload) async { webCalls.add(action); return {'deleted': true}; }
  int itemReads = 0;
  @override Item? getItem(String id) { itemReads++; return null; }
  Map<String, dynamic>? last;
  Map<String, dynamic>? approvedDraft;
  bool duplicate = false;
  bool failPreview = false;
  bool failCommit = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> capture(String action, Map<String, dynamic> payload) async {
    calls.add(action); last = payload;
    if (action == 'enqueue') { approvedDraft = Map<String, dynamic>.from(payload['draft'] as Map); return {'id': payload['id'], 'status': 'queued'}; }
    if (pending != null) return pending!.future;
    if (action == 'preview') {
      if (failPreview) throw const FormatException('Invalid input; no source saved');
      return {'format': payload['format'], 'review_hash': 'review-binding', 'sha256': 'a' * 64,
        'byte_len': 12, 'title': 'Reviewed source', 'block_count': 1, 'excerpt': 'Reader excerpt',
        'source_url': payload['source_url'], 'other_saved_inputs_for_url': 0,
        'warnings': ['Local only; no URL fetch.'], 'duplicate': duplicate ? {'id': 'existing', 'title': 'Existing title', 'import_ts': 1} : null};
    }
    if (failCommit) throw const FormatException('Save failed');
    if (action == 'run') return {'status': 'completed', 'result_item_id': 'saved'};
    return {'item': {'id': 'saved'}, 'reused_existing': payload['choice'] == 'use_existing'};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Shares extends ShareIntentChannel {
  final removed = <String>[];
  @override Future<bool> remove(String id) async { removed.add(id); return true; }
}
class _Picker implements FilePicker {
  FilePickerResult? result;
  Object? error;
  bool? cleared = true;
  int cleanups = 0;
  @override dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #pickFiles) {
      expect(invocation.namedArguments[#withData], false);
      expect(invocation.namedArguments[#withReadStream], true);
      if (error != null) return Future<FilePickerResult?>.error(error!);
      return Future<FilePickerResult?>.value(result);
    }
    if (invocation.memberName == #clearTemporaryFiles) { cleanups++; return Future<bool?>.value(cleared); }
    return super.noSuchMethod(invocation);
  }
}
Future<void> _host(WidgetTester tester, _Repo repo, {ImportPage page = const ImportPage()}) async {
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, s) => page), GoRoute(path: '/reader/:id', builder: (_, s) => Scaffold(body: Text('Opened ${s.pathParameters['id']}')))]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [bootstrapProvider.overrideWith((ref) async => repo)], child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}
Future<void> _click(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(finder, 140, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(finder); await tester.pumpAndSettle();
}
Future<void> _enter(WidgetTester tester, String text) async {
  // Start at the top: the input can be outside the lazy ListView cache after
  // adding capture controls, or above the current offset after an earlier review.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(const Key('capture-text')), 140, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('capture-text')), text);
  tester.testTextInput.hide(); await tester.pumpAndSettle();
}
void main() {
  testWidgets('Failed PDF preview offers an explicit original-only choice, not automatic saving', (tester) async {
    final repo = _Repo()..failPreview = true;
    const pdf = CaptureFile(name: 'scan.pdf', format: 'pdf', pdfBase64: 'JVBERg==');
    await _host(tester, repo, page: const ImportPage(initialFile: pdf));
    await _click(tester, 'capture-preview'); expect(repo.calls, ['preview']);
    expect(find.byKey(const Key('capture-original-only')), findsOneWidget);
    await _click(tester, 'capture-original-only'); expect(repo.calls, ['preview']);
    expect(find.textContaining('without checking PDF validity'), findsOneWidget);
    expect(find.byKey(const Key('capture-save')), findsNothing);
    repo.failPreview = false; await _click(tester, 'capture-preview');
    expect(repo.calls, ['preview', 'preview']); expect(repo.last?['format'], 'pdf_original');
    expect(repo.last?['pdf_base64'], pdf.pdfBase64); expect(find.byKey(const Key('capture-save')), findsOneWidget);
  });
  testWidgets('Original-only PDF requires explicit mode, review and save approval', (tester) async {
    final repo = _Repo(); final inbox = _Shares(); addTearDown(inbox.dispose);
    const pdf = CaptureFile(name: 'scan.pdf', format: 'pdf', pdfBase64: 'JVBERg==');
    await _host(tester, repo, page: ImportPage(initialFile: pdf, sharedDraftId: 'pdf-share', sharedDraftStaged: true, shareInbox: inbox));
    expect(repo.calls, isEmpty); await _click(tester, 'capture-format');
    await tester.tap(find.text('PDF original only (no extraction)').last); await tester.pumpAndSettle();
    expect(find.textContaining('without checking PDF validity'), findsOneWidget); expect(repo.calls, isEmpty);
    await _click(tester, 'capture-preview');
    expect(repo.calls, ['preview']); expect(repo.last?['format'], 'pdf_original'); expect(repo.last?['pdf_base64'], pdf.pdfBase64);
    await _click(tester, 'capture-save'); expect(repo.calls, ['preview']); expect(inbox.removed, isEmpty);
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(repo.calls, ['preview', 'enqueue', 'run']); expect(repo.approvedDraft?['format'], 'pdf_original');
    expect(repo.approvedDraft?['pdf_base64'], pdf.pdfBase64); expect(inbox.removed, ['pdf-share']);
  });
  testWidgets('Saved unedited web preview is cleaned up only after reviewed library save', (tester) async {
    final repo = _Repo();
    const source = WebPreview(id: 'staged-id', html: '<p>Original</p>', requestedUrl: 'https://public.com/a', finalUrl: 'https://public.com/b');
    await _host(tester, repo, page: const ImportPage(webPreview: source));
    await _click(tester, 'capture-preview'); expect(repo.webCalls, isEmpty);
    await _click(tester, 'capture-save'); await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(repo.calls, ['preview', 'enqueue', 'run']); expect(repo.webCalls, ['delete']);
  });
  testWidgets('Saving an unchanged shared draft removes only that draft', (tester) async {
    final repo = _Repo(); final inbox = _Shares(); addTearDown(inbox.dispose);
    await _host(tester, repo, page: ImportPage(initialFile: const CaptureFile(name: 'table.csv', format: 'text', text: 'a,b\r\n1,2\r\n'), sharedDraftId: 'shared-id', sharedDraftStaged: true, shareInbox: inbox));
    await _click(tester, 'capture-preview'); await _click(tester, 'capture-save');
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(inbox.removed, ['shared-id']);
  });
  testWidgets('Saving an edited shared draft retains its original handoff copy', (tester) async {
    final repo = _Repo(); final inbox = _Shares(); addTearDown(inbox.dispose);
    await _host(tester, repo, page: ImportPage(initialFile: const CaptureFile(name: 'original.txt', format: 'text', text: 'Original'), sharedDraftId: 'shared-id', sharedDraftStaged: true, shareInbox: inbox));
    await _enter(tester, 'Edited'); await _click(tester, 'capture-preview'); await _click(tester, 'capture-save');
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(inbox.removed, isEmpty); expect(repo.approvedDraft?['text'], 'Edited');
    expect(find.textContaining('original handoff copy remains'), findsOneWidget);
  });
  testWidgets('Saving a different chosen file leaves the shared original in its inbox', (tester) async {
    final repo = _Repo(); final inbox = _Shares(); addTearDown(inbox.dispose);
    await _host(tester, repo, page: ImportPage(initialFile: const CaptureFile(name: 'original.txt', format: 'text', text: 'Original'), sharedDraftId: 'shared-id', shareInbox: inbox, pickFile: () async => const CaptureFile(name: 'replacement.txt', format: 'text', text: 'Replacement')));
    await _click(tester, 'capture-file'); await _click(tester, 'capture-preview'); await _click(tester, 'capture-save');
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(inbox.removed, isEmpty); expect(repo.approvedDraft?['text'], 'Replacement');
  });
  testWidgets('Saving edited web preview retains the original staged copy', (tester) async {
    final repo = _Repo();
    const source = WebPreview(id: 'staged-id', html: '<p>Original</p>', requestedUrl: 'https://public.com/a', finalUrl: 'https://public.com/b');
    await _host(tester, repo, page: const ImportPage(webPreview: source));
    await _enter(tester, '<p>Edited</p>'); await _click(tester, 'capture-preview');
    await _click(tester, 'capture-save'); await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    expect(repo.webCalls, isEmpty); expect(repo.approvedDraft?['text'], '<p>Edited</p>');
  });
  test('URL references retain their distinct not-fetched source kind', () {
    expect(sourceTypeFromString('url_reference'), SourceType.urlReference);
    expect(sourceTypeLabel(SourceType.urlReference), contains('not fetched'));
  });
  test('JSON and XML are selected as exact UTF-8 text without structural parsing', () async {
    final picker = _Picker();
    for (final pair in [const ['file.JSON', '\uFEFF{not validated}\r\n'], const ['file.xml', '<!DOCTYPE x><broken>\r\n']]) {
      final bytes = Uint8List.fromList(utf8.encode(pair[1]));
      picker.result = FilePickerResult([PlatformFile(name: pair[0], size: bytes.length, readStream: Stream.value(bytes))]);
      final file = await pickCaptureFile(picker: picker, requireCleanup: true);
      expect(file!.format, 'text'); expect(utf8.encode(file.text!), bytes);
    }
  });
  testWidgets('JSON review identifies plain text and does not auto-save', (tester) async {
    final repo = _Repo();
    await _host(tester, repo, page: ImportPage(pickFile: () async => const CaptureFile(name: 'source.JSON', format: 'text', text: '{not validated}')));
    await _click(tester, 'capture-file');
    expect(find.textContaining('not interpreted or validated'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await _click(tester, 'capture-preview');
    expect(repo.last?['format'], 'text'); expect(repo.last?['text'], '{not validated}'); expect(repo.calls, ['preview']);
  });
  test('LOG files are picked as strict UTF-8 with exact unedited bytes', () async {
    final picker = _Picker();
    final bytes = Uint8List.fromList(utf8.encode('\uFEFFline one\r\nline two\r\n'));
    picker.result = FilePickerResult([PlatformFile(name: 'source.LOG', size: bytes.length, readStream: Stream.value(bytes))]);
    final file = await pickCaptureFile(picker: picker, requireCleanup: true);
    expect(file!.format, 'text'); expect(utf8.encode(file.text!), bytes);
    picker.result = FilePickerResult([PlatformFile(name: 'bad.log', size: 1, bytes: Uint8List.fromList([255]))]);
    await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException);
  });
  testWidgets('Log review warns about secrets and does not save automatically', (tester) async {
    final repo = _Repo();
    await _host(tester, repo, page: ImportPage(pickFile: () async => const CaptureFile(name: 'source.LOG', format: 'text', text: 'entry')));
    await _click(tester, 'capture-file');
    expect(find.textContaining('passwords, tokens'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await _click(tester, 'capture-preview');
    expect(repo.last?['format'], 'text'); expect(repo.last?['text'], 'entry'); expect(repo.calls, ['preview']);
  });
  test('CSV and TSV are picked as UTF-8 plain text with exact unedited bytes', () async {
    final picker = _Picker();
    for (final name in ['table.CSV', 'table.tsv']) {
      final bytes = Uint8List.fromList(utf8.encode('\uFEFFname,value\r\nAlice,=1+1\r\n'));
      picker.result = FilePickerResult([PlatformFile(name: name, size: bytes.length, readStream: Stream.value(bytes))]);
      final selected = await pickCaptureFile(picker: picker, requireCleanup: true);
      expect(selected!.format, 'text');
      expect(utf8.encode(selected.text!), bytes);
      expect(selected.pdfBase64, isNull);
    }
    expect(picker.cleanups, 2);
    picker.result = FilePickerResult([PlatformFile(name: 'invalid.csv', size: 1, bytes: Uint8List.fromList([255]))]);
    await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException);
  });
  testWidgets('CSV review makes plain-text handling clear and does not save automatically', (tester) async {
    final repo = _Repo();
    await _host(tester, repo, page: ImportPage(pickFile: () async => const CaptureFile(name: 'table.CSV', format: 'text', text: 'a,b\r\n1,2\r\n')));
    await _click(tester, 'capture-file');
    expect(find.textContaining('not as a table'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await _click(tester, 'capture-preview');
    expect(repo.last?['format'], 'text'); expect(repo.last?['text'], 'a,b\r\n1,2\r\n');
    expect(repo.calls, ['preview']);
  });
  test('Selected UTF-8 Markdown and binary PDF retain exact input bytes', () async {
    final picker = _Picker()..result = FilePickerResult([PlatformFile(name: 'source.MD', size: 12, bytes: Uint8List.fromList(utf8.encode('\uFEFF# Heading')))]);
    final md = await pickCaptureFile(picker: picker, requireCleanup: true);
    expect(md!.format, 'markdown'); expect(md.text, '\uFEFF# Heading'); expect(picker.cleanups, 1);
    final binary = Uint8List.fromList([37, 80, 68, 70, 45, 255, 0, 128]);
    picker.result = FilePickerResult([PlatformFile(name: 'source.pdf', size: binary.length, readStream: Stream.value(binary))]);
    final pdf = await pickCaptureFile(picker: picker, requireCleanup: true);
    expect(pdf!.format, 'pdf'); expect(base64Decode(pdf.pdfBase64!), binary); expect(pdf.text, isNull); expect(picker.cleanups, 2);
  });
  test('Picker cleans up cancellation, unsupported, invalid UTF-8 and read failures', () async {
    final picker = _Picker(); expect(await pickCaptureFile(picker: picker, requireCleanup: true), isNull);
    for (final file in [PlatformFile(name: 'bad.docx', size: 1, bytes: Uint8List(1)), PlatformFile(name: 'bad.txt', size: 1, bytes: Uint8List.fromList([255])), PlatformFile(name: 'bad.txt', size: 1), PlatformFile(name: 'empty.txt', size: 0, bytes: Uint8List(0))]) {
      picker.result = FilePickerResult([file]); await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException);
    }
    picker.error = const FormatException('Provider read error'); await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException); expect(picker.cleanups, 6);
  });
  test('Actual stream bounds cannot be bypassed by false picker size metadata', () async {
    final picker = _Picker()..result = FilePickerResult([PlatformFile(name: 'large.txt', size: 1, readStream: Stream.value(List<int>.filled(2 * 1024 * 1024 + 1, 65)))]);
    await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException); expect(picker.cleanups, 1);
    picker.result = FilePickerResult([PlatformFile(name: 'large.pdf', size: 10 * 1024 * 1024 + 1)]);
    await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException); expect(picker.cleanups, 2);
  });
  test('Unconfirmed picker cleanup blocks file acceptance even on cancel', () async {
    for (final cleared in [false, null]) {
      final picker = _Picker()..cleared = cleared;
      await expectLater(pickCaptureFile(picker: picker, requireCleanup: true), throwsFormatException); expect(picker.cleanups, 1);
    }
  });
  testWidgets('Angle brackets stay plain text; saving requires review and refreshes stale projections', (tester) async {
    final repo = _Repo(); await _host(tester, repo);
    expect(find.byKey(const Key('capture-save')), findsNothing); await _enter(tester, '1 < 2 > 0'); await _click(tester, 'capture-preview');
    expect(repo.calls, ['preview']); expect(repo.last?['format'], 'text'); expect(repo.last?['text'], '1 < 2 > 0');
    final container = ProviderScope.containerOf(tester.element(find.byType(ImportPage)));
    await container.read(itemProvider('cached').future); expect(repo.itemReads, 1);
    await _click(tester, 'capture-save');
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle();
    await container.read(itemProvider('cached').future); expect(repo.itemReads, 2);
    expect(repo.calls, ['preview', 'enqueue', 'run']); expect(repo.approvedDraft?['review_hash'], 'review-binding'); expect(repo.approvedDraft?['choice'], 'save'); expect(find.text('Opened saved'), findsOneWidget);
  });
  testWidgets('Edits invalidate reviewed text and source address; shared drafts are not auto-saved', (tester) async {
    final repo = _Repo(); await _host(tester, repo, page: const ImportPage(initialText: 'https://example.test/shared'));
    expect(repo.calls, isEmpty); await _click(tester, 'capture-preview'); expect(repo.last?['format'], 'text');
    await _enter(tester, 'Changed after review'); expect(find.byKey(const Key('capture-save')), findsNothing);
    await _click(tester, 'capture-preview'); await tester.ensureVisible(find.byKey(const Key('capture-url'))); await tester.enterText(find.byKey(const Key('capture-url')), 'https://example.test/source'); await tester.pumpAndSettle(); expect(find.byKey(const Key('capture-save')), findsNothing);
  });
  testWidgets('Duplicate input exposes explicit reuse or separate-copy choices', (tester) async {
    final repo = _Repo()..duplicate = true; await _host(tester, repo); await _enter(tester, 'Reviewed duplicate'); await _click(tester, 'capture-preview');
    expect(find.byKey(const Key('capture-save')), findsNothing); expect(find.byKey(const Key('capture-keep-copy')), findsOneWidget);
    await _click(tester, 'capture-use-existing'); expect(repo.last?['choice'], 'use_existing'); expect(repo.last?['existing_id'], 'existing'); expect(find.text('Opened saved'), findsOneWidget);
  });
  testWidgets('File selection uses declared format and a changed parser invalidates review', (tester) async {
    final repo = _Repo(); await _host(tester, repo, page: ImportPage(pickFile: () async => const CaptureFile(name: 'source.md', format: 'markdown', text: '# Heading')));
    await _click(tester, 'capture-file'); await _click(tester, 'capture-preview'); expect(repo.last?['format'], 'markdown'); expect(repo.last?['text'], '# Heading');
    await tester.scrollUntilVisible(find.byKey(const Key('capture-format')), -140, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle(); await tester.tap(find.byKey(const Key('capture-format'))); await tester.pumpAndSettle(); await tester.tap(find.text('HTML').last); await tester.pumpAndSettle(); expect(find.byKey(const Key('capture-save')), findsNothing);
  });
  testWidgets('Restore selected source discards only editor changes and requires a fresh preview', (tester) async {
    final repo = _Repo();
    await _host(tester, repo, page: ImportPage(pickFile: () async => const CaptureFile(name: 'source.csv', format: 'text', text: '\uFEFFa,b\r\n1,2\r\n')));
    await _click(tester, 'capture-file'); await _enter(tester, 'Edited source');
    await _click(tester, 'capture-preview');
    expect(find.textContaining('will not also save'), findsOneWidget);
    await _click(tester, 'capture-restore-file');
    expect(find.byKey(const Key('capture-save')), findsNothing);
    await _click(tester, 'capture-preview');
    expect(repo.last?['text'], '\uFEFFa,b\r\n1,2\r\n');
    expect(repo.last?['format'], 'text');
    expect(repo.calls, ['preview', 'preview']);
  });
  testWidgets('Failed preview and save retain input and do not show a false success', (tester) async {
    final repo = _Repo()..failPreview = true; await _host(tester, repo); await _enter(tester, 'Keep my input'); final controller = tester.widget<TextField>(find.byKey(const Key('capture-text'))).controller!; await _click(tester, 'capture-preview');
    expect(find.byKey(const Key('capture-save')), findsNothing); expect(controller.text, 'Keep my input');
    repo.failPreview = false; repo.failCommit = true; await _click(tester, 'capture-preview'); await _click(tester, 'capture-save');
    await tester.tap(find.text('Approve durable save')); await tester.pumpAndSettle(); expect(find.text('Opened saved'), findsNothing);
    expect(controller.text, 'Keep my input'); expect(find.textContaining('check the library before retrying'), findsOneWidget);
  });
  testWidgets('Disposed picker/preview completion never sets state on an unmounted page', (tester) async {
    final pending = Completer<CaptureFile?>(); final repo = _Repo(); await _host(tester, repo, page: ImportPage(pickFile: () => pending.future));
    await tester.tap(find.byKey(const Key('capture-file'))); await tester.pump(); await tester.pumpWidget(const MaterialApp(home: SizedBox())); pending.complete(const CaptureFile(name: 'a.md', format: 'markdown', text: '# Late')); await tester.pumpAndSettle(); expect(tester.takeException(), isNull); expect(repo.calls, isEmpty);
  });
  testWidgets('Review displays the capture mode and supplied unverified source address', (tester) async {
    final repo = _Repo(); await _host(tester, repo); await _enter(tester, 'A local source');
    await tester.enterText(find.byKey(const Key('capture-url')), 'https://example.test/supplied');
    tester.testTextInput.hide(); await tester.pumpAndSettle(); await _click(tester, 'capture-preview');
    expect(find.text('Capture mode: text'), findsOneWidget);
    expect(find.text('Supplied source address (not fetched or verified): https://example.test/supplied'), findsOneWidget);
  });
  testWidgets('Repeated save taps cannot submit the same foreground operation twice', (tester) async {
    final repo = _Repo(); await _host(tester, repo); await _enter(tester, 'Save once'); await _click(tester, 'capture-preview');
    final pending = Completer<Map<String, dynamic>>(); repo.pending = pending;
    final save = find.byKey(const Key('capture-save'));
    await tester.scrollUntilVisible(save, 140, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    await tester.tap(save); await tester.tap(save, warnIfMissed: false); await tester.pump();
    expect(repo.calls, ['preview']);
    await tester.tap(find.text('Approve durable save')); await tester.pump();
    expect(repo.calls, ['preview', 'enqueue', 'run']);
    pending.complete({'status': 'completed', 'result_item_id': 'saved'}); await tester.pumpAndSettle();
    expect(find.text('Opened saved'), findsOneWidget);
  });

  testWidgets('Declining durable storage stages no input', (tester) async {
    final repo = _Repo(); await _host(tester, repo); await _enter(tester, 'Not approved'); await _click(tester, 'capture-preview');
    await _click(tester, 'capture-save'); expect(repo.calls, ['preview']);
    await tester.tap(find.text('Not now')); await tester.pumpAndSettle(); expect(repo.calls, ['preview']);
    expect(find.text('Opened saved'), findsNothing);
  });

}
