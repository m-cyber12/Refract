import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';

/// Runs with the actual host Rust library, not a fake repository. The regular
/// widget suite skips this until CI builds the host core and sets its path.
void main() {
  final enabled = Platform.isLinux && Platform.environment.containsKey('REFRACT_NATIVE_LIBRARY');
  test('Real web ABI keeps sessions across workers and requires approval before DNS', () async {
    final dir = await Directory.systemTemp.createTemp('refract-native-web-');
    final repo = RefractRepository.openLocal('${dir.path}/library.db');
    try {
      await expectLater(repo.web('start', {'url': 'https://public.com/', 'stage_approved': false}), throwsA(anything));
      await expectLater(repo.web('start', {'url': 'http://127.0.0.1/', 'stage_approved': true}), throwsA(anything));
      final session = await repo.web('start', {'url': 'http://public.com/', 'stage_approved': true});
      expect(session['http'], true); expect((await repo.web('list', {}))['previews'], isEmpty);
      await expectLater(repo.web('advance', {'id': session['id'], 'ticket': session['ticket'], 'request': true, 'http': false, 'destination_change': false}), throwsA(anything));
      expect((await repo.web('close', {'id': session['id']}))['status'], 'closed');
      expect(repo.listItems(), isEmpty);
    } finally { repo.dispose(); await dir.delete(recursive: true); }
  }, skip: enabled ? false : 'Requires CI-built host library: REFRACT_NATIVE_LIBRARY');
  test('Actual worker owns its handle; UI connection sees commits, duplicates and binary PDF after restart', () async {
    final dir = await Directory.systemTemp.createTemp('refract-native-capture-');
    RefractRepository? repo;
    try {
      final path = '${dir.path}/library.db'; repo = RefractRepository.openLocal(path);
      final draft = <String, dynamic>{'format': 'markdown', 'text': '# Native worker\n\nPreserved source 1 < 2 > 0'};
      final preview = await repo.capture('preview', draft);
      expect(repo.listItems(), isEmpty);
      final result = await repo.capture('commit', {...draft, 'review_hash': preview['review_hash']});
      final id = (result['item'] as Map)['id'] as String;
      expect(repo.getItem(id)!.sourceType, SourceType.markdown);
      expect(repo.search('Preserved').single.id, id);
      final again = await repo.capture('preview', draft); expect((again['duplicate'] as Map)['id'], id);
      await expectLater(repo.capture('commit', {...draft, 'review_hash': again['review_hash']}), throwsA(anything));
      final reused = await repo.capture('commit', {...draft, 'review_hash': again['review_hash'], 'choice': 'use_existing', 'existing_id': id});
      expect(reused['reused_existing'], true); expect(repo.listItems().length, 1);
      final bytes = await File('../../shared/fixtures/capture/compressed-text.pdf').readAsBytes();
      final pdf = <String, dynamic>{'format': 'pdf', 'pdf_base64': base64Encode(bytes)};
      final pdfPreview = await repo.capture('preview', pdf);
      expect(pdfPreview['excerpt'], contains('Binary PDF capture regression'));
      final saved = await repo.capture('commit', {...pdf, 'review_hash': pdfPreview['review_hash']});
      final pdfId = (saved['item'] as Map)['id'] as String;
      final queuedInput = <String, dynamic>{'format': 'text', 'text': 'Approved durable worker source'};
      final queuePreview = await repo.capture('preview', queuedInput);
      final queued = await repo.capture('enqueue', {'id': 'native-durable-job-123456', 'persist_approved': true,
        'draft': {...queuedInput, 'review_hash': queuePreview['review_hash'], 'choice': 'keep_copy'}});
      expect(queued['status'], 'queued'); expect(repo.listItems().length, 2);
      repo.dispose(); repo = RefractRepository.openLocal(path);
      final jobs = await repo.capture('jobs', {'limit': 100, 'offset': 0}); expect((jobs['jobs'] as List).single['status'], 'queued');
      final completed = await repo.capture('run', {'id': queued['id']}); expect(completed['status'], 'completed');
      final repeated = await repo.capture('run', {'id': queued['id']}); expect(repeated['result_item_id'], completed['result_item_id']);
      expect(repo.listItems().length, 3); expect(repo.getItem(pdfId)!.sourceType, SourceType.pdf);
      expect(await File('${dir.path}/library.blobs/$pdfId.original').readAsBytes(), bytes);
    } finally { repo?.dispose(); await dir.delete(recursive: true); }
  }, skip: enabled ? false : 'Requires CI-built host library: REFRACT_NATIVE_LIBRARY');
}
