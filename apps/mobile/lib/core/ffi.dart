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
  late final _tagItem = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_tag_item');
  late final _listTags = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_list_tags');
  late final _listItemTags = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_list_item_tags');
  late final _createCollection = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_create_collection');
  late final _listCollections = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_list_collections');
  late final _addToCollection = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_add_to_collection');
  late final _addAnnotation = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int64),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int)>('refract_add_annotation');
  late final _listAnnotations = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_list_annotations');
  late final _export = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_export');
  late final _dailyEdition = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int)>('refract_daily_edition');
  late final _addSubscription = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_add_subscription');
  late final _listSubscriptions = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_list_subscriptions');
  late final _upcomingEvents = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int)>('refract_upcoming_events');
  late final _addEvidence = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, Size, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>)>('refract_add_evidence');
  late final _listEvidence = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_list_evidence');
  late final _listClaims = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_list_claims');
  late final _verifyEvidence = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_verify_evidence');

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
    if (handle.address == 0) {
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
        final msg = err is Map ? '${err['type'] ?? ''}: ${err.values.whereType<String>().join(' ')}' : '$err';
        throw RefractFailure(msg.isEmpty ? 'unknown error' : msg);
      }
      return decoded;
    } finally {
      _freeString(ptr);
    }
  }

  static Pointer<Utf8> _opt(String? s) => s?.toNativeUtf8() ?? Pointer<Utf8>.fromAddress(0);

  Item importText(Pointer<Void> h, String text, String? sourceUrl) =>
      Item.fromJson(_call(() => _importText(h, text.toNativeUtf8(), _opt(sourceUrl)))['payload'] as Map<String, dynamic>);

  Item importHtml(Pointer<Void> h, String html, String? sourceUrl) =>
      Item.fromJson(_call(() => _importHtml(h, html.toNativeUtf8(), _opt(sourceUrl)))['payload'] as Map<String, dynamic>);

  Item importPdf(Pointer<Void> h, List<int> bytes, String? sourceUrl) {
    final ptr = calloc<Uint8>(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      return Item.fromJson(_call(() => _importPdf(h, ptr, bytes.length, _opt(sourceUrl)))['payload'] as Map<String, dynamic>);
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

  Subscription addSubscription(Pointer<Void> h, Map<String, dynamic> subJson) {
    final encoded = jsonEncode(subJson);
    return Subscription.fromJson(_call(() => _addSubscription(h, encoded.toNativeUtf8()))['payload'] as Map<String, dynamic>);
  }

  List<Subscription> listSubscriptions(Pointer<Void> h) =>
      (_call(() => _listSubscriptions(h))['payload'] as List).map((e) => Subscription.fromJson(e as Map<String, dynamic>)).toList();

  List<Subscription> upcomingEvents(Pointer<Void> h, int days) =>
      (_call(() => _upcomingEvents(h, days))['payload'] as List).map((e) => Subscription.fromJson(e as Map<String, dynamic>)).toList();

  EvidenceRecord addEvidence(Pointer<Void> h, String kind, String? note, List<int> bytes, String? textForClaims) {
    final ptr = calloc<Uint8>(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      return EvidenceRecord.fromJson(
          _call(() => _addEvidence(h, kind.toNativeUtf8(), _opt(note), ptr, bytes.length, _opt(textForClaims)))['payload'] as Map<String, dynamic>);
    } finally {
      calloc.free(ptr);
    }
  }

  List<EvidenceRecord> listEvidence(Pointer<Void> h) =>
      (_call(() => _listEvidence(h))['payload'] as List).map((e) => EvidenceRecord.fromJson(e as Map<String, dynamic>)).toList();

  List<EvidenceClaim> listClaims(Pointer<Void> h, String recordId) =>
      (_call(() => _listClaims(h, recordId.toNativeUtf8()))['payload'] as List).map((e) => EvidenceClaim.fromJson(e as Map<String, dynamic>)).toList();

  bool? verifyEvidence(Pointer<Void> h, String id) =>
      _call(() => _verifyEvidence(h, id.toNativeUtf8()))['payload'] as bool?;

  Map<String, dynamic> summarize(Pointer<Void> h, String itemId, int maxSentences) =>
      _call(() => _summarize(h, itemId.toNativeUtf8(), maxSentences))['payload'] as Map<String, dynamic>;

  Map<String, dynamic> suggestTags(Pointer<Void> h, String itemId, int maxTags) =>
      _call(() => _suggestTags(h, itemId.toNativeUtf8(), maxTags))['payload'] as Map<String, dynamic>;

  List<Item> related(Pointer<Void> h, String itemId, int limit) =>
      (_call(() => _related(h, itemId.toNativeUtf8(), limit))['payload'] as List).map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
}
