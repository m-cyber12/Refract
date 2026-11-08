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

  late final _capture = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_capture');

  Map<String, dynamic> capture(Pointer<Void> h, String request) =>
      _memoryCall([request], (p) => _capture(h, p[0]))['payload'] as Map<String, dynamic>;

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
  late final _summarize = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_summarize');
  late final _suggestTags = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_suggest_tags');
  late final _related = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_related');
  late final _createWorkspace = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_create_workspace');
  late final _listWorkspaces = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_list_workspaces');
  late final _shareAnnotation = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>('refract_share_annotation');
  late final _syncPending = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_sync_pending');
  late final _merkleRoot = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_evidence_merkle_root');
  late final _merkleProof = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_evidence_merkle_proof');
  late final _verifyProof = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_verify_evidence_proof');

  late final _senseEvaluate = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_sense_evaluate');
  late final _senseDecisions = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int, int)>('refract_sense_decisions');
  late final _senseReview = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_sense_review');
  late final _senseRules = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>('refract_sense_rules');
  late final _senseRuleUpsert = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_sense_rule_upsert');
  late final _senseRuleDelete = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_sense_rule_delete');
  late final _sensePresetSet = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_sense_preset_set');
  late final _senseSettingGet = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_sense_setting_get');
  late final _senseSettingSet = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_sense_setting_set');

  late final _memoryOrganizeItem = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_memory_organize_item');
  late final _memoryOrganizeLibrary = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>),
      Pointer<Utf8> Function(Pointer<Void>)>('refract_memory_organize_library');
  late final _topicsList = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>('refract_topics_list');
  late final _topicRename = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_topic_rename');
  late final _topicMerge = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_topic_merge');
  late final _topicReject = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_topic_reject');
  late final _topicPin = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_topic_pin');
  late final _topicItems = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_topic_items');
  late final _topicEvolution = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_topic_evolution');
  late final _entitiesList = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int)>('refract_entities_list');
  late final _relationshipsList = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_relationships_list');
  late final _relationshipDismiss = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_relationship_dismiss');
  late final _relationshipAdd = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_relationship_add');
  late final _memoryTimeline = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int)>('refract_memory_timeline');
  late final _itemTimeSet = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_item_time_set');
  late final _projectsList = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>('refract_projects_list');
  late final _projectCreate = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_project_create');
  late final _projectDelete = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_project_delete');
  late final _projectAddItem = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_project_add_item');
  late final _projectRemoveItem = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('refract_project_remove_item');
  late final _projectItems = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_project_items');
  late final _projectTimeline = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, int)>('refract_project_timeline');

  late final _recallQuery = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_recall_query');
  late final _recallRebuild = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>('refract_recall_rebuild');

  late final _signal = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('refract_signal');

  late final _consumer = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>)>('refract_consumer');

  late final _knowledge = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>)>('refract_knowledge');

  late final _margins = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>),Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>)>('refract_margins');
  late final _integrations = _lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>),Pointer<Utf8> Function(Pointer<Void>,Pointer<Utf8>)>('refract_integrations');
  static RefractBindings? _instance;

  factory RefractBindings.load() {
    if (_instance != null) return _instance!;
    final lib = Platform.isAndroid
        ? DynamicLibrary.open('librefract.so')
        : Platform.isLinux
            ? DynamicLibrary.open(Platform.environment['REFRACT_NATIVE_LIBRARY'] ?? 'librefract.so')
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
    final path = dbPath.toNativeUtf8();
    late Pointer<Void> handle;
    try { handle = _open(path); } finally { malloc.free(path); }
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
      Item.fromJson(_memoryCall([text, if (sourceUrl != null) sourceUrl], (p) => _importText(h, p[0], sourceUrl == null ? nullptr : p[1]))['payload'] as Map<String, dynamic>);

  Item importHtml(Pointer<Void> h, String html, String? sourceUrl) =>
      Item.fromJson(_memoryCall([html, if (sourceUrl != null) sourceUrl], (p) => _importHtml(h, p[0], sourceUrl == null ? nullptr : p[1]))['payload'] as Map<String, dynamic>);

  Item importPdf(Pointer<Void> h, List<int> bytes, String? sourceUrl) {
    if (bytes.length > 10 * 1024 * 1024) { throw RefractFailure('PDF exceeds 10 MiB'); }
    final ptr = calloc<Uint8>(bytes.length);
    final url = _opt(sourceUrl);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      return Item.fromJson(_call(() => _importPdf(h, ptr, bytes.length, url))['payload'] as Map<String, dynamic>);
    } finally {
      calloc.free(ptr);
      if (url.address != 0) { malloc.free(url); }
    }
  }

  List<Item> listItems(Pointer<Void> h, {int limit = 50, int offset = 0}) =>
      (_call(() => _listItems(h, limit, offset))['payload'] as List)
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();

  Item? getItem(Pointer<Void> h, String id) {
    final payload = _memoryCall([id], (p) => _getItem(h, p[0]))['payload'];
    if (payload == null) return null;
    return Item.fromJson(payload as Map<String, dynamic>);
  }

  List<Item> search(Pointer<Void> h, String query) =>
      (_memoryCall([query], (p) => _search(h, p[0]))['payload'] as List)
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

  // ----- REFRACT SENSE (Phase II master, Phase 2) -----

  CaptureDecisionRecord senseEvaluate(Pointer<Void> h, String itemId) =>
      CaptureDecisionRecord.fromJson(_call(() => _senseEvaluate(h, itemId.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  List<CaptureDecisionRecord> senseDecisions(Pointer<Void> h, {int limit = 50, int offset = 0}) =>
      (_call(() => _senseDecisions(h, limit, offset))['payload'] as List)
          .map((e) => CaptureDecisionRecord.fromJson(e as Map<String, dynamic>))
          .toList();

  CaptureDecisionRecord senseReview(Pointer<Void> h, String decisionId, String action) =>
      CaptureDecisionRecord.fromJson(_call(() => _senseReview(h, decisionId.toNativeUtf8(), action.toNativeUtf8()))['payload'] as Map<String, dynamic>);

  List<SenseRule> senseRules(Pointer<Void> h) =>
      (_call(() => _senseRules(h))['payload'] as List).map((e) => SenseRule.fromJson(e as Map<String, dynamic>)).toList();

  SenseRule senseRuleUpsert(Pointer<Void> h, Map<String, dynamic> rule) =>
      SenseRule.fromJson(_call(() => _senseRuleUpsert(h, jsonEncode(rule).toNativeUtf8()))['payload'] as Map<String, dynamic>);

  void senseRuleDelete(Pointer<Void> h, String ruleId) => _call(() => _senseRuleDelete(h, ruleId.toNativeUtf8()));

  int sensePresetSet(Pointer<Void> h, String preset) =>
      (_call(() => _sensePresetSet(h, preset.toNativeUtf8()))['payload'] as num).toInt();

  String senseSettingGet(Pointer<Void> h, String key) => _call(() => _senseSettingGet(h, key.toNativeUtf8()))['payload'] as String;

  void senseSettingSet(Pointer<Void> h, String key, String value) => _call(() => _senseSettingSet(h, key.toNativeUtf8(), value.toNativeUtf8()));

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

  String createWorkspace(Pointer<Void> h, String name) =>
      _memoryCall([name],(p)=>_createWorkspace(h,p[0]))['payload'] as String;

  List<List<String>> listWorkspaces(Pointer<Void> h) =>
      (_call(() => _listWorkspaces(h))['payload'] as List).map((e) => (e as List).map((x) => x as String).toList()).toList();

  bool shareAnnotation(Pointer<Void> h, String workspaceId, String annotationId, Map<String, dynamic> payload) {
    final encoded = jsonEncode(payload);
    return _memoryCall([workspaceId,annotationId,encoded],(p)=>_shareAnnotation(h,p[0],p[1],p[2]))['payload'] as bool;
  }

  int syncPending(Pointer<Void> h) => _call(() => _syncPending(h))['payload'] as int;

  String? merkleRoot(Pointer<Void> h) => _call(() => _merkleRoot(h))['payload'] as String?;

  Map<String, dynamic>? merkleProof(Pointer<Void> h, String recordId) {
    final p = _call(() => _merkleProof(h, recordId.toNativeUtf8()))['payload'];
    return p == null ? null : p as Map<String, dynamic>;
  }

  bool? verifyProof(Pointer<Void> h, String recordId) =>
      _call(() => _verifyProof(h, recordId.toNativeUtf8()))['payload'] as bool?;

  // Input UTF-8 buffers belong to Dart, unlike the Rust-owned response.
  Map<String, dynamic> _memoryCall(List<String> values, Pointer<Utf8> Function(List<Pointer<Utf8>>) call) {
    final pointers = <Pointer<Utf8>>[];
    try {
      for (final value in values) {
        pointers.add(value.toNativeUtf8());
      }
      return _call(() => call(pointers));
    } finally {
      for (final pointer in pointers) {
        malloc.free(pointer);
      }
    }
  }

  // ----- SMART MEMORY (Phase II master, Phase 3) -----

  OrganizeReport memoryOrganizeItem(Pointer<Void> h, String itemId) =>
      OrganizeReport.fromJson(_memoryCall([itemId], (p) => _memoryOrganizeItem(h, p[0]))['payload'] as Map<String, dynamic>);

  List<OrganizeReport> memoryOrganizeLibrary(Pointer<Void> h) =>
      (_call(() => _memoryOrganizeLibrary(h))['payload'] as List)
          .map((e) => OrganizeReport.fromJson(e as Map<String, dynamic>))
          .toList();

  List<Topic> topicsList(Pointer<Void> h) =>
      (_call(() => _topicsList(h))['payload'] as List).map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();

  Topic topicRename(Pointer<Void> h, String topicId, String newName) =>
      Topic.fromJson(_memoryCall([topicId, newName], (p) => _topicRename(h, p[0], p[1]))['payload'] as Map<String, dynamic>);

  Topic topicMerge(Pointer<Void> h, String fromId, String toId) =>
      Topic.fromJson(_memoryCall([fromId, toId], (p) => _topicMerge(h, p[0], p[1]))['payload'] as Map<String, dynamic>);

  void topicReject(Pointer<Void> h, String topicId) => _memoryCall([topicId], (p) => _topicReject(h, p[0]));

  void topicPin(Pointer<Void> h, String topicId, bool pinned) => _memoryCall([topicId], (p) => _topicPin(h, p[0], pinned ? 1 : 0));

  List<Item> topicItems(Pointer<Void> h, String topicId, {int limit = 50}) =>
      (_memoryCall([topicId], (p) => _topicItems(h, p[0], limit))['payload'] as List)
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();

  TopicEvolution topicEvolution(Pointer<Void> h, String topicId, {int stages = 4}) =>
      TopicEvolution.fromJson(_memoryCall([topicId], (p) => _topicEvolution(h, p[0], stages))['payload'] as Map<String, dynamic>);

  List<EntityRecord> entitiesList(Pointer<Void> h, {int limit = 50}) =>
      (_call(() => _entitiesList(h, limit))['payload'] as List)
          .map((e) => EntityRecord.fromJson(e as Map<String, dynamic>))
          .toList();

  List<Relationship> relationshipsList(Pointer<Void> h, {String itemId = '', int limit = 50}) =>
      (_memoryCall([itemId], (p) => _relationshipsList(h, p[0], limit))['payload'] as List)
          .map((e) => Relationship.fromJson(e as Map<String, dynamic>))
          .toList();

  void relationshipDismiss(Pointer<Void> h, String relId) => _memoryCall([relId], (p) => _relationshipDismiss(h, p[0]));

  Relationship relationshipAdd(Pointer<Void> h, Map<String, dynamic> rel) =>
      Relationship.fromJson(_memoryCall([jsonEncode(rel)], (p) => _relationshipAdd(h, p[0]))['payload'] as Map<String, dynamic>);

  List<TimelineEntry> memoryTimeline(Pointer<Void> h, {int limit = 100}) =>
      (_call(() => _memoryTimeline(h, limit))['payload'] as List)
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList();

  void itemTimeSet(Pointer<Void> h, Map<String, dynamic> t) => _memoryCall([jsonEncode(t)], (p) => _itemTimeSet(h, p[0]));

  List<Project> projectsList(Pointer<Void> h) =>
      (_call(() => _projectsList(h))['payload'] as List).map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();

  Project projectCreate(Pointer<Void> h, Map<String, dynamic> proj) =>
      Project.fromJson(_memoryCall([jsonEncode(proj)], (p) => _projectCreate(h, p[0]))['payload'] as Map<String, dynamic>);

  void projectDelete(Pointer<Void> h, String projectId) => _memoryCall([projectId], (p) => _projectDelete(h, p[0]));

  void projectAddItem(Pointer<Void> h, String projectId, String itemId) =>
      _memoryCall([projectId, itemId], (p) => _projectAddItem(h, p[0], p[1]));

  void projectRemoveItem(Pointer<Void> h, String projectId, String itemId) =>
      _memoryCall([projectId, itemId], (p) => _projectRemoveItem(h, p[0], p[1]));

  List<Item> projectItems(Pointer<Void> h, String projectId, {int limit = 100}) =>
      (_memoryCall([projectId], (p) => _projectItems(h, p[0], limit))['payload'] as List)
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();

  List<TimelineEntry> projectTimeline(Pointer<Void> h, String projectId, {int limit = 100}) =>
      (_memoryCall([projectId], (p) => _projectTimeline(h, p[0], limit))['payload'] as List)
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList();
  RecallResponse recallQuery(Pointer<Void> h, String requestJson) => RecallResponse.fromJson(
      _memoryCall([requestJson], (p) => _recallQuery(h, p[0]))['payload'] as Map<String, dynamic>);

  int recallRebuild(Pointer<Void> h) => (_call(() => _recallRebuild(h))['payload'] as num).toInt();

  dynamic signal(Pointer<Void> h, String action, [dynamic payload]) =>
      _memoryCall([jsonEncode({'action': action, 'payload': payload})], (p) => _signal(h, p[0]))['payload'];

  dynamic consumer(Pointer<Void> h,String action,[dynamic payload])=>
      _memoryCall([jsonEncode({'action':action,'payload':payload})],(p)=>_consumer(h,p[0]))['payload'];

  dynamic knowledge(Pointer<Void> h,String action,[dynamic payload])=>
      _memoryCall([jsonEncode({'action':action,'payload':payload})],(p)=>_knowledge(h,p[0]))['payload'];

  dynamic integrations(Pointer<Void> h,String action,[dynamic payload])=>_memoryCall([jsonEncode({'action':action,'payload':payload})],(p)=>_integrations(h,p[0]))['payload'];

  dynamic margins(Pointer<Void> h,String action,[dynamic payload])=>_memoryCall([jsonEncode({'action':action,'payload':payload})],(p)=>_margins(h,p[0]))['payload'];

}
