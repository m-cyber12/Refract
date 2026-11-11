import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/library_refresh.dart';
import '../../core/repository.dart';
import '../../core/share_intent.dart';
import 'capture_file.dart';
import 'capture_jobs_page.dart';
import 'web_capture_page.dart';

/// Explicit local review/save; webpage fetching is a separate consented flow.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.pickFile, this.initialText = '', this.initialFile, this.sharedDraftId, this.sharedDraftStaged = false, this.webPreview});
  final Future<CaptureFile?> Function()? pickFile;
  final String initialText;
  final CaptureFile? initialFile;
  final String? sharedDraftId;
  final bool sharedDraftStaged;
  final WebPreview? webPreview;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}
class _ImportPageState extends ConsumerState<ImportPage> {
  final _text = TextEditingController();
  final _url = TextEditingController();
  String _format = 'text';
  CaptureFile? _file;
  bool _busy = false;
  String? _saveToken;
  String? _error;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _reviewedInput;

  @override
  void initState() { super.initState(); _file = widget.initialFile; _format = widget.webPreview != null ? 'html' : _file?.format ?? 'text'; _text.text = widget.webPreview?.html ?? _file?.text ?? widget.initialText; _url.text = widget.webPreview?.finalUrl ?? ''; _text.addListener(_changed); _url.addListener(_changed); }
  void _changed() {
    if (mounted) setState(() { _preview = null; _reviewedInput = null; _saveToken = null; _error = null; });
  }
  @override
  void dispose() { _text.dispose(); _url.dispose(); super.dispose(); }

  String _webAddress() {
    if (_format == 'url_reference') return _text.text.trim();
    if (_url.text.trim().isNotEmpty) return _url.text.trim();
    final candidate = _text.text.trim();
    final uri = Uri.tryParse(candidate);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty && !candidate.contains(RegExp(r'\s')) ? candidate : '';
  }

  Future<void> _chooseFile() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final file = await (widget.pickFile?.call() ?? pickCaptureFile());
      if (!mounted || file == null) return;
      _text.text = file.text ?? '';
      setState(() { _file = file; _format = file.format; _preview = null; _reviewedInput = null; _saveToken = null; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Map<String, dynamic> _input() {
    if (_format == 'pdf' && _file?.pdfBase64 == null) throw const FormatException('Choose a PDF file first.');
    return {'format': _format,
      if (_format == 'pdf') 'pdf_base64': _file!.pdfBase64 else 'text': _text.text,
      if (_format != 'url_reference' && _url.text.trim().isNotEmpty) 'source_url': _url.text.trim()};
  }
  Future<void> _review() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _preview = null; _reviewedInput = null; _saveToken = null; });
    try {
      final input = _input();
      final repo = await ref.read(bootstrapProvider.future);
      final preview = await repo.capture('preview', input);
      if (mounted) setState(() { _preview = preview; _reviewedInput = input; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _save(String choice) async {
    if (_busy) return;
    final preview = _preview;
    final input = _reviewedInput;
    if (preview == null || input == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final draft = {...input, 'review_hash': preview['review_hash'], 'choice': choice,
        if (choice == 'use_existing') 'existing_id': (preview['duplicate'] as Map)['id']};
      late Map<String, dynamic> result;
      if (choice == 'use_existing') {
        result = await repo.capture('commit', draft);
      } else {
        if (!mounted) return;
        final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Persist this approved save for recovery?'),
          content: const Text('The complete approved input will be staged in local SQLite without app-level encryption, then processed. It survives restart until completed or cancelled in Capture jobs. Completion/cancellation removes the active staged payload, not secure erasure of WAL, free pages or backups. Unreviewed previews are not saved.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve durable save'))]));
        if (approved != true || !mounted) return;
        _saveToken ??= base64UrlEncode(List<int>.generate(24, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
        final staged = await repo.capture('enqueue', {'id': _saveToken, 'draft': draft, 'persist_approved': true});
        final job = await repo.capture('run', {'id': staged['id']});
        if (mounted) ref.invalidate(captureJobsProvider);
        if (job['status'] != 'completed') throw StateError('${job['error'] ?? 'Capture is not complete'}. Open Capture jobs to retry or cancel.');
        result = {'item': {'id': job['result_item_id']}, 'reused_existing': false};
      }
      if (!mounted) return;
      final handoffRemoved = widget.sharedDraftId == null || await ShareIntentChannel.instance.remove(widget.sharedDraftId!);
      var webCleanup = '';
      final web = widget.webPreview;
      if (web != null) {
        // Never silently discard the fetched original when edited content or its
        // source binding was saved. The user can review/discard that copy later.
        if (input['format'] != 'html' || input['text'] != web.html || input['source_url'] != web.finalUrl) {
          webCleanup = ' The original web preview remains in Web previews because this capture was edited.';
        } else {
          try { await repo.web('delete', {'id': web.id}); if (mounted) ref.invalidate(webPreviewsProvider); }
          catch (_) { webCleanup = ' Web preview cleanup was not confirmed; check Web previews.'; }
        }
      }
      if (!mounted) return;
      refreshLibrary(ref);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['reused_existing'] == true
        ? 'Opened existing copy; no new original was saved.${handoffRemoved ? '' : ' Handoff cleanup failed; its copy is still in Shared drafts.'}$webCleanup' : 'Saved to your local library.${handoffRemoved ? '' : ' Handoff cleanup failed; its copy is still in Shared drafts.'}$webCleanup')));
      context.go('/reader/${Uri.encodeComponent((result['item'] as Map)['id'] as String)}');
    } catch (e) {
      if (mounted) setState(() => _error = '$e\nYour input is still here. If a save was interrupted, check the library before retrying.');
    } finally { if (mounted) { ref.invalidate(captureJobsProvider); setState(() => _busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final duplicate = preview?['duplicate'] as Map?;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('Capture locally'), automaticallyImplyLeading: !_busy, actions: [IconButton(tooltip: 'Capture jobs', onPressed: _busy ? null : () => context.push('/capture/jobs'), icon: const Icon(Icons.pending_actions))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.sharedDraftId != null) Text(widget.sharedDraftStaged ? 'iOS handoff copy: already staged with consent, not yet a library original. It remains until saved/discarded, including after restart. Returning does not save editor changes. No app-level encryption or secure-erasure guarantee.' : 'Shared draft: not saved. Returning keeps the original shared input in memory, not edits. Other shares never replace this draft. It can be lost if the OS ends this process.'),
        if (widget.webPreview != null) ...[const Text('Consented web handoff copy: not yet a library original. Editing keeps the fetched copy in Web previews after save. Only the final address is bound to the library capture; the requested address is shown here separately.'), SelectableText('Requested address: ${widget.webPreview!.requestedUrl}')],
        const Text('Choose a format. Preview extracts text locally without saving content. URL references remain addresses only; fetching is a separate explicitly approved action.'),
        OutlinedButton.icon(key: const Key('web-open'), onPressed: _busy ? null : () => context.push('/web/fetch', extra: _webAddress()), icon: const Icon(Icons.public), label: const Text('Fetch a webpage with consent')),
        TextButton(onPressed: _busy ? null : () => context.push('/web/previews'), child: const Text('Web previews')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('capture-format'), initialValue: _format, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Format'),
          items: const [DropdownMenuItem(value: 'text', child: Text('Plain text')),
            DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
            DropdownMenuItem(value: 'html', child: Text('HTML')),
            DropdownMenuItem(value: 'url_reference', child: Text('URL reference (not fetched)')),
            DropdownMenuItem(value: 'pdf', child: Text('PDF file (text extraction, no OCR)'))],
          onChanged: _busy ? null : (value) { if (value != null) setState(() { _format = value; _preview = null; _reviewedInput = null; _saveToken = null; _error = null; }); }),
        const SizedBox(height: 8),
        const Text('A selected provider may download/cache a file before app size checks. Mobile picker cleanup is requested, not secure erasure or control of provider caches.'),
        OutlinedButton.icon(key: const Key('capture-file'), onPressed: _busy ? null : _chooseFile,
          icon: const Icon(Icons.file_open_outlined), label: const Text('Choose one file · TXT / CSV / TSV / MD / HTML / PDF')),
        if (_file != null) Text('Loaded: ${_file!.name}. The selected source file is not changed. Text edits below become the captured original.'),
        if (_file != null && RegExp(r'\.(csv|tsv)$', caseSensitive: false).hasMatch(_file!.name))
          const Text('CSV/TSV is captured as plain UTF-8 text, not as a table. Column structure, formulas and spreadsheet formatting are not interpreted or validated. Original bytes are retained only if the text is not edited.'),
        if (_format != 'pdf') TextField(key: const Key('capture-text'), controller: _text, enabled: !_busy,
          minLines: 4, maxLines: 10, decoration: InputDecoration(labelText: _format == 'url_reference' ? 'Complete HTTP(S) address' : 'Original input', alignLabelWithHint: true)),
        if (_format != 'url_reference') TextField(key: const Key('capture-url'), controller: _url, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Source HTTP(S) URL (optional; editing does not fetch)')),
        const SizedBox(height: 12),
        const Text('Limits: text 2 MiB; PDF 10 MiB / 200 pages / 16 MiB decoded page content; extracted text 2 MiB / 20,000 blocks. No app-level encryption. Unreviewed drafts are temporary. Approved saves can be staged for explicit recovery in Capture jobs. Editing this draft does not cancel older approved jobs.'),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('capture-preview'), onPressed: _busy ? null : _review,
          icon: _busy && _preview == null ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.preview_outlined),
          label: Text(_busy ? 'Working locally…' : 'Preview without saving')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (preview != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(preview['title'] as String? ?? 'Untitled', style: Theme.of(context).textTheme.titleLarge),
          Text('Chosen parser: ${preview['format']}'),
          if (preview['source_url'] != null) SelectableText(widget.webPreview != null && preview['source_url'] == widget.webPreview!.finalUrl
            ? 'Final request address (source authenticity not verified): ${preview['source_url']}'
            : 'Supplied source address (not fetched or verified): ${preview['source_url']}'),
          Text('${preview['byte_len']} original bytes · ${preview['block_count']} extracted blocks'),
          SelectableText('SHA-256 (local consistency, not authenticity): ${preview['sha256']}'),
          const SizedBox(height: 8), SelectableText(preview['excerpt'] as String),
          const Text('Excerpt only. Original bytes are retained separately when you save.'),
          for (final warning in preview['warnings'] as List) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$warning')),
          if (duplicate != null) ...[
            const Divider(), Text('Exact original bytes, format and source address already saved: ${duplicate['title'] ?? duplicate['id']}. Nothing will be overwritten.'),
            FilledButton(key: const Key('capture-use-existing'), onPressed: _busy ? null : () => _save('use_existing'), child: const Text('Use existing copy')),
            OutlinedButton(key: const Key('capture-keep-copy'), onPressed: _busy ? null : () => _save('keep_copy'), child: const Text('Keep a separate copy')),
          ] else FilledButton(key: const Key('capture-save'), onPressed: _busy ? null : () => _save('save'), child: const Text('Save reviewed capture')),
        ]))),
      ]),
    ));
  }
}
