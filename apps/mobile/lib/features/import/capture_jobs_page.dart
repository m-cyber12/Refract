import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/repository.dart';
import '../../core/library_refresh.dart';
import '../../core/device_time.dart';

final captureJobsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  final result = await repo.capture('jobs', {'limit': 100, 'offset': 0});
  return (result['jobs'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
});

/// Explicit foreground recovery. Merely opening this page never reparses input.
class CaptureJobsPage extends ConsumerStatefulWidget {
  const CaptureJobsPage({super.key});
  @override ConsumerState<CaptureJobsPage> createState() => _CaptureJobsPageState();
}
class _CaptureJobsPageState extends ConsumerState<CaptureJobsPage> {
  String? _busy;
  String? _error;
  bool _confirming = false;
  Future<void> _act(String id, String action) async {
    if (_busy != null || _confirming) return;
    if (action == 'cancel') {
      _confirming = true;
      bool? approved;
      try { approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Cancel this pending save?'),
        content: const Text('Remove its active staged input and any unreferenced original owned by this job. Completed library originals are never deleted here. SQLite/WAL, backups and caches are not securely erased.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep job')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel pending save'))])); }
      finally { _confirming = false; }
      if (approved != true || !mounted) return;
    }
    setState(() { _busy = id; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final job = await repo.capture(action, {'id': id});
      if (!mounted) return;
      refreshLibrary(ref); ref.invalidate(captureJobsProvider);
      if (job['status'] == 'failed') setState(() => _error = job['error'] as String? ?? 'Capture failed; input is retained for retry or cancellation.');
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) { ref.invalidate(captureJobsProvider); setState(() => _busy = null); } }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Capture jobs'), actions: [IconButton(tooltip: 'Refresh job states', onPressed: () => ref.invalidate(captureJobsProvider), icon: const Icon(Icons.refresh))]),
    body: ref.watch(captureJobsProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Job history unavailable: $e')),
      data: (jobs) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Only approved saves are staged. Pending originals are stored locally without app-level encryption. No automatic startup retry or OS background service. Processing can also mean interrupted: Resume checks that no live worker still owns the job.'),
        const Text('Up to 100 jobs shown, unresolved first. Failed jobs keep their approved input until completed or cancelled. Cancel is available only when no worker is active; it cannot interrupt native parsing.'),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SelectableText(_error!)),
        if (jobs.isEmpty) const Text('No durable capture jobs.'),
        for (final job in jobs) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${switch (job['format']) { 'pdf_original' => 'PDF original only (no extraction)', 'pdf' => 'PDF (capture mode not recorded)', final value => value }} · ${job['status']} · attempts ${job['attempts']}'),
          SelectableText('Job ${job['id']}'),
          Text('Approved on this device: ${formatDeviceTime(job['created_ts'])} (not a source publication date)'),
          if (job['error'] != null) Text(job['error'] as String),
          if (_busy == job['id']) const LinearProgressIndicator(),
          if (job['status'] == 'completed') TextButton(onPressed: () => context.push('/reader/${Uri.encodeComponent(job['result_item_id'] as String)}'), child: const Text('Open saved source')),
          if (job['status'] != 'completed' && job['status'] != 'cancelled') Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy == null ? () => _act(job['id'] as String, 'run') : null, child: Text(job['status'] == 'processing' ? 'Resume if interrupted' : 'Run / retry')),
            TextButton(onPressed: _busy == null ? () => _act(job['id'] as String, 'cancel') : null, child: const Text('Cancel pending save'))]),
        ]))),
      ])),
  );
}
