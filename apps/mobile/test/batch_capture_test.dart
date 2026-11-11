import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/features/import/batch_capture_page.dart';
import 'package:refract/features/import/capture_file.dart';

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
    picker.cleared = false;
    await expectLater(pickCaptureFiles(picker: picker, requireCleanup: true), throwsFormatException);
    expect(picker.cleanups, 5);
  });
  testWidgets('Batch reviews files individually and keeps drafts until explicit discard', (tester) async {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    final one = BatchEntry(file: const CaptureFile(name: 'a.txt', format: 'text', text: 'one'), byteLength: 3);
    final two = BatchEntry(file: const CaptureFile(name: 'b.txt', format: 'text', text: 'two'), byteLength: 3);
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
  test('Batch inbox checks count and byte budgets even for injected results', () {
    final inbox = BatchInbox(); addTearDown(inbox.dispose);
    final entry = BatchEntry(file: const CaptureFile(name: 'a.txt', format: 'text', text: 'a'), byteLength: 1);
    inbox.add(List.filled(16, entry));
    expect(() => inbox.add([entry]), throwsFormatException); expect(inbox.entries.length, 16);
    final another = BatchInbox(); addTearDown(another.dispose);
    expect(() => another.add([BatchEntry(file: entry.file, byteLength: 24 * 1024 * 1024 + 1)]), throwsFormatException);
    expect(another.entries, isEmpty);
  });
}
