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

/// Reads only the chosen file, with checks on metadata AND actual streamed bytes.
/// Native/provider caching can happen before these checks. Cleanup is a request
/// for plugin temporary copies, not secure erasure or control of provider caches.
Future<CaptureFile?> pickCaptureFile({FilePicker? picker, bool? requireCleanup}) async {
  final files = picker ?? FilePicker.platform;
  try {
    final result = await files.pickFiles(type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'markdown', 'html', 'htm', 'pdf'],
      allowMultiple: false, withData: false, withReadStream: true);
    if (result == null) return null;
    if (result.files.length != 1) throw const FormatException('Select one file only.');
    final file = result.files.single;
    final format = switch (file.extension?.toLowerCase()) {
      'txt' => 'text', 'md' || 'markdown' => 'markdown',
      'html' || 'htm' => 'html', 'pdf' => 'pdf',
      _ => throw const FormatException('Supported files: UTF-8 text, Markdown, HTML and PDF. Nothing was imported.'),
    };
    final limit = (format == 'pdf' ? 10 : 2) * 1024 * 1024;
    if (file.size > limit) throw FormatException('File exceeds ${format == 'pdf' ? '10' : '2'} MiB.');
    final builder = BytesBuilder(copy: false);
    if (file.readStream != null) {
      await for (final chunk in file.readStream!) {
        if (builder.length + chunk.length > limit) throw const FormatException('Stream exceeds the capture size limit.');
        builder.add(chunk);
      }
    } else if (file.bytes != null) {
      if (file.bytes!.length > limit) throw const FormatException('File exceeds the capture size limit.');
      builder.add(file.bytes!);
    } else {
      throw const FormatException('Provider did not supply readable bytes. Paste text or choose another file provider.');
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw const FormatException('File is empty.');
    // Dart's UTF-8 decoder consumes an initial BOM. Restore it in the captured
    // text so re-encoding preserves source bytes; Rust ignores it only for parsing.
    final decoded = format == 'pdf' ? null : utf8.decode(bytes);
    final hasBom = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
    return CaptureFile(name: file.name, format: format,
      text: decoded == null ? null : hasBom ? '\uFEFF$decoded' : decoded,
      pdfBase64: format == 'pdf' ? base64Encode(bytes) : null);
  } finally {
    if (requireCleanup ?? (Platform.isAndroid || Platform.isIOS)) {
      if (await files.clearTemporaryFiles() != true) {
        throw const FormatException('Picker-cache cleanup could not be confirmed. No selected file was accepted. OS/provider caches may need cleanup; paste text instead.');
      }
    }
  }
}
