import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/repository.dart';

final webPreviewsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  final value = await repo.web('list', {});
  return (value['previews'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

String _approvalTime(Object? value) {
  if (value is! num || value < 0 || value > 253402300799) return 'unavailable';
  return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true).toIso8601String();
}

class WebPreview {
  const WebPreview({required this.id, required this.html, required this.requestedUrl, required this.finalUrl});
  final String id;
  final String html;
  final String requestedUrl;
  final String finalUrl;
}

/// No request or write occurs on opening this page.
class WebCapturePage extends ConsumerStatefulWidget {
  const WebCapturePage({super.key, this.initialUrl = ''});
  final String initialUrl;
  @override ConsumerState<WebCapturePage> createState() => _WebCapturePageState();
}
class _WebCapturePageState extends ConsumerState<WebCapturePage> {
  final _url = TextEditingController();
  Map<String, dynamic>? _step;
  RefractRepository? _repo;
  String? _session;
  String? _error;
  bool _busy = false;
  bool _stageUncertain = false;

  @override void initState() { super.initState(); _url.text = widget.initialUrl; }
  @override void dispose() {
    _url.dispose();
    final id = _session, repo = _repo;
    if (id != null && repo != null && !_busy) { unawaited(repo.web('close', {'id': id}).catchError((_) => <String, dynamic>{})); }
    super.dispose();
  }
  Future<void> _start() async {
    if (_busy || _session != null) return;
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Allow fetch and a retained preview copy?'),
      content: const Text('A request can disclose the address, including its query, to the website, network and configured DNS resolver. No browser cookies or saved credentials are used. If retrieval succeeds, the full HTML response and addresses will be stored locally without app-level encryption until you save or discard the preview. This does not approve a library save. SQLite, WAL, backups and memory are not securely erased.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve preview copy'))]));
    if (approved != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future); _repo = repo;
      final step = await repo.web('start', {'url': _url.text.trim(), 'stage_approved': true});
      _session = step['id'] as String;
      if (mounted) setState(() => _step = step);
    } catch (_) { if (mounted) setState(() => _error = 'Could not start a web session. Check the address and try again.'); }
    finally { if (mounted) { setState(() => _busy = false); } else { await _closeAfterDispose(); } }
  }
  Future<void> _closeAfterDispose() async {
    final id = _session, repo = _repo; _session = null;
    if (id != null && repo != null) { try { await repo.web('close', {'id': id}); } catch (_) {} }
  }
  Future<void> _advance() async {
    final step = _step, repo = _repo, id = _session;
    if (_busy || step == null || repo == null || id == null || step['status'] != 'approval') return;
    setState(() { _busy = true; _error = null; _stageUncertain = false; });
    try {
      final result = await repo.web('advance', {'id': id, 'ticket': step['ticket'], 'request': true,
        'http': step['http'] == true, 'destination_change': step['destination_change'] == true});
      if (result['status'] == 'staged') { _session = null; if (mounted) ref.invalidate(webPreviewsProvider); }
      if (mounted) setState(() => _step = result);
    } catch (_) {
      if (mounted) setState(() { _stageUncertain = true; _error = 'The request or staging could not be confirmed. Check Web previews before retrying; a retained copy may already exist.'; });
    } finally { if (mounted) { setState(() => _busy = false); } else { await _closeAfterDispose(); } }
  }
  Future<void> _act(String action) async {
    final repo = _repo, id = _session;
    if (_busy || repo == null || id == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await repo.web(action, {'id': id});
      if (action == 'close' || result['status'] == 'staged') _session = null;
      if (mounted) {
        if (result['status'] == 'staged') ref.invalidate(webPreviewsProvider);
        setState(() { _step = action == 'close' ? null : result; _stageUncertain = false; });
      }
    } catch (_) { if (mounted) setState(() => _error = 'Could not complete this action. Check Web previews before retrying.'); }
    finally { if (mounted) { setState(() => _busy = false); } else { await _closeAfterDispose(); } }
  }
  @override Widget build(BuildContext context) {
    final step = _step;
    return PopScope(canPop: !_busy, child: Scaffold(appBar: AppBar(title: const Text('Fetch webpage'), automaticallyImplyLeading: !_busy),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Static UTF-8 HTML only, at most 2 MiB. No scripts, cookies, login, embedded resources, automatic retry or library save. Some pages may be incomplete. DNS/private-network restrictions can block a site.'),
        TextField(key: const Key('web-url'), controller: _url, enabled: !_busy && _session == null && step?['status'] != 'staged', decoration: const InputDecoration(labelText: 'Complete HTTP(S) address')),
        if (_session == null && step?['status'] != 'staged') FilledButton(key: const Key('web-start'), onPressed: _busy ? null : _start, child: const Text('Request webpage')),
        if (step?['status'] == 'approval') ...[
          const Text('Confirm this exact request:'), SelectableText('${step!['address']}'),
          if (step['http'] == true) const Text('Warning: HTTP is unencrypted; the address and page can be observed or modified in transit.'),
          if (step['destination_change'] == true) const Text('The redirect changes host or port. Confirm before contacting this destination.'),
          FilledButton(key: const Key('web-advance'), onPressed: _busy ? null : _advance, child: const Text('Confirm and fetch')),
        ],
        if (step?['status'] == 'failed') ...[Text('${step!['message']}'), FilledButton(onPressed: _busy ? null : () => _act('retry'), child: const Text('Request retry'))],
        if (_stageUncertain) OutlinedButton(onPressed: _busy ? null : () => _act('stage'), child: const Text('Retry staging completed response')),
        if (_session != null) TextButton(onPressed: _busy ? null : () => _act('close'), child: const Text('Close session')),
        if (step?['status'] == 'staged') const Text('Preview copy stored. It is not a library save. Open Web previews to review or discard it.'),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _busy ? null : () => context.push('/web/previews'), child: const Text('Open Web previews')),
      ])));
  }
}

class WebPreviewsPage extends ConsumerStatefulWidget {
  const WebPreviewsPage({super.key});
  @override ConsumerState<WebPreviewsPage> createState() => _WebPreviewsPageState();
}
class _WebPreviewsPageState extends ConsumerState<WebPreviewsPage> {
  String? _busy, _error;
  Future<void> _act(Map<String, dynamic> preview, bool discard) async {
    final id = preview['id'] as String;
    if (_busy != null) return;
    if (discard) {
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Discard this web preview copy?'),
        content: const Text('This removes only the staged copy, not library originals or approved jobs. Open editors, SQLite/WAL, backups and caches may retain copies; this is not secure erasure.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep copy')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard copy'))]));
      if (approved != true || !mounted) return;
    }
    setState(() { _busy = id; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      if (discard) { await repo.web('delete', {'id': id}); if (mounted) ref.invalidate(webPreviewsProvider); }
      else {
        final value = await repo.web('get', {'id': id});
        if (mounted) context.push('/import', extra: WebPreview(id: id, html: value['html'] as String, requestedUrl: value['requested_url'] as String, finalUrl: value['final_url'] as String));
      }
    } catch (_) { if (mounted) setState(() => _error = 'Preview could not be accessed or removed. It remains listed; retry or discard it explicitly.'); }
    finally { if (mounted) setState(() => _busy = null); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Web previews'), actions: [IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(webPreviewsProvider), icon: const Icon(Icons.refresh))]),
    body: ref.watch(webPreviewsProvider).when(loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Web previews unavailable.')),
      data: (items) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Explicitly approved fetched copies stay here until saved or discarded. They are not library originals, have no app-level encryption and are not securely erased. Opening a copy does not save it.'),
        if (_error != null) Text(_error!), if (items.isEmpty) const Text('No web previews.'),
        for (final item in items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText('Requested: ${item['requested_url']}'), SelectableText('Final address: ${item['final_url']}'),
          Text('${item['byte_len']} bytes · approval on device ${_approvalTime(item['consent_ts'])} (not publication time)'),
          Wrap(spacing: 8, children: [FilledButton(onPressed: _busy == null ? () => _act(item, false) : null, child: const Text('Review preview')),
            TextButton(onPressed: _busy == null ? () => _act(item, true) : null, child: const Text('Discard preview'))]),
        ]))),
      ])));
}
