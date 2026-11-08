import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/library_refresh.dart';
import '../../core/repository.dart';
import 'capture_file.dart';

/// Explicit local capture with a review binding; no inferred parser or URL fetch.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.pickFile, this.initialText = ''});
  final Future<CaptureFile?> Function()? pickFile;
  final String initialText;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}
class _ImportPageState extends ConsumerState<ImportPage> {
  final _text = TextEditingController();
  final _url = TextEditingController();
  String _format = 'text';
  CaptureFile? _file;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _reviewedInput;

  @override
  void initState() { super.initState(); _text.text = widget.initialText; _text.addListener(_changed); _url.addListener(_changed); }
  void _changed() {
    if (mounted) setState(() { _preview = null; _reviewedInput = null; _error = null; });
  }
  @override
  void dispose() { _text.dispose(); _url.dispose(); super.dispose(); }

  Future<void> _chooseFile() async {
    setState(() { _busy = true; _error = null; });
    try {
      final file = await (widget.pickFile?.call() ?? pickCaptureFile());
      if (!mounted || file == null) return;
      _text.text = file.text ?? '';
      setState(() { _file = file; _format = file.format; _preview = null; _reviewedInput = null; });
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
    setState(() { _busy = true; _error = null; _preview = null; _reviewedInput = null; });
    try {
      final input = _input();
      final repo = await ref.read(bootstrapProvider.future);
      final preview = await repo.capture('preview', input);
      if (mounted) setState(() { _preview = preview; _reviewedInput = input; });
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _save(String choice) async {
    final preview = _preview;
    final input = _reviewedInput;
    if (preview == null || input == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final result = await repo.capture('commit', {...input, 'review_hash': preview['review_hash'], 'choice': choice,
        if (choice == 'use_existing') 'existing_id': (preview['duplicate'] as Map)['id']});
      if (!mounted) return;
      refreshLibrary(ref);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['reused_existing'] == true
        ? 'Opened existing copy; no new original was saved.' : 'Saved to your local library.')));
      context.go('/reader/${Uri.encodeComponent((result['item'] as Map)['id'] as String)}');
    } catch (e) {
      if (mounted) setState(() => _error = '$e\nYour input is still here. If a save was interrupted, check the library before retrying.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final duplicate = preview?['duplicate'] as Map?;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('Capture locally'), automaticallyImplyLeading: !_busy),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Choose a format. Preview extracts text locally without saving content. URLs are saved as addresses only, never fetched.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('capture-format'), initialValue: _format, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Format'),
          items: const [DropdownMenuItem(value: 'text', child: Text('Plain text')),
            DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
            DropdownMenuItem(value: 'html', child: Text('HTML')),
            DropdownMenuItem(value: 'url_reference', child: Text('URL reference (not fetched)')),
            DropdownMenuItem(value: 'pdf', child: Text('PDF file (text extraction, no OCR)'))],
          onChanged: _busy ? null : (value) { if (value != null) setState(() { _format = value; _preview = null; _reviewedInput = null; _error = null; }); }),
        const SizedBox(height: 8),
        const Text('A selected provider may download/cache a file before app size checks. Mobile picker cleanup is requested, not secure erasure or control of provider caches.'),
        OutlinedButton.icon(key: const Key('capture-file'), onPressed: _busy ? null : _chooseFile,
          icon: const Icon(Icons.file_open_outlined), label: const Text('Choose one file · TXT / MD / HTML / PDF')),
        if (_file != null) Text('Loaded: ${_file!.name}. The selected source file is not changed. Text edits below become the captured original.'),
        if (_format != 'pdf') TextField(key: const Key('capture-text'), controller: _text, enabled: !_busy,
          minLines: 4, maxLines: 10, decoration: InputDecoration(labelText: _format == 'url_reference' ? 'Complete HTTP(S) address' : 'Original input', alignLabelWithHint: true)),
        if (_format != 'url_reference') TextField(key: const Key('capture-url'), controller: _url, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Source HTTP(S) URL (optional, not fetched)')),
        const SizedBox(height: 12),
        const Text('Limits: text 2 MiB; PDF 10 MiB / 200 pages / 16 MiB decoded page content; extracted text 2 MiB / 20,000 blocks. No app-level encryption. Drafts are not saved: keep the app open until the result; no durable retry queue.'),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('capture-preview'), onPressed: _busy ? null : _review,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.preview_outlined),
          label: Text(_busy ? 'Working locally…' : 'Preview without saving')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (preview != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(preview['title'] as String? ?? 'Untitled', style: Theme.of(context).textTheme.titleLarge),
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
