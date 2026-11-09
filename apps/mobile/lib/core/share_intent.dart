import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../features/import/capture_file.dart';

class SharedDraft {
  const SharedDraft({required this.id, this.file, this.error, this.byteLength = 0, this.staged = false, this.consentTS});
  final String id;
  final CaptureFile? file;
  final String? error;
  final int byteLength;
  final bool staged;
  final int? consentTS;
}

/// Review inbox, not the durable approved capture queue. Android is memory-only;
/// iOS explicitly consented handoff copies stay native until save/discard. No parsing, fetching,
/// repository access, navigation or persistence occurs on delivery.
class ShareIntentChannel extends ChangeNotifier with WidgetsBindingObserver {
  ShareIntentChannel({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('dev.refract/shared');
  static final instance = ShareIntentChannel();
  final MethodChannel _channel;
  final List<SharedDraft> _drafts = [];
  final Set<String> _accepted = {};
  List<SharedDraft> get drafts => List.unmodifiable(_drafts);
  String? notice;
  bool _pulling = false;
  bool _again = false;
  bool _initialized = false;
  bool _disposed = false;
  int get _bytes => _drafts.fold(0, (n, d) => n + d.byteLength);

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharesAvailable') await pull();
    });
    unawaited(_beginAndPull());
  }
  Future<void> _beginAndPull() async {
    try { await _channel.invokeMethod<void>('beginShareSession'); }
    on MissingPluginException { /* Android memory queue needs no reset. */ }
    on PlatformException { /* pull reports native availability separately. */ }
    if (!_disposed) await pull();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(pull());
  }

  Future<void> pull() async {
    if (_disposed) return;
    if (_pulling) { _again = true; return; }
    _pulling = true;
    try {
      do {
        _again = false;
        while (!_disposed) {
          final response = await _channel.invokeMapMethod<String, dynamic>('peekShare');
          if (_disposed) return;
          if (response?['notice'] is String) { notice = response!['notice'] as String; notifyListeners(); }
          final raw = response?['draft'];
          if (raw == null) break;
          final value = Map<String, dynamic>.from(raw as Map);
          if (!_accept(value)) break; // Native retains unacknowledged input until space exists.
          await _channel.invokeMethod<void>('ackShare', value['id']);
          _accepted.remove(value['id']);
        }
      } while (_again && !_disposed);
    } on MissingPluginException {
      // Desktop/manual Import may not implement the native handoff API.
    } on PlatformException {
      if (!_disposed) { notice = 'Native share handoff unavailable. Retry from the sender or use Import.'; notifyListeners(); }
    } catch (_) {
      if (!_disposed) { notice = 'Invalid share handoff. Nothing was imported; use Import or share again.'; notifyListeners(); }
    } finally { _pulling = false; }
  }

  bool _accept(Map<String, dynamic> raw) {
    final id = raw['id'];
    if (id is! String || id.isEmpty || id.length > 128) throw const FormatException('Invalid share ID');
    if (_accepted.contains(id) || _drafts.any((d) => d.id == id)) return true; // Retry after an uncertain native acknowledgement.
    final bytes = raw['bytes'];
    final size = bytes is Uint8List ? bytes.length : 0;
    if (_drafts.length >= 16 || _bytes + size > 24 * 1024 * 1024) {
      notice = 'Shared drafts are full (16 / 24 MiB). Review or discard some drafts; further input may still be waiting natively.';
      notifyListeners(); return false;
    }
    final staged = raw['staged'] == true;
    final consentTS = (raw['consent_ts'] as num?)?.toInt();
    SharedDraft draft;
    try {
      if (raw['error'] is String) {
        draft = SharedDraft(id: id, staged: staged, consentTS: consentTS, error: raw['error'] as String);
      } else {
        if (bytes is! Uint8List || bytes.isEmpty) throw const FormatException('Unreadable or empty shared input.');
        final format = raw['format'];
        if (!['text', 'markdown', 'html', 'pdf'].contains(format)) throw const FormatException('Unsupported shared format.');
        if (size > (format == 'pdf' ? 10 : 2) * 1024 * 1024) throw const FormatException('Shared input exceeds its size limit.');
        final name = String.fromCharCodes((raw['name'] is String ? raw['name'] as String : 'Shared input').replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').runes.take(120));
        final text = format == 'pdf' ? null : utf8.decode(bytes);
        final bom = size >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
        draft = SharedDraft(id: id, staged: staged, consentTS: consentTS, byteLength: size, file: CaptureFile(name: name, format: format as String,
          text: text == null ? null : bom ? '\uFEFF$text' : text,
          pdfBase64: format == 'pdf' ? base64Encode(bytes) : null));
      }
    } catch (_) { draft = SharedDraft(id: id, staged: staged, consentTS: consentTS, error: 'Shared input is empty, oversized, unsupported or not valid UTF-8. Nothing was imported.'); }
    _accepted.add(id); _drafts.add(draft); notifyListeners(); return true;
  }

  final Set<String> _removing = {};
  Future<bool> remove(String id) async {
    if (!_removing.add(id)) return false;
    try {
      final retained = _drafts.any((d) => d.id == id && d.staged);
      if (retained) await _channel.invokeMethod<void>('deleteShare', id);
      if (_disposed) return false;
      _drafts.removeWhere((d) => d.id == id);
      notifyListeners(); unawaited(pull()); return true;
    } catch (_) {
      if (!_disposed) { notice = 'Staged handoff removal could not be confirmed. It remains listed; retry discard or open the already saved library copy. This is not a failed library save.'; notifyListeners(); }
      return false;
    } finally { _removing.remove(id); }
  }
  Future<void> clearNotice() async {
    notice = null; notifyListeners();
    try { await _channel.invokeMethod<void>('clearShareNotice'); } on MissingPluginException { /* optional bridge */ } on PlatformException { /* retryable notice dismissal */ }
  }
  @override void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
