import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi.dart';
import 'models.dart';

/// Owns the Rust store handle and exposes the library API to the UI.
class RefractRepository {
  RefractRepository._(this._bindings, this._handle);

  final RefractBindings _bindings;
  final Pointer<Void> _handle;

  static Future<RefractRepository> create() async {
    final dir = await getApplicationSupportDirectory();
    final bindings = RefractBindings.load();
    final handle = bindings.open('${dir.path}/refract.db');
    return RefractRepository._(bindings, handle);
  }

  Item importText(String text, {String? sourceUrl}) => _bindings.importText(_handle, text, sourceUrl);

  Item importHtml(String html, {String? sourceUrl}) => _bindings.importHtml(_handle, html, sourceUrl);

  Item importPdf(List<int> bytes, {String? sourceUrl}) => _bindings.importPdf(_handle, bytes, sourceUrl);

  List<Item> listItems({int limit = 50, int offset = 0}) => _bindings.listItems(_handle, limit: limit, offset: offset);

  Item? getItem(String id) => _bindings.getItem(_handle, id);

  List<Item> search(String query) => _bindings.search(_handle, query);

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

  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      _bindings.close(_handle);
    }
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

final itemProvider = FutureProvider.family<Item?, String>((ref, id) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.getItem(id);
});

final searchProvider = FutureProvider.family<List<Item>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.search(query);
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
