import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repository.dart';

typedef PdfRender = Future<Map<String, dynamic>> Function(Uint8List bytes, int index);

/// Explicit local page rendering. The platform parser is not an isolation boundary.
class PdfLayoutViewer extends ConsumerStatefulWidget {
  const PdfLayoutViewer({super.key, required this.itemId, this.render});
  final String itemId;
  final PdfRender? render;
  @override ConsumerState<PdfLayoutViewer> createState() => _PdfLayoutViewerState();
}

class _PdfLayoutViewerState extends ConsumerState<PdfLayoutViewer> {
  static const _channel = MethodChannel('dev.refract/pdf_page');
  bool _confirming = false, _busy = false;
  Uint8List? _original, _png;
  int _index = 0, _pages = 0, _generation = 0;
  String? _error;

  @override void didUpdateWidget(covariant PdfLayoutViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId) { _generation++; _original = null; _png = null; _index = 0; _pages = 0; _error = null; }
  }
  @override void dispose() { _generation++; _original = null; _png = null; super.dispose(); }

  Future<void> _open() async {
    if (_busy || _confirming) return;
    final generation = _generation, id = widget.itemId;
    bool current() => mounted && generation == _generation;
    _confirming = true;
    bool? approved;
    try {
      approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Render the PDF original on this device?'),
        content: const Text('Android will parse this untrusted file. Rendering is not isolated or guaranteed safe. A temporary private cache file and memory copies are used; an interrupted process may leave a file, and deletion is not secure erasure. No document is uploaded by this viewer. Password-protected or malformed PDFs may fail.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Render locally'))]));
    } finally { _confirming = false; }
    if (approved != true || !current()) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.render == null && !Platform.isAndroid) throw StateError('Android only');
      final repo = await ref.read(bootstrapProvider.future);
      if (!current()) return;
      final source = await repo.capture('read_original', {'id': id, 'approved': true});
      if (!current()) return;
      if (source['source_type'] != 'pdf') throw const FormatException('Not a PDF');
      final bytes = base64Decode(source['bytes_base64'] as String);
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024 || bytes.length != source['byte_len']) throw const FormatException('Invalid original length');
      final rendered = await _render(bytes, 0);
      if (!current()) return;
      _apply(bytes, rendered, 0);
    } catch (_) { if (current()) setState(() => _error = 'The original PDF page could not be rendered. The original is unchanged.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<Map<String, dynamic>> _render(Uint8List bytes, int index) async => widget.render != null
      ? widget.render!(bytes, index)
      : (await _channel.invokeMapMethod<String, dynamic>('render', {'bytes': bytes, 'index': index}))!;

  void _apply(Uint8List bytes, Map<String, dynamic> result, int requested) {
    final png = result['png']; final pages = result['pages']; final index = result['index'];
    if (png is! Uint8List || png.isEmpty || png.length > 8 * 1024 * 1024 || pages is! int || pages < 1 || pages > 200 || index != requested || requested >= pages) {
      throw const FormatException('Invalid page result');
    }
    setState(() { _original = bytes; _png = png; _pages = pages; _index = requested; _error = null; });
  }

  Future<void> _page(int index) async {
    if (_busy || _original == null || index < 0 || index >= _pages) return;
    final generation = _generation, bytes = _original!;
    setState(() { _busy = true; _error = null; });
    try { final result = await _render(bytes, index); if (mounted && generation == _generation) _apply(bytes, result, index); }
    catch (_) { if (mounted && generation == _generation) setState(() => _error = 'The requested page could not be rendered.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (_original == null) TextButton.icon(key: const Key('open-pdf-layout'), onPressed: _busy ? null : _open,
      icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('View original PDF layout (Android)')),
    if (_original != null) ...[
      const Text('Original page layout · rendered locally; not signature or authenticity verification.'),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(onPressed: _busy || _index == 0 ? null : () => _page(_index - 1), child: const Text('Previous page')),
        Text('Page ${_index + 1} of $_pages'),
        TextButton(onPressed: _busy || _index + 1 >= _pages ? null : () => _page(_index + 1), child: const Text('Next page')),
        TextButton(onPressed: _busy ? null : () => setState(() { _generation++; _original = null; _png = null; _pages = 0; _error = null; }), child: const Text('Close layout')),
      ]),
      if (_png != null) Image.memory(_png!, gaplessPlayback: true, semanticLabel: 'PDF page ${_index + 1}'),
    ],
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Text(_error!),
  ]);
}
