import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';

String _utc(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toIso8601String().substring(0, 10);

class RecallPage extends ConsumerStatefulWidget {
  const RecallPage({this.contextItemId, super.key});
  final String? contextItemId;

  @override
  ConsumerState<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends ConsumerState<RecallPage> {
  final _query = TextEditingController();
  final _url = TextEditingController();
  final _author = TextEditingController();
  final _entity = TextEditingController();
  final _selected = <String>{};
  String _mode = 'find';
  String? _type;
  String? _project;
  DateTime? _after;
  DateTime? _before;
  String? _request;
  bool _rebuilding = false;

  @override
  void initState() {
    super.initState();
    if (widget.contextItemId != null) {
      _mode = 'connections';
      _request = jsonEncode({'query': '', 'mode': _mode, 'context_item_id': widget.contextItemId});
    }
  }

  @override
  void dispose() {
    for (final c in [_query, _url, _author, _entity]) { c.dispose(); }
    super.dispose();
  }

  void _run() {
    if (['summarize', 'compare'].contains(_mode) && _selected.length < (_mode == 'compare' ? 2 : 1)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Find documents first, then select sources using their checkboxes. Comparison needs two sources.')));
      return;
    }
    final selectionMode = ['summarize', 'compare'].contains(_mode);
    final request = jsonEncode({
      'query': _query.text.trim(), 'mode': _mode, 'limit': 50,
      if (selectionMode) 'item_ids': _selected.toList(),
      if (_type != null) 'source_type': _type,
      if (_project != null) 'project_id': _project,
      if (_url.text.trim().isNotEmpty) 'source_url': _url.text.trim(),
      if (_author.text.trim().isNotEmpty) 'author': _author.text.trim(),
      if (_entity.text.trim().isNotEmpty) 'entity': _entity.text.trim(),
      if (_after != null) 'captured_after': DateTime.utc(_after!.year, _after!.month, _after!.day).millisecondsSinceEpoch ~/ 1000,
      if (_before != null) 'captured_before': DateTime.utc(_before!.year, _before!.month, _before!.day, 23, 59, 59).millisecondsSinceEpoch ~/ 1000,
      if (widget.contextItemId != null && !selectionMode) 'context_item_id': widget.contextItemId,
    });
    ref.invalidate(recallProvider(request));
    setState(() => _request = request);
  }

  Future<void> _date(bool after) async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(1970), lastDate: DateTime(2200));
    if (date != null && mounted) setState(() { if (after) { _after = date; } else { _before = date; } });
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final count = repo.rebuildRecallIndex();
      ref.invalidate(recallProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rebuilt the local derived index for $count source(s). Originals unchanged.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Index rebuild failed: $e')));
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _request == null ? null : ref.watch(recallProvider(_request!));
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('REFRACT RECALL'), actions: [
        IconButton(tooltip: 'Rebuild local derived index', onPressed: _rebuilding ? null : _rebuild, icon: const Icon(Icons.manage_search)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('MEMORY ASSISTANT · local & extractive', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Describe what you remember. Results include source passages, not invented answers. Concept matching is dictionary-based; no neural model is running.'),
        if (widget.contextItemId != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Reading context: ${widget.contextItemId}. The current document is excluded from related suggestions.')),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('recall-query'), controller: _query, maxLines: 2, decoration: const InputDecoration(labelText: 'What do you remember?', hintText: 'Find that article about AI privacy', border: OutlineInputBorder()), onSubmitted: (_) => _run()),
        const SizedBox(height: 8),
        Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String>(value: _mode, onChanged: (v) { if (v != null) setState(() => _mode = v); }, items: const [
            DropdownMenuItem(value: 'find', child: Text('Find sources')),
            DropdownMenuItem(value: 'answer', child: Text('Evidence for a question')),
            DropdownMenuItem(value: 'summarize', child: Text('Extract selected sources')),
            DropdownMenuItem(value: 'compare', child: Text('Compare selected sources')),
            DropdownMenuItem(value: 'connections', child: Text('Explain connections')),
            DropdownMenuItem(value: 'timeline', child: Text('Source-backed timeline')),
          ]),
          FilledButton.icon(key: const ValueKey('recall-run'), onPressed: _rebuilding ? null : _run, icon: const Icon(Icons.search), label: const Text('Recall')),
        ]),
        ExpansionTile(title: const Text('Metadata & capture-date filters'), tilePadding: EdgeInsets.zero, children: [
          DropdownButton<String>(value: _type ?? '', isExpanded: true, onChanged: (v) => setState(() => _type = v == '' ? null : v), items: const [
            DropdownMenuItem(value: '', child: Text('All source types')),
            DropdownMenuItem(value: 'pdf', child: Text('PDF')),
            DropdownMenuItem(value: 'text', child: Text('Text')),
            DropdownMenuItem(value: 'html', child: Text('HTML')),
            DropdownMenuItem(value: 'url', child: Text('URL')),
            DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
            DropdownMenuItem(value: 'shared_text', child: Text('Shared text')),
            DropdownMenuItem(value: 'file', child: Text('File')),
          ]),
          projects.when(
            data: (values) => DropdownButton<String>(value: values.any((p) => p.id == _project) ? _project : '', isExpanded: true, onChanged: (v) => setState(() => _project = v == '' ? null : v), items: [
              const DropdownMenuItem(value: '', child: Text('All Project Spaces')),
              ...values.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
            ]),
            loading: () => const LinearProgressIndicator(), error: (e, _) => Text('Project filter unavailable: $e'),
          ),
          TextField(controller: _url, decoration: const InputDecoration(labelText: 'Exact original source URL')),
          TextField(controller: _author, decoration: const InputDecoration(labelText: 'Author (exact, case-insensitive)')),
          TextField(controller: _entity, decoration: const InputDecoration(labelText: 'Entity candidate (exact, case-insensitive)')),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: () => _date(true), child: Text(_after == null ? 'Captured after…' : 'From ${_utc(_after!.millisecondsSinceEpoch ~/ 1000)}')),
            TextButton(onPressed: () => _date(false), child: Text(_before == null ? 'Captured before…' : 'To ${_utc(_before!.millisecondsSinceEpoch ~/ 1000)}')),
            TextButton(onPressed: () => setState(() { _after = null; _before = null; _type = null; _project = null; _url.clear(); _author.clear(); _entity.clear(); }), child: const Text('Clear filters')),
          ]),
          const Text('These filters refer to capture time, not publication dates or extracted deadlines.'),
        ]),
        if (_selected.isNotEmpty) Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [Text('${_selected.length}/20 sources selected'), TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear selection'))]),
        if (_rebuilding) const LinearProgressIndicator(),
        if (result == null) const Padding(padding: EdgeInsets.all(24), child: Text('Try “Where was the PDF about encryption?” or “What did I save about SQLite?”'))
        else result.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Recall could not complete: $e. Originals have not been changed.')),
          data: (response) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(response.answer), const SizedBox(height: 8),
              Text('${response.answerKind} · model used: ${response.modelUsed} · ${response.scannedItems} source(s) scanned', style: Theme.of(context).textTheme.bodySmall),
            ]))),
            ...response.hits.map(_hit),
            if (response.connections.isNotEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Stored connections — suggestions / user assertions')),
            ...response.connections.map((r) => Card(child: ListTile(
              title: Text(r.kind.replaceAll('_', ' ')), subtitle: Text('${r.basis}\nHeuristic score ${r.confidence.toStringAsFixed(2)} — not a truth probability'),
              onTap: () => context.push('/reader/${Uri.encodeComponent(r.targetItemId)}'),
            ))),
            ...response.timeline.map((e) => ListTile(
              leading: const Icon(Icons.schedule), title: Text(e.title), subtitle: Text('${_utc(e.ts)} UTC · ${e.timeKind}${e.note == null ? '' : '\n${e.note}'}'),
              onTap: () => context.push('/reader/${Uri.encodeComponent(e.itemId)}'),
            )),
            ExpansionTile(title: const Text('Limitations & evidence quality'), children: response.limitations.map((s) => Padding(padding: const EdgeInsets.all(8), child: Text(s))).toList()),
          ]),
        ),
      ]),
    );
  }

  Widget _hit(RecallHit hit) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    CheckboxListTile(contentPadding: EdgeInsets.zero, value: _selected.contains(hit.itemId), onChanged: (selected) => setState(() {
      if (selected == true && _selected.length < 20) _selected.add(hit.itemId);
      if (selected == false) _selected.remove(hit.itemId);
    }), title: Text(hit.title), subtitle: Text('${hit.sourceType} · captured ${_utc(hit.capturedTs)} UTC · rank score ${hit.score.toStringAsFixed(3)}')),
    Text(hit.evidence.kind == 'metadata_only' ? 'METADATA ONLY — no supporting passage' : hit.evidence.kind == 'context_excerpt' ? 'CONTEXT EXCERPT — not a matching answer passage' : 'VERBATIM SOURCE EXCERPT · block ${hit.evidence.blockIdx}'),
    const SizedBox(height: 8), SelectableText(hit.evidence.quote),
    if (hit.evidence.sourceUrl != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(hit.evidence.sourceUrl!, style: Theme.of(context).textTheme.bodySmall)),
    TextButton.icon(onPressed: () => context.push('/reader/${Uri.encodeComponent(hit.itemId)}${hit.evidence.blockIdx == null ? '' : '?block=${hit.evidence.blockIdx}'}'), icon: const Icon(Icons.article_outlined), label: const Text('Open supporting source')),
    ...hit.supportingPassages.map((e) => ListTile(contentPadding: EdgeInsets.zero, title: SelectableText(e.quote), subtitle: Text('Extractive summary citation · block ${e.blockIdx}'), onTap: () => context.push('/reader/${Uri.encodeComponent(e.itemId)}?block=${e.blockIdx}'))),
    ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Why this matched'), children: hit.reasons.map((r) => ListTile(dense: true, title: Text(r))).toList()),
  ])));
}
