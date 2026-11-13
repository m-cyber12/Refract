import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi.dart';
import 'models.dart';
import 'consumer_models.dart';
import 'knowledge_models.dart';
import 'margin_models.dart';
import 'integration_models.dart';

/// Owns the Rust store handle and exposes the library API to the UI.
class RefractRepository {
  RefractRepository._(this._bindings, this._handle, this._databasePath);

  final String _databasePath;
  bool _closed = false;

  final RefractBindings _bindings;
  final Pointer<Void> _handle;

  static Future<RefractRepository> create() async {
    final dir = await getApplicationSupportDirectory();
    return openLocal('${dir.path}/refract.db');
  }

  /// Open an explicitly supplied local path (also used by host-native tests).
  static RefractRepository openLocal(String path) {
    final bindings = RefractBindings.load();
    return RefractRepository._(bindings, bindings.open(path), path);
  }

  /// No native handle crosses isolates. This keeps ordinary capture work off
  /// the UI thread, but is not an OS sandbox or durable/background job queue.
  Future<Map<String, dynamic>> capture(String action, Map<String, dynamic> payload) {
    if (_closed) throw StateError('Repository is closed');
    final path = _databasePath;
    final request = jsonEncode({'action': action, 'payload': payload});
    return Isolate.run(() => _captureWorker(path, request));
  }

  /// Network and staging operations run on a separate isolate with their own
  /// store handle. A native request may remain active until its timeout.
  Future<Map<String, dynamic>> web(String action, Map<String, dynamic> payload) {
    if (_closed) throw StateError('Repository is closed');
    final path = _databasePath;
    final request = jsonEncode({'action': action, 'payload': payload});
    return Isolate.run(() => _webWorker(path, request));
  }

  Item importText(String text, {String? sourceUrl}) => _bindings.importText(_handle, text, sourceUrl);

  Item importHtml(String html, {String? sourceUrl}) => _bindings.importHtml(_handle, html, sourceUrl);

  Item importPdf(List<int> bytes, {String? sourceUrl}) => _bindings.importPdf(_handle, bytes, sourceUrl);

  List<Item> listItems({int limit = 50, int offset = 0}) => _bindings.listItems(_handle, limit: limit, offset: offset);

  Item? getItem(String id) => _bindings.getItem(_handle, id);

  List<Item> search(String query) => _bindings.search(_handle, query);
  List<Item> searchPage(String query, {int limit = 51, int offset = 0}) => _bindings.searchPage(_handle, query, limit: limit, offset: offset);

  Tag tagItem(String itemId, String tagName) => _bindings.tagItem(_handle, itemId, tagName);

  List<Tag> listTags() => _bindings.listTags(_handle);

  List<Tag> listItemTags(String itemId) => _bindings.listItemTags(_handle, itemId);

  Collection createCollection(String name) => _bindings.createCollection(_handle, name);

  List<Collection> listCollections() => _bindings.listCollections(_handle);

  void addToCollection(String itemId, String collectionId) => _bindings.addToCollection(_handle, itemId, collectionId);

  Annotation addAnnotation(String itemId, String quote, {String? note, int? blockIdx}) =>
      _bindings.addAnnotation(_handle, itemId, quote, note, blockIdx);

  List<Annotation> listAnnotations(String itemId) => _bindings.listAnnotations(_handle, itemId);

  String export() => _bindings.export(_handle);

  // ----- REFRACT SENSE -----

  CaptureDecisionRecord senseEvaluate(String itemId) => _bindings.senseEvaluate(_handle, itemId);

  List<CaptureDecisionRecord> senseDecisions({int limit = 50, int offset = 0}) => _bindings.senseDecisions(_handle, limit: limit, offset: offset);

  CaptureDecisionRecord senseReview(String decisionId, String action) => _bindings.senseReview(_handle, decisionId, action);

  List<SenseRule> senseRules() => _bindings.senseRules(_handle);

  SenseRule senseRuleUpsert(Map<String, dynamic> rule) => _bindings.senseRuleUpsert(_handle, rule);

  void senseRuleDelete(String ruleId) => _bindings.senseRuleDelete(_handle, ruleId);

  int sensePresetSet(String preset) => _bindings.sensePresetSet(_handle, preset);

  String senseSettingGet(String key) => _bindings.senseSettingGet(_handle, key);

  void senseSettingSet(String key, String value) => _bindings.senseSettingSet(_handle, key, value);

  List<Item> dailyEdition({int days = 7}) => _bindings.dailyEdition(_handle, days: days);

  Subscription addSubscription(Map<String, dynamic> subJson) => _bindings.addSubscription(_handle, subJson);

  List<Subscription> listSubscriptions() => _bindings.listSubscriptions(_handle);

  List<Subscription> upcomingEvents(int days) => _bindings.upcomingEvents(_handle, days);

  EvidenceRecord addEvidence(String kind, String? note, List<int> bytes, {String? textForClaims}) =>
      _bindings.addEvidence(_handle, kind, note, bytes, textForClaims);

  List<EvidenceRecord> listEvidence() => _bindings.listEvidence(_handle);

  List<EvidenceClaim> listClaims(String recordId) => _bindings.listClaims(_handle, recordId);

  bool? verifyEvidence(String id) => _bindings.verifyEvidence(_handle, id);

  Map<String, dynamic> summarize(String itemId, {int maxSentences = 3}) => _bindings.summarize(_handle, itemId, maxSentences);

  Map<String, dynamic> suggestTags(String itemId, {int maxTags = 5}) => _bindings.suggestTags(_handle, itemId, maxTags);

  List<Item> related(String itemId, {int limit = 5}) => _bindings.related(_handle, itemId, limit);

  String createWorkspace(String name) => _bindings.createWorkspace(_handle, name);

  List<List<String>> listWorkspaces() => _bindings.listWorkspaces(_handle);

  bool shareAnnotation(String workspaceId, String annotationId, Map<String, dynamic> payload) =>
      _bindings.shareAnnotation(_handle, workspaceId, annotationId, payload);

  int syncPending() => _bindings.syncPending(_handle);

  String? merkleRoot() => _bindings.merkleRoot(_handle);

  Map<String, dynamic>? merkleProof(String recordId) => _bindings.merkleProof(_handle, recordId);

  bool? verifyProof(String recordId) => _bindings.verifyProof(_handle, recordId);

  // ----- SMART MEMORY -----
  List<OrganizeReport> organizeLibrary() => _bindings.memoryOrganizeLibrary(_handle);
  List<Topic> topics() => _bindings.topicsList(_handle);
  Topic renameTopic(String id, String name) => _bindings.topicRename(_handle, id, name);
  Topic mergeTopics(String from, String to) => _bindings.topicMerge(_handle, from, to);
  void rejectTopic(String id) => _bindings.topicReject(_handle, id);
  void pinTopic(String id, bool pinned) => _bindings.topicPin(_handle, id, pinned);
  List<Item> topicItems(String id) => _bindings.topicItems(_handle, id);
  TopicEvolution topicEvolution(String id) => _bindings.topicEvolution(_handle, id);
  List<EntityRecord> entities() => _bindings.entitiesList(_handle);
  List<Relationship> relationships({String itemId = ''}) => _bindings.relationshipsList(_handle, itemId: itemId);
  void dismissRelationship(String id) => _bindings.relationshipDismiss(_handle, id);
  Relationship addRelationship(String source, String target, String kind, String basis) =>
      _bindings.relationshipAdd(_handle, {'source_item_id': source, 'target_item_id': target, 'kind': kind, 'basis': basis});
  List<TimelineEntry> memoryTimeline() => _bindings.memoryTimeline(_handle);
  void setItemTime(String id, String kind, int ts, String note) =>
      _bindings.itemTimeSet(_handle, {'item_id': id, 'kind': kind, 'ts': ts, 'note': note});
  List<Project> projects() => _bindings.projectsList(_handle);
  Project createProject(String name, String description) => _bindings.projectCreate(_handle, {'name': name, 'description': description});
  void deleteProject(String id) => _bindings.projectDelete(_handle, id);
  void projectAddItem(String projectId, String itemId) => _bindings.projectAddItem(_handle, projectId, itemId);
  void projectRemoveItem(String projectId, String itemId) => _bindings.projectRemoveItem(_handle, projectId, itemId);
  List<Item> projectItems(String id) => _bindings.projectItems(_handle, id);
  List<TimelineEntry> projectTimeline(String id) => _bindings.projectTimeline(_handle, id);

  RecallResponse recall(String requestJson) => _bindings.recallQuery(_handle, requestJson);
  int rebuildRecallIndex() => _bindings.recallRebuild(_handle);

  SignalConfig signalConfig() => SignalConfig.fromJson(_bindings.signal(_handle, 'config') as Map<String,dynamic>);
  void configureSignal(SignalConfig config) => _bindings.signal(_handle, 'configure', config.toJson());
  SignalEdition dailySignal({bool refresh = false}) => SignalEdition.fromJson(_bindings.signal(_handle, refresh ? 'refresh' : 'edition') as Map<String,dynamic>);
  void dismissSignal(String key) => _bindings.signal(_handle, 'dismiss', key);
  void resetSignalDismissals() => _bindings.signal(_handle, 'reset_dismissals');
  void reviewSignalEvent(String id, String status) => _bindings.signal(_handle, 'review_event', {'id':id,'status':status});
  SignalContext signalContext(String request) => SignalContext.fromJson(_bindings.signal(_handle, 'context', jsonDecode(request)) as Map<String,dynamic>);
  void saveReadingPlace(String itemId, int? blockIdx, String status) => _bindings.signal(_handle, 'reading', {'item_id':itemId,'block_idx':blockIdx,'status':status});
  void clearReadingPlaces() => _bindings.signal(_handle, 'clear_reading');

  List<ConsumerSummary> consumerDocuments()=>(_bindings.consumer(_handle,'documents') as List).map((v)=>ConsumerSummary.fromJson(v as Map<String,dynamic>)).toList();
  ConsumerDocument consumerDocument(String id)=>ConsumerDocument.fromJson(_bindings.consumer(_handle,'document',id) as Map<String,dynamic>);
  void consumerAnalyze(String id)=>_bindings.consumer(_handle,'scan',id);
  int consumerAnalyzeLibrary()=>(_bindings.consumer(_handle,'scan_library') as List).length;
  List<ConsumerClaim> consumerSearch(String request)=>(_bindings.consumer(_handle,'search',jsonDecode(request)) as List).map((v)=>ConsumerClaim.fromJson(v as Map<String,dynamic>)).toList();
  void consumerReview(String id,String status)=>_bindings.consumer(_handle,'review',{'id':id,'status':status});
  List<ConsumerReview> consumerHistory(String id)=>(_bindings.consumer(_handle,'history',id) as List).map((v)=>ConsumerReview.fromJson(v as Map<String,dynamic>)).toList();
  ConsumerComparison consumerCompare(String idsJson)=>ConsumerComparison.fromJson(_bindings.consumer(_handle,'compare',jsonDecode(idsJson)) as Map<String,dynamic>);
  ConsumerOriginalCheck consumerCheckOriginal(String id)=>ConsumerOriginalCheck.fromJson(_bindings.consumer(_handle,'check_original',id) as Map<String,dynamic>);
  Subscription consumerTrackSubscription(String id)=>Subscription.fromJson(_bindings.consumer(_handle,'track_subscription',id) as Map<String,dynamic>);

  List<DecisionRecord> decisions(String request)=>(_bindings.knowledge(_handle,'decisions',jsonDecode(request)) as List).map((v)=>DecisionRecord.fromJson(v as Map<String,dynamic>)).toList();
  DecisionRecord decision(String id)=>DecisionRecord.fromJson(_bindings.knowledge(_handle,'decision',id) as Map<String,dynamic>);
  DecisionRecord saveDecision(Map<String,dynamic> input)=>DecisionRecord.fromJson(_bindings.knowledge(_handle,'save_decision',input) as Map<String,dynamic>);
  void archiveDecision(String id,bool archived)=>_bindings.knowledge(_handle,'archive_decision',{'id':id,'archived':archived});
  List<DecisionRecord> decisionHistory(String id)=>(_bindings.knowledge(_handle,'decision_history',id) as List).map((v)=>DecisionRecord.fromJson(v as Map<String,dynamic>)).toList();
  KnowledgeGraph knowledgeGraph(String request)=>KnowledgeGraph.fromJson(_bindings.knowledge(_handle,'graph',jsonDecode(request)) as Map<String,dynamic>);
  Map<String,dynamic> knowledgePath(String request)=>_bindings.knowledge(_handle,'path',jsonDecode(request)) as Map<String,dynamic>;
  void dismissKnowledgeLink(String id)=>_bindings.knowledge(_handle,'dismiss_link',id);
  List<Map<String,dynamic>> compressions()=>(_bindings.knowledge(_handle,'compressions') as List).cast<Map<String,dynamic>>();
  Map<String,dynamic> compression(String id)=>_bindings.knowledge(_handle,'compression',id) as Map<String,dynamic>;
  Map<String,dynamic> createCompression(Map<String,dynamic> input)=>_bindings.knowledge(_handle,'compress',input) as Map<String,dynamic>;
  void regenerateCompression(String id)=>_bindings.knowledge(_handle,'regenerate_compression',id);
  void discardCompression(String id)=>_bindings.knowledge(_handle,'discard_compression',id);
  Map<String,dynamic> sourceIntelligence(String id)=>_bindings.knowledge(_handle,'source',id) as Map<String,dynamic>;
  void sourceSnapshot(String id)=>_bindings.knowledge(_handle,'source_snapshot',id);
  Map<String,dynamic> sourceDiff(String request)=>_bindings.knowledge(_handle,'source_diff',jsonDecode(request)) as Map<String,dynamic>;

  dynamic integrations(String action,[dynamic payload])=>_bindings.integrations(_handle,action,payload);

  dynamic margins(String action,[dynamic payload])=>_bindings.margins(_handle,action,payload);
  MarginContact marginContact()=>MarginContact.fromJson(margins('contact') as Map<String,dynamic>);
  List<MarginWorkspace> marginWorkspaces()=>(margins('workspaces') as List).map((v)=>MarginWorkspace.fromJson(v as Map<String,dynamic>)).toList();
  MarginWorkspace marginWorkspace(String id)=>MarginWorkspace.fromJson(margins('workspace',id) as Map<String,dynamic>);
  void dispose() {
    if (!_closed) { _closed = true; _bindings.close(_handle); }
  }
}

final repositoryProvider = Provider<RefractRepository>((ref) {
  throw UnimplementedError('Initialized asynchronously in main/bootstrap');
});

/// Async bootstrap provider: opens the local store before first use.
final bootstrapProvider = FutureProvider<RefractRepository>((ref) async {
  final repo = await RefractRepository.create();
  ref.onDispose(repo.dispose);
  return repo;
});

final senseDecisionsProvider = FutureProvider<List<CaptureDecisionRecord>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.senseDecisions(limit: 50);
});

final itemsProvider = FutureProvider<List<Item>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listItems();
});

/// One bounded library page plus one lookahead item. Offset pages are not a
/// snapshot: changes between requests can shift entries.
final libraryPageProvider = FutureProvider.autoDispose.family<List<Item>, int>((ref, offset) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listItems(limit: 51, offset: offset);
});

final itemProvider = FutureProvider.family<Item?, String>((ref, id) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.getItem(id);
});

final searchProvider = FutureProvider.family<List<Item>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.search(query);
});

final librarySearchPageProvider = FutureProvider.autoDispose.family<List<Item>, (String, int)>((ref, request) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.searchPage(request.$1, limit: 51, offset: request.$2);
});

final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listTags();
});

final annotationsProvider = FutureProvider.family<List<Annotation>, String>((ref, itemId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listAnnotations(itemId);
});

final dailyEditionProvider = FutureProvider<List<Item>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.dailyEdition(days: 7);
});

final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listSubscriptions();
});

final upcomingEventsProvider = FutureProvider<List<Subscription>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.upcomingEvents(30);
});

final evidenceProvider = FutureProvider<List<EvidenceRecord>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listEvidence();
});

final claimsProvider = FutureProvider.family<List<EvidenceClaim>, String>((ref, recordId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listClaims(recordId);
});

final summaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, itemId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.summarize(itemId);
});

final suggestedTagsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, itemId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.suggestTags(itemId);
});

final relatedProvider = FutureProvider.family<List<Item>, String>((ref, itemId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.related(itemId);
});

final workspacesProvider = FutureProvider<List<List<String>>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listWorkspaces();
});

final merkleRootProvider = FutureProvider<String?>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.merkleRoot();
});

final topicsProvider = FutureProvider<List<Topic>>((ref) async => (await ref.watch(bootstrapProvider.future)).topics());
final entitiesProvider = FutureProvider<List<EntityRecord>>((ref) async => (await ref.watch(bootstrapProvider.future)).entities());
final relationshipsProvider = FutureProvider<List<Relationship>>((ref) async => (await ref.watch(bootstrapProvider.future)).relationships());
final memoryTimelineProvider = FutureProvider<List<TimelineEntry>>((ref) async => (await ref.watch(bootstrapProvider.future)).memoryTimeline());
final projectsProvider = FutureProvider<List<Project>>((ref) async => (await ref.watch(bootstrapProvider.future)).projects());
final topicItemsProvider = FutureProvider.family<List<Item>, String>((ref, id) async => (await ref.watch(bootstrapProvider.future)).topicItems(id));
final topicEvolutionProvider = FutureProvider.family<TopicEvolution, String>((ref, id) async => (await ref.watch(bootstrapProvider.future)).topicEvolution(id));
final projectItemsProvider = FutureProvider.family<List<Item>, String>((ref, id) async => (await ref.watch(bootstrapProvider.future)).projectItems(id));
final projectTimelineProvider = FutureProvider.family<List<TimelineEntry>, String>((ref, id) async => (await ref.watch(bootstrapProvider.future)).projectTimeline(id));

final recallProvider = FutureProvider.family<RecallResponse, String>((ref, requestJson) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.recall(requestJson);
});

final signalConfigProvider = FutureProvider<SignalConfig>((ref) async => (await ref.watch(bootstrapProvider.future)).signalConfig());
final dailySignalProvider = FutureProvider<SignalEdition>((ref) async => (await ref.watch(bootstrapProvider.future)).dailySignal());
final signalContextProvider = FutureProvider.family<SignalContext,String>((ref, request) async => (await ref.watch(bootstrapProvider.future)).signalContext(request));

final consumerDocumentsProvider=FutureProvider<List<ConsumerSummary>>((ref)async=>(await ref.watch(bootstrapProvider.future)).consumerDocuments());
final consumerDocumentProvider=FutureProvider.family<ConsumerDocument,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).consumerDocument(id));
final consumerSearchProvider=FutureProvider.family<List<ConsumerClaim>,String>((ref,request)async=>(await ref.watch(bootstrapProvider.future)).consumerSearch(request));
final consumerCompareProvider=FutureProvider.family<ConsumerComparison,String>((ref,ids)async=>(await ref.watch(bootstrapProvider.future)).consumerCompare(ids));
final consumerHistoryProvider=FutureProvider.family<List<ConsumerReview>,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).consumerHistory(id));

final decisionsProvider=FutureProvider.family<List<DecisionRecord>,String>((ref,q)async=>(await ref.watch(bootstrapProvider.future)).decisions(q));
final decisionProvider=FutureProvider.family<DecisionRecord,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).decision(id));
final decisionHistoryProvider=FutureProvider.family<List<DecisionRecord>,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).decisionHistory(id));
final knowledgeGraphProvider=FutureProvider.family<KnowledgeGraph,String>((ref,q)async=>(await ref.watch(bootstrapProvider.future)).knowledgeGraph(q));
final knowledgePathProvider=FutureProvider.family<Map<String,dynamic>,String>((ref,q)async=>(await ref.watch(bootstrapProvider.future)).knowledgePath(q));
final compressionsProvider=FutureProvider<List<Map<String,dynamic>>>((ref)async=>(await ref.watch(bootstrapProvider.future)).compressions());
final compressionProvider=FutureProvider.family<Map<String,dynamic>,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).compression(id));
final sourceIntelligenceProvider=FutureProvider.family<Map<String,dynamic>,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).sourceIntelligence(id));
final sourceDiffProvider=FutureProvider.family<Map<String,dynamic>,String>((ref,q)async=>(await ref.watch(bootstrapProvider.future)).sourceDiff(q));

final collectionsProvider=FutureProvider<List<Collection>>((ref)async=>(await ref.watch(bootstrapProvider.future)).listCollections());

final marginContactProvider=FutureProvider<MarginContact>((ref)async=>(await ref.watch(bootstrapProvider.future)).marginContact());
final marginWorkspacesProvider=FutureProvider<List<MarginWorkspace>>((ref)async=>(await ref.watch(bootstrapProvider.future)).marginWorkspaces());
final marginWorkspaceProvider=FutureProvider.family<MarginWorkspace,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).marginWorkspace(id));
final marginHistoryProvider=FutureProvider.family<Map<String,dynamic>,String>((ref,id)async=>(await ref.watch(bootstrapProvider.future)).margins('history',id) as Map<String,dynamic>);
final marginTransfersProvider=FutureProvider.family<List<Map<String,dynamic>>,String>((ref,id)async=>((await ref.watch(bootstrapProvider.future)).margins('transfers',id) as List).cast<Map<String,dynamic>>());
final marginPeersProvider=FutureProvider.family<List<MarginMember>,String>((ref,id)async=>((await ref.watch(bootstrapProvider.future)).margins('peers',id) as List).map((v)=>MarginMember.fromJson(v as Map<String,dynamic>)).toList());

final integrationCatalogProvider=FutureProvider<List<IntegrationCapability>>((ref)async=>((await ref.watch(bootstrapProvider.future)).integrations('catalog') as List).map((v)=>IntegrationCapability.fromJson(Map<String,dynamic>.from(v as Map))).toList());
final integrationCalendarProvider=FutureProvider<IntegrationCalendarCandidates>((ref)async=>IntegrationCalendarCandidates.fromJson((await ref.watch(bootstrapProvider.future)).integrations('calendar_candidates') as Map<String,dynamic>));

final integrationCopiesProvider=FutureProvider<List<Map<String,dynamic>>>((ref)async=>((await ref.watch(bootstrapProvider.future)).integrations('email_copies') as List).map((v)=>Map<String,dynamic>.from(v as Map)).toList());

Map<String, dynamic> _captureWorker(String path, String request) {
  final bindings = RefractBindings.load();
  final handle = bindings.open(path);
  try { return bindings.capture(handle, request); } finally { bindings.close(handle); }
}

Map<String, dynamic> _webWorker(String path, String request) {
  final bindings = RefractBindings.load();
  final handle = bindings.open(path);
  try { return bindings.web(handle, request); } finally { bindings.close(handle); }
}
