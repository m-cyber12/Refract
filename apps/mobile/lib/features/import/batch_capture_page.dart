import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'capture_file.dart';

/// Process-local queue: never writes or previews content without user action.
class BatchInbox extends ChangeNotifier {
  static final instance = BatchInbox();
  final List<BatchEntry> _entries = [];
  List<BatchEntry> get entries => List.unmodifiable(_entries);
  int get byteLength => _entries.fold(0, (sum, item) => sum + item.byteLength);
  void add(List<BatchEntry> items) {
    if (items.isEmpty || _entries.length + items.length > 16 ||
        items.any((item) => item.byteLength <= 0) ||
        byteLength + items.fold<int>(0, (sum, item) => sum + item.byteLength) > 24 * 1024 * 1024) {
      throw const FormatException('Batch is full or invalid. Nothing was added.');
    }
    _entries.addAll(items); notifyListeners();
  }
  void remove(BatchEntry item) { _entries.remove(item); notifyListeners(); }
  void removeSelected(List<BatchEntry> selected) {
    // Remove at most one occurrence for each snapshotted entry.
    for (final item in selected) { _entries.remove(item); }
    notifyListeners();
  }
}

class BatchCapturePage extends StatefulWidget {
  const BatchCapturePage({super.key, this.inbox, this.pick});
  final BatchInbox? inbox;
  final Future<List<BatchEntry>?> Function(int remainingCount, int remainingBytes)? pick;
  @override State<BatchCapturePage> createState() => _BatchCapturePageState();
}
class _BatchCapturePageState extends State<BatchCapturePage> {
  bool _busy = false;
  bool _confirming = false;
  String? _error;
  BatchInbox get _inbox => widget.inbox ?? BatchInbox.instance;
  Future<void> _select() async {
    if (_busy || _confirming || _inbox.entries.length >= 16 || _inbox.byteLength >= 24 * 1024 * 1024) return;
    setState(() { _busy = true; _error = null; });
    try {
      final count = 16 - _inbox.entries.length;
      final bytes = 24 * 1024 * 1024 - _inbox.byteLength;
      final selected = await (widget.pick?.call(count, bytes) ?? pickCaptureFiles(maxCount: count, maxBytes: bytes));
      if (!mounted || selected == null) return;
      _inbox.add(selected);
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _discardOne(BatchEntry item) async {
    if (_busy || _confirming || !_inbox.entries.contains(item)) return;
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Discard this batch draft?'),
        content: const Text('Remove this temporary draft from the list. Saved library originals and approved jobs are not deleted. Open editors, memory and provider caches can retain copies; this is not secure erasure.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep draft')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard draft'))]));
      if (confirmed == true && mounted && _inbox.entries.contains(item)) _inbox.remove(item);
    } finally { if (mounted) setState(() => _confirming = false); }
  }
  Future<void> _discardAll() async {
    if (_busy || _confirming || _inbox.entries.isEmpty) return;
    final selected = _inbox.entries;
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Discard these batch drafts?'),
        content: Text('Remove ${selected.length} temporary drafts from this list. Saved library originals and approved jobs are not deleted. Open editors, memory and provider caches can retain copies; this is not secure erasure.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep drafts')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard drafts'))]));
      if (confirmed == true && mounted) _inbox.removeSelected(selected);
    } finally { if (mounted) setState(() => _confirming = false); }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Batch drafts'), automaticallyImplyLeading: !_busy),
    body: AnimatedBuilder(animation: _inbox, builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Select up to 16 files / 24 MiB in total. Drafts live only in process memory and can be lost if the app stops. Providers may download or cache files before limits are checked. Each item needs its own preview and separate save approval; nothing is saved automatically.'),
      const Text('Saving an item does not remove it from this temporary list. Explicitly discard it when finished. Editing an item does not change its queued original. Discard is not secure erasure of memory or provider caches.'),
      if (_error != null) SelectableText(_error!),
      Text('${_inbox.entries.length} drafts · ${_inbox.byteLength} bytes'),
      FilledButton(key: const Key('batch-select'), onPressed: _busy || _confirming || _inbox.entries.length >= 16 || _inbox.byteLength >= 24 * 1024 * 1024 ? null : _select, child: const Text('Select files')),
      if (_inbox.entries.isNotEmpty) TextButton(key: const Key('batch-discard-all'), onPressed: _busy || _confirming ? null : _discardAll, child: const Text('Discard all batch drafts')),
      if (_busy) const LinearProgressIndicator(),
      for (final item in _inbox.entries) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.file.name), Text('${item.file.format} · ${item.byteLength} bytes · not saved by batch selection'),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: _busy || _confirming ? null : () => context.push('/import', extra: item), child: const Text('Review this file')),
          TextButton(onPressed: _busy || _confirming ? null : () => _discardOne(item), child: const Text('Discard batch draft')),
        ]),
      ]))),
    ]))));
}
