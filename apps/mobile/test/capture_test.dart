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
import 'package:refract/features/import/capture_file.dart';
import 'package:refract/features/import/import_page.dart';

class _Repo implements RefractRepository {
  final calls = <String>[];
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
  await tester.scrollUntilVisible(find.byKey(const Key('capture-text')), -140, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('capture-text')), text);
  tester.testTextInput.hide(); await tester.pumpAndSettle();
}
void main() {
  test('URL references retain their distinct not-fetched source kind', () {
    expect(sourceTypeFromString('url_reference'), SourceType.urlReference);
    expect(sourceTypeLabel(SourceType.urlReference), contains('not fetched'));
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
  testWidgets('Review displays the chosen parser and supplied unverified source address', (tester) async {
    final repo = _Repo(); await _host(tester, repo); await _enter(tester, 'A local source');
    await tester.enterText(find.byKey(const Key('capture-url')), 'https://example.test/supplied');
    tester.testTextInput.hide(); await tester.pumpAndSettle(); await _click(tester, 'capture-preview');
    expect(find.text('Chosen parser: text'), findsOneWidget);
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
