import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class CaptureFile {
  const CaptureFile({required this.name, required this.format, this.text, this.pdfBase64});
  final String name;
  final String format;
  final String? text;
  final String? pdfBase64;
}

/// An ephemeral selection; no file is saved by selecting it.
class BatchEntry {
  const BatchEntry({required this.file, required this.byteLength});
  final CaptureFile file;
  final int byteLength;
}

const captureExtensions = ['txt', 'log', 'csv', 'tsv', 'json', 'xml', 'md', 'markdown', 'html', 'htm', 'pdf'];

Future<BatchEntry> _readCaptureFile(PlatformFile file, int remaining, Stopwatch elapsed, Duration idleTimeout, Duration readBudget) async {
  if (elapsed.elapsed >= readBudget) throw const FormatException('File selection read deadline exceeded; nothing was accepted.');
  final format = switch (file.extension?.toLowerCase()) {
    'txt' || 'log' || 'csv' || 'tsv' || 'json' || 'xml' => 'text', 'md' || 'markdown' => 'markdown',
    'html' || 'htm' => 'html', 'pdf' => 'pdf',
    _ => throw const FormatException('Supported files: UTF-8 text and logs, CSV, TSV, JSON, XML, Markdown, HTML and PDF. Nothing was imported.'),
  };
  final limit = (format == 'pdf' ? 10 : 2) * 1024 * 1024;
  if (file.size > limit) throw FormatException('File exceeds ${format == 'pdf' ? '10' : '2'} MiB.');
  if (file.size > remaining) throw const FormatException('Selection exceeds the 24 MiB batch limit.');
  final builder = BytesBuilder(copy: false);
  if (file.readStream != null) {
    final iterator = StreamIterator<List<int>>(file.readStream!);
    try {
      while (true) {
        final timeLeft = readBudget - elapsed.elapsed;
        if (timeLeft <= Duration.zero) throw const FormatException('File selection read deadline exceeded; nothing was accepted.');
        final timeout = timeLeft < idleTimeout ? timeLeft : idleTimeout;
        if (!await iterator.moveNext().timeout(timeout)) break;
        if (elapsed.elapsed >= readBudget) throw const FormatException('File selection read deadline exceeded; nothing was accepted.');
        final chunk = iterator.current;
        if (builder.length + chunk.length > limit || builder.length + chunk.length > remaining) throw const FormatException('Stream exceeds the file or batch capture size limit.');
        builder.add(chunk);
      }
    } on TimeoutException {
      throw const FormatException('File provider read timed out; nothing was accepted. Try another provider.');
    } finally {
      await iterator.cancel();
    }
  } else if (file.bytes != null) {
    if (file.bytes!.length > limit || file.bytes!.length > remaining) throw const FormatException('File exceeds the file or batch capture size limit.');
    builder.add(file.bytes!);
  } else {
    throw const FormatException('Provider did not supply readable bytes. Paste text or choose another file provider.');
  }
  if (elapsed.elapsed >= readBudget) throw const FormatException('File selection read deadline exceeded; nothing was accepted.');
  final bytes = builder.takeBytes();
  if (bytes.isEmpty) throw const FormatException('File is empty.');
  // A positive provider-reported size is only a consistency check, not proof
  // of source authenticity or completeness. Zero is treated as unknown.
  if (file.size > 0 && bytes.length != file.size) {
    throw const FormatException('Provider-reported size differs from bytes read. Nothing was accepted; try the provider again.');
  }
  // Decoder consumes a BOM. Restore it so unedited input re-encodes exactly.
  final decoded = format == 'pdf' ? null : utf8.decode(bytes);
  final hasBom = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
  return BatchEntry(byteLength: bytes.length, file: CaptureFile(name: file.name, format: format,
    text: decoded == null ? null : hasBom ? '\uFEFF$decoded' : decoded,
    pdfBase64: format == 'pdf' ? base64Encode(bytes) : null));
}

/// Read a bounded selection atomically into temporary process memory. The OS or
/// provider may cache/download before checks. No batch item is saved here.
Future<List<BatchEntry>?> pickCaptureFiles({FilePicker? picker, bool? requireCleanup,
    bool multiple = true, int maxCount = 16, int maxBytes = 24 * 1024 * 1024,
    Duration idleTimeout = const Duration(seconds: 15), Duration readBudget = const Duration(minutes: 2)}) async {
  final files = picker ?? FilePicker.platform;
  try {
    final result = await files.pickFiles(type: FileType.custom, allowedExtensions: captureExtensions,
      allowMultiple: multiple, withData: false, withReadStream: true);
    if (result == null) return null;
    if (result.files.isEmpty || result.files.length > maxCount || (!multiple && result.files.length != 1)) {
      throw const FormatException('Selection exceeds the available item limit; nothing was accepted.');
    }
    var remaining = maxBytes;
    final elapsed = Stopwatch()..start();
    final selected = <BatchEntry>[];
    for (final file in result.files) {
      final entry = await _readCaptureFile(file, remaining, elapsed, idleTimeout, readBudget);
      remaining -= entry.byteLength;
      selected.add(entry);
    }
    return selected;
  } finally {
    if (requireCleanup ?? (Platform.isAndroid || Platform.isIOS)) {
      if (await files.clearTemporaryFiles() != true) {
        throw const FormatException('Picker-cache cleanup could not be confirmed. No selected file was accepted. OS/provider caches may need cleanup; paste text instead.');
      }
    }
  }
}

/// Single-file flow uses the same bounded decoder and cleanup contract.
Future<CaptureFile?> pickCaptureFile({FilePicker? picker, bool? requireCleanup}) async {
  final entries = await pickCaptureFiles(picker: picker, requireCleanup: requireCleanup, multiple: false, maxCount: 1);
  return entries?.single.file;
}
