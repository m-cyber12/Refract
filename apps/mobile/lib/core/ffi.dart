import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'models.dart';

/// Thin Dart FFI binding over the Rust `platform_bridge` C ABI.
///
/// Every call returns a decoded JSON envelope; `ok == false` becomes a
/// [RefractFailure]. All returned C strings are freed via `refract_free_string`.
class RefractBindings {
  RefractBindings._(this._lib);

  final DynamicLibrary _lib;

  late final _abiVersion = _lib
      .lookupFunction<Uint32 Function(), int Function()>('refract_abi_version');
  late final _open = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)>('refract_open');
  late final _close = _lib
      .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('refract_close');
  late final _freeString = _lib
      .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('refract_free_string');
  late final _importText = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_import_text');
  late final _importHtml = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_import_html');
  late final _importPdf = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Utf8>)>('refract_import_pdf');
  late final _listItems = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int, int)>('refract_list_items');
  late final _getItem = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_get_item');
  late final _search = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_search');

  static RefractBindings? _instance;

  factory RefractBindings.load() {
    if (_instance != null) return _instance!;
    final lib = Platform.isAndroid
        ? DynamicLibrary.open('librefract.so')
        : DynamicLibrary.process();
    final bindings = RefractBindings._(lib);
    const expectedAbi = 1;
    if (bindings._abiVersion() != expectedAbi) {
      throw RefractFailure('ABI mismatch: lib=${bindings._abiVersion()} app=$expectedAbi');
    }
    _instance = bindings;
    return bindings;
  }

  Pointer<Void> open(String dbPath) {
    final handle = _open(dbPath.toNativeUtf8());
    if (handle == Pointer.null) {
      throw RefractFailure('failed to open store at $dbPath');
    }
    return handle;
  }

  void close(Pointer<Void> handle) => _close(handle);

  Map<String, dynamic> _call(Pointer<Utf8> Function() fn) {
    final ptr = fn();
    try {
      final json = ptr.toDartString();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        final err = decoded['error'];
        final msg = err is Map ? '${err['type'] ?? ''}: ${err.values.where((v) => v is String).join(' ')}' : '$err';
        throw RefractFailure(msg.isEmpty ? 'unknown error' : msg);
      }
      return decoded;
    } finally {
      _freeString(ptr);
    }
  }

  Item importText(Pointer<Void> h, String text, String? sourceUrl) =>
      Item.fromJson(_call(() => _importText(h, text.toNativeUtf8(), sourceUrl?.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  Item importHtml(Pointer<Void> h, String html, String? sourceUrl) =>
      Item.fromJson(_call(() => _importHtml(h, html.toNativeUtf8(), sourceUrl?.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  Item importPdf(Pointer<Void> h, List<int> bytes, String? sourceUrl) {
    final ptr = calloc<Uint8>(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      return Item.fromJson(_call(() => _importPdf(h, ptr, bytes.length, sourceUrl?.toNativeUtf8()))['payload'] as Map<String, dynamic>);
    } finally {
      calloc.free(ptr);
    }
  }

  List<Item> listItems(Pointer<Void> h, {int limit = 50, int offset = 0}) =>
      (_call(() => _listItems(h, limit, offset))['payload'] as List)
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();

  Item? getItem(Pointer<Void> h, String id) {
    final payload = _call(() => _getItem(h, id.toNativeUtf8()))['payload'];
    if (payload == null) return null;
    return Item.fromJson(payload as Map<String, dynamic>);
  }

  List<Item> search(Pointer<Void> h, String query) =>
      (_call(() => _search(h, query.toNativeUtf8()))['payload'] as List)
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();

  Tag tagItem(Pointer<Void> h, String itemId, String tagName) =>
      Tag.fromJson(_call(() => _tagItem(h, itemId.toNativeUtf8(), tagName.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  List<Tag> listTags(Pointer<Void> h) =>
      (_call(() => _listTags(h))['payload'] as List).map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList();

  List<Tag> listItemTags(Pointer<Void> h, String itemId) =>
      (_call(() => _listItemTags(h, itemId.toNativeUtf8()))['payload'] as List).map((e) => Tag.fromJson(e as Map<String, dynamic>)).toList();

  Collection createCollection(Pointer<Void> h, String name) =>
      Collection.fromJson(_call(() => _createCollection(h, name.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  List<Collection> listCollections(Pointer<Void> h) =>
      (_call(() => _listCollections(h))['payload'] as List).map((e) => Collection.fromJson(e as Map<String, dynamic>)).toList();

  void addToCollection(Pointer<Void> h, String itemId, String collectionId) =>
      _call(() => _addToCollection(h, itemId.toNativeUtf8(), collectionId.toNativeUtf8()));

  Annotation addAnnotation(Pointer<Void> h, String itemId, String quote, String? note, int? blockIdx) =>
      Annotation.fromJson(_call(() => _addAnnotation(h, itemId.toNativeUtf8(), quote.toNativeUtf8(), _opt(note), (blockIdx ?? -1)))['payload'] as Map<String, dynamic>);

  List<Annotation> listAnnotations(Pointer<Void> h, String itemId) =>
      (_call(() => _listAnnotations(h, itemId.toNativeUtf8()))['payload'] as List).map((e) => Annotation.fromJson(e as Map<String, dynamic>)).toList();

  String export(Pointer<Void> h) => _call(() => _export(h))['payload'] as String;

  List<Item> dailyEdition(Pointer<Void> h, {int days = 7}) =>
      (_call(() => _dailyEdition(h, days))['payload'] as List).map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
}
