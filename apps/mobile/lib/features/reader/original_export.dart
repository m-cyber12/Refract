import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repository.dart';

/// Copies an existing original only after explicit consent and destination choice.
/// The plugin/OS may use temporary copies and the destination can be cloud-backed.
class OriginalExportButton extends ConsumerStatefulWidget {
  const OriginalExportButton({super.key, required this.itemId, required this.extension, this.save});
  final String itemId;
  final String extension;
  /// Injectable destination for tests; the mobile UI uses the OS picker.
  final Future<String?> Function(Uint8List bytes, String name)? save;
  @override ConsumerState<OriginalExportButton> createState() => _OriginalExportButtonState();
}
class _OriginalExportButtonState extends ConsumerState<OriginalExportButton> {
  bool _confirming = false, _busy = false;
  String? _status;
  Future<void> _export() async {
    if (_confirming || _busy) return;
    // Consent applies to the item visible when the dialog was opened, not
    // another item that might later reuse this widget's state.
    final itemId = widget.itemId;
    final extension = widget.extension;
    bool stillSameItem() => mounted && widget.itemId == itemId && widget.extension == extension;
    _confirming = true;
    bool? approved;
    try {
      approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Export a copy of the original?'),
        content: const Text('Choose a destination using the system picker. The complete original may contain private content, metadata or embedded scripts. The chosen provider may upload, retain or make its own copies. The app and OS may use temporary memory or files; deletion is not secure erasure. This does not open or verify the document.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Choose destination'))]));
    } finally { _confirming = false; }
    if (approved != true || !stillSameItem()) return;
    setState(() { _busy = true; _status = null; });
    try {
      if (widget.save == null && !Platform.isAndroid && !Platform.isIOS) {
        throw StateError('Original export is supported here only on Android and iOS.');
      }
      final repo = await ref.read(bootstrapProvider.future);
      if (!stillSameItem()) return;
      final result = await repo.capture('read_original', {'id': itemId, 'approved': true});
      if (result['source_type'] != 'pdf') throw const FormatException('Original is not a PDF.');
      final bytes = base64Decode(result['bytes_base64'] as String);
      if (bytes.length != result['byte_len']) throw const FormatException('Original length mismatch.');
      if (!stillSameItem()) return;
      final name = 'refract-original.$extension';
      final String? destination;
      if (widget.save != null) {
        destination = await widget.save!(bytes, name);
      } else {
        destination = await FilePicker.platform.saveFile(dialogTitle: 'Save a copy of the original', fileName: name, bytes: bytes);
      }
      if (stillSameItem()) {
        setState(() => _status = destination == null
          ? 'No destination was confirmed. Check the chosen provider if the picker was interrupted.'
          : 'The system reported the export complete. Verify the copy in the chosen destination.');
      }
    } catch (_) {
      if (stillSameItem()) setState(() => _status = 'Original export could not be confirmed. Check the original and chosen destination before retrying.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextButton.icon(key: const Key('export-original'), onPressed: _busy ? null : _export,
      icon: const Icon(Icons.file_download_outlined), label: const Text('Export a copy of the original')),
    if (_busy) const LinearProgressIndicator(),
    if (_status != null) Text(_status!),
  ]);
}
