library;

import 'knowledge_models.dart';

/// Data model mirroring the Rust core's JSON contract (crates/refract_core).

enum SourceType { emailCopy, url, sharedText, html, pdf, markdown, text, file }

SourceType sourceTypeFromString(String s) => switch (s) {
      'email_copy' => SourceType.emailCopy,
      'url' => SourceType.url,
      'shared_text' => SourceType.sharedText,
      'html' => SourceType.html,
      'pdf' => SourceType.pdf,
      'markdown' => SourceType.markdown,
      'file' => SourceType.file,
      _ => SourceType.text,
    };

String sourceTypeLabel(SourceType t) => switch (t) {
      SourceType.emailCopy => 'Selected email copy',
      SourceType.url => 'URL',
      SourceType.sharedText => 'Shared text',
      SourceType.html => 'HTML',
      SourceType.pdf => 'PDF',
      SourceType.markdown => 'Markdown',
      SourceType.text => 'Text',
      SourceType.file => 'File',
    };

enum ImportStatus { processing, ready, failed }

enum BlockKind {
  heading1, heading2, heading3, paragraph, listItem, quote, code, image, divider,
}

BlockKind blockKindFromString(String s) => switch (s) {
      'heading1' => BlockKind.heading1,
      'heading2' => BlockKind.heading2,
      'heading3' => BlockKind.heading3,
      'list_item' => BlockKind.listItem,
      'quote' => BlockKind.quote,
      'code' => BlockKind.code,
      'image' => BlockKind.image,
      'divider' => BlockKind.divider,
      _ => BlockKind.paragraph,
    };

class Block {
  Block({required this.idx, required this.kind, required this.text});

  final int idx;
  final BlockKind kind;
  final String text;

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        idx: (j['idx'] as num).toInt(),
        kind: blockKindFromString(j['kind'] as String),
        text: j['text'] as String,
      );
}

class Item {
  Item({
    required this.id,
    required this.sourceType,
    required this.importTs,
    required this.contentHash,
    required this.extractionConfidence,
    required this.status,
    required this.blocks,
    this.sourceUrl,
    this.title,
    this.author,
    this.language,
  });

  final String id;
  final SourceType sourceType;
  final int importTs;
  final String contentHash;
  final double extractionConfidence;
  final ImportStatus status;
  final List<Block> blocks;
  final String? sourceUrl;
  final String? title;
  final String? author;
  final String? language;

  String get displayTitle =>
      title ?? (sourceUrl != null ? 'Imported ${sourceTypeLabel(sourceType)}' : 'Untitled note');

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        sourceType: sourceTypeFromString(j['source_type'] as String),
        importTs: (j['import_ts'] as num).toInt(),
        contentHash: j['content_hash'] as String,
        extractionConfidence: (j['extraction_confidence'] as num).toDouble(),
        status: switch (j['status'] as String) {
          'processing' => ImportStatus.processing,
          'failed' => ImportStatus.failed,
          _ => ImportStatus.ready,
        },
        blocks: ((j['blocks'] as List?) ?? [])
            .map((b) => Block.fromJson(b as Map<String, dynamic>))
            .toList(),
        sourceUrl: j['source_url'] as String?,
        title: j['title'] as String?,
        author: j['author'] as String?,
        language: j['language'] as String?,
      );
}

class Tag {
  Tag({required this.id, required this.name, this.color});
  final String id;
  final String name;
  final String? color;
  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as String?,
      );
}

class Collection {
  Collection({required this.id, required this.name, required this.createdTs});
  final String id;
  final String name;
  final int createdTs;
  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'] as String,
        name: j['name'] as String,
        createdTs: (j['created_ts'] as num).toInt(),
      );
}

class Annotation {
  Annotation({
    required this.id,
    required this.itemId,
    required this.quote,
    required this.visibility,
    required this.createdTs,
    this.note,
    this.blockIdx,
  });
  final String id;
  final String itemId;
  final String quote;
  final String? note;
  final int? blockIdx;
  final String visibility;
  final int createdTs;
  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        quote: j['quote'] as String,
        note: j['note'] as String?,
        blockIdx: (j['block_idx'] as num?)?.toInt(),
        visibility: j['visibility'] as String,
        createdTs: (j['created_ts'] as num).toInt(),
      );
}

enum SubscriptionStatus { confirmed, imported, suspected, unverified }

String subscriptionStatusLabel(SubscriptionStatus s) => switch (s) {
      SubscriptionStatus.confirmed => 'confirmed',
      SubscriptionStatus.imported => 'imported',
      SubscriptionStatus.suspected => 'suspected',
      SubscriptionStatus.unverified => 'unverified',
    };

class Subscription {
  Subscription({
    required this.id,
    required this.service,
    required this.status,
    required this.confidence,
    required this.createdTs,
    this.plan,
    this.price,
    this.currency,
    this.frequency,
    this.renewalDate,
    this.trialEnd,
    this.sourceDocId,
  });

  final String id;
  final String service;
  final String? plan;
  final double? price;
  final String? currency;
  final String? frequency;
  final int? renewalDate;
  final int? trialEnd;
  final SubscriptionStatus status;
  final double confidence;
  final String? sourceDocId;
  final int createdTs;

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        service: j['service'] as String,
        plan: j['plan'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        frequency: j['frequency'] as String?,
        renewalDate: (j['renewal_date'] as num?)?.toInt(),
        trialEnd: (j['trial_end'] as num?)?.toInt(),
        status: switch (j['status'] as String) {
          'confirmed' => SubscriptionStatus.confirmed,
          'imported' => SubscriptionStatus.imported,
          'suspected' => SubscriptionStatus.suspected,
          _ => SubscriptionStatus.unverified,
        },
        confidence: (j['confidence'] as num).toDouble(),
        sourceDocId: j['source_doc_id'] as String?,
        createdTs: (j['created_ts'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'service': service,
        'plan': plan,
        'price': price,
        'currency': currency,
        'frequency': frequency,
        'renewal_date': renewalDate,
        'trial_end': trialEnd,
        'status': switch (status) {
          SubscriptionStatus.confirmed => 'confirmed',
          SubscriptionStatus.imported => 'imported',
          SubscriptionStatus.suspected => 'suspected',
          SubscriptionStatus.unverified => 'unverified',
        },
        'confidence': confidence,
        'source_doc_id': sourceDocId,
        'created_ts': createdTs,
      };
}

class EvidenceRecord {
  EvidenceRecord({
    required this.id,
    required this.kind,
    required this.blobPath,
    required this.sha256,
    required this.importedTs,
    this.note,
  });

  final String id;
  final String kind;
  final String? note;
  final String blobPath;
  final String sha256;
  final int importedTs;

  factory EvidenceRecord.fromJson(Map<String, dynamic> j) => EvidenceRecord(
        id: j['id'] as String,
        kind: j['kind'] as String,
        note: j['note'] as String?,
        blobPath: j['blob_path'] as String,
        sha256: j['sha256'] as String,
        importedTs: (j['imported_ts'] as num).toInt(),
      );
}

class EvidenceClaim {
  EvidenceClaim({
    required this.id,
    required this.recordId,
    required this.claimType,
    required this.text,
    required this.confidence,
    this.offset,
  });

  final String id;
  final String recordId;
  final String claimType; // quote | extracted | interpretation
  final String text;
  final int? offset;
  final double confidence;

  factory EvidenceClaim.fromJson(Map<String, dynamic> j) => EvidenceClaim(
        id: j['id'] as String,
        recordId: j['record_id'] as String,
        claimType: j['claim_type'] as String,
        text: j['text'] as String,
        offset: (j['offset'] as num?)?.toInt(),
        confidence: (j['confidence'] as num).toDouble(),
      );
}

/// REFRACT SENSE — one editable capture policy rule (spec §3.3).
class SenseRule {
  SenseRule({
    required this.id,
    required this.name,
    required this.kind,
    required this.pattern,
    required this.enabled,
    required this.preset,
    required this.createdTs,
  });

  final String id;
  final String name;
  final String kind; // allow_source | deny_source | allow_category | confirm_category
  final String pattern;
  final bool enabled;
  final String preset;
  final int createdTs;

  factory SenseRule.fromJson(Map<String, dynamic> j) => SenseRule(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        pattern: j['pattern'] as String,
        enabled: (j['enabled'] as bool?) ?? true,
        preset: (j['preset'] as String?) ?? 'custom',
        createdTs: (j['created_ts'] as num?)?.toInt() ?? 0,
      );
}

/// REFRACT SENSE — one logged pipeline decision with review/undo state.
class CaptureDecisionRecord {
  CaptureDecisionRecord({
    required this.id,
    this.itemId,
    required this.decision,
    required this.score,
    required this.category,
    required this.explanation,
    this.ruleId,
    required this.ts,
    required this.undone,
  });

  final String id;
  final String? itemId;
  final String decision; // auto_save | smart_suggest | ignore
  final double score;
  final String category;
  final String explanation;
  final String? ruleId;
  final int ts;
  final bool undone;

  factory CaptureDecisionRecord.fromJson(Map<String, dynamic> j) => CaptureDecisionRecord(
        id: j['id'] as String,
        itemId: j['item_id'] as String?,
        decision: j['decision'] as String,
        score: (j['score'] as num).toDouble(),
        category: j['category'] as String,
        explanation: j['explanation'] as String,
        ruleId: j['rule_id'] as String?,
        ts: (j['ts'] as num).toInt(),
        undone: (j['undone'] as bool?) ?? false,
      );
}

/// SMART MEMORY — an identified topic (spec §5.2). Origin is 'automatic'
/// or 'user'; user topics survive re-organization.
class Topic {
  Topic({
    required this.id,
    required this.name,
    required this.origin,
    required this.createdTs,
    required this.pinned,
    required this.itemCount,
  });

  final String id;
  final String name;
  final String origin;
  final int createdTs;
  final bool pinned;
  final int itemCount;

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        id: j['id'] as String,
        name: j['name'] as String,
        origin: (j['origin'] as String?) ?? 'automatic',
        createdTs: (j['created_ts'] as num?)?.toInt() ?? 0,
        pinned: (j['pinned'] as bool?) ?? false,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      );
}

/// SMART MEMORY — an extracted entity (person/organization/date/email/...).
class EntityRecord {
  EntityRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdTs,
    required this.itemCount,
  });

  final String id;
  final String name;
  final String kind;
  final int createdTs;
  final int itemCount;

  factory EntityRecord.fromJson(Map<String, dynamic> j) => EntityRecord(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        createdTs: (j['created_ts'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      );
}

/// SMART MEMORY — a relationship suggestion. Every link carries a
/// human-readable basis and a confidence level (spec §5.3); weak similarity
/// is never presented as fact and users can dismiss any connection.
class Relationship {
  Relationship({
    required this.id,
    required this.sourceItemId,
    required this.targetItemId,
    required this.kind,
    required this.basis,
    required this.confidence,
    required this.dismissed,
    required this.createdTs,
  });

  final String id;
  final String sourceItemId;
  final String targetItemId;
  final String kind;
  final String basis;
  final double confidence;
  final bool dismissed;
  final int createdTs;

  factory Relationship.fromJson(Map<String, dynamic> j) => Relationship(
        id: j['id'] as String,
        sourceItemId: j['source_item_id'] as String,
        targetItemId: j['target_item_id'] as String,
        kind: j['kind'] as String,
        basis: j['basis'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        dismissed: (j['dismissed'] as bool?) ?? false,
        createdTs: (j['created_ts'] as num?)?.toInt() ?? 0,
      );
}

/// SMART MEMORY — one Memory Timeline entry. timeKind strictly distinguishes
/// capture / publication / modification / event / deadline (spec §5.4).
class TimelineEntry {
  TimelineEntry({
    required this.itemId,
    required this.title,
    required this.timeKind,
    required this.ts,
    this.note,
  });

  final String itemId;
  final String title;
  final String timeKind;
  final int ts;
  final String? note;

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        itemId: j['item_id'] as String,
        title: j['title'] as String,
        timeKind: j['time_kind'] as String,
        ts: (j['ts'] as num).toInt(),
        note: j['note'] as String?,
      );
}

/// KNOWLEDGE EVOLUTION — one descriptive stage of a topic's development.
class EvolutionStage {
  EvolutionStage({
    required this.fromTs,
    required this.toTs,
    required this.itemCount,
    required this.description,
    required this.itemIds,
  });

  final int fromTs;
  final int toTs;
  final int itemCount;
  final String description;
  final List<String> itemIds;

  factory EvolutionStage.fromJson(Map<String, dynamic> j) => EvolutionStage(
        fromTs: (j['from_ts'] as num).toInt(),
        toTs: (j['to_ts'] as num).toInt(),
        itemCount: (j['item_count'] as num).toInt(),
        description: j['description'] as String,
        itemIds: (j['item_ids'] as List).map((e) => e as String).toList(),
      );
}

class TopicEvolution {
  TopicEvolution({required this.topic, required this.stages, required this.summary});

  final Topic topic;
  final List<EvolutionStage> stages;
  final String summary;

  factory TopicEvolution.fromJson(Map<String, dynamic> j) => TopicEvolution(
        topic: Topic.fromJson(j['topic'] as Map<String, dynamic>),
        stages: (j['stages'] as List).map((e) => EvolutionStage.fromJson(e as Map<String, dynamic>)).toList(),
        summary: j['summary'] as String,
      );
}

/// PROJECT SPACES — a named space grouping items with its own timeline.
class Project {
  Project({
    required this.id,
    required this.name,
    this.description,
    required this.createdTs,
    required this.itemCount,
  });

  final String id;
  final String name;
  final String? description;
  final int createdTs;
  final int itemCount;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        createdTs: (j['created_ts'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      );
}

/// SMART MEMORY — result of automatic organization for one item.
class OrganizeReport {
  OrganizeReport({
    required this.itemId,
    required this.topics,
    required this.entities,
    required this.relationshipsSuggested,
  });

  final String itemId;
  final List<String> topics;
  final List<String> entities;
  final int relationshipsSuggested;

  factory OrganizeReport.fromJson(Map<String, dynamic> j) => OrganizeReport(
        itemId: j['item_id'] as String,
        topics: (j['topics'] as List).map((e) => e as String).toList(),
        entities: (j['entities'] as List).map((e) => e as String).toList(),
        relationshipsSuggested: (j['relationships_suggested'] as num).toInt(),
      );
}

/// A verbatim source excerpt (or explicitly marked metadata-only evidence).
class RecallEvidence {
  RecallEvidence({required this.itemId, required this.title, this.sourceUrl, this.blockIdx, required this.quote, required this.kind});
  final String itemId;
  final String title;
  final String? sourceUrl;
  final int? blockIdx;
  final String quote;
  final String kind;
  factory RecallEvidence.fromJson(Map<String, dynamic> j) => RecallEvidence(
    itemId: j['item_id'] as String, title: j['title'] as String,
    sourceUrl: j['source_url'] as String?, blockIdx: (j['block_idx'] as num?)?.toInt(),
    quote: j['quote'] as String, kind: j['kind'] as String,
  );
}

class RecallHit {
  RecallHit({required this.itemId, required this.title, required this.sourceType, required this.capturedTs, required this.score, required this.reasons, required this.evidence, required this.supportingPassages});
  final String itemId;
  final String title;
  final String sourceType;
  final int capturedTs;
  final double score;
  final List<String> reasons;
  final RecallEvidence evidence;
  final List<RecallEvidence> supportingPassages;
  factory RecallHit.fromJson(Map<String, dynamic> j) => RecallHit(
    itemId: j['item_id'] as String, title: j['title'] as String, sourceType: j['source_type'] as String,
    capturedTs: (j['captured_ts'] as num).toInt(), score: (j['score'] as num).toDouble(),
    supportingPassages: ((j['supporting_passages'] as List?) ?? []).map((v) => RecallEvidence.fromJson(v as Map<String, dynamic>)).toList(),
    reasons: (j['reasons'] as List).cast<String>(), evidence: RecallEvidence.fromJson(j['evidence'] as Map<String, dynamic>),
  );
}

class RecallResponse {
  RecallResponse({required this.query, required this.mode, required this.answer, required this.answerKind, required this.modelUsed, required this.encoder, required this.hits, this.decisionRecords = const [], required this.connections, required this.timeline, required this.limitations, required this.scannedItems});
  final String query;
  final String mode;
  final String answer;
  final String answerKind;
  final bool modelUsed;
  final String encoder;
  final List<RecallHit> hits;
  final List<DecisionRecord> decisionRecords;
  final List<Relationship> connections;
  final List<TimelineEntry> timeline;
  final List<String> limitations;
  final int scannedItems;
  factory RecallResponse.fromJson(Map<String, dynamic> j) => RecallResponse(
    query: j['query'] as String, mode: j['mode'] as String, answer: j['answer'] as String,
    answerKind: j['answer_kind'] as String, modelUsed: j['model_used'] as bool, encoder: j['encoder'] as String,
    hits: (j['hits'] as List).map((v) => RecallHit.fromJson(v as Map<String, dynamic>)).toList(),
    decisionRecords: ((j['decision_records'] as List?) ?? []).map((v) => DecisionRecord.fromJson(v as Map<String,dynamic>)).toList(),
    connections: (j['connections'] as List).map((v) => Relationship.fromJson(v as Map<String, dynamic>)).toList(),
    timeline: (j['timeline'] as List).map((v) => TimelineEntry.fromJson(v as Map<String, dynamic>)).toList(),
    limitations: (j['limitations'] as List).cast<String>(), scannedItems: (j['scanned_items'] as num).toInt(),
  );
}

class SignalConfig {
  SignalConfig({required this.enabled, required this.contextEnabled, required this.frequency, required this.lookbackDays, required this.upcomingDays, required this.maxPerSection, required this.showUnconfirmed, required this.sections});
  final bool enabled;
  final bool contextEnabled;
  final String frequency;
  final int lookbackDays;
  final int upcomingDays;
  final int maxPerSection;
  final bool showUnconfirmed;
  final List<String> sections;
  factory SignalConfig.fromJson(Map<String, dynamic> j) => SignalConfig(
    enabled: j['enabled'] as bool, contextEnabled: j['context_enabled'] as bool, frequency: j['frequency'] as String,
    lookbackDays: (j['lookback_days'] as num).toInt(), upcomingDays: (j['upcoming_days'] as num).toInt(), maxPerSection: (j['max_per_section'] as num).toInt(), showUnconfirmed: j['show_unconfirmed'] as bool, sections: (j['sections'] as List).cast<String>(),
  );
  Map<String, dynamic> toJson() => {'enabled': enabled, 'context_enabled': contextEnabled, 'frequency': frequency, 'lookback_days': lookbackDays, 'upcoming_days': upcomingDays, 'max_per_section': maxPerSection, 'show_unconfirmed': showUnconfirmed, 'sections': sections};
  SignalConfig changed(String key, dynamic value) => SignalConfig.fromJson({...toJson(), key: value});
}

class SignalEntry {
  SignalEntry({required this.key, required this.section, required this.title, required this.explanation, required this.itemIds, this.projectId, this.blockIdx, this.ts, required this.status});
  final String key;
  final String section;
  final String title;
  final String explanation;
  final List<String> itemIds;
  final String? projectId;
  final int? blockIdx;
  final int? ts;
  final String status;
  factory SignalEntry.fromJson(Map<String, dynamic> j) => SignalEntry(key:j['key'] as String, section:j['section'] as String, title:j['title'] as String, explanation:j['explanation'] as String, itemIds:(j['item_ids'] as List).cast<String>(), projectId:j['project_id'] as String?, blockIdx:(j['block_idx'] as num?)?.toInt(), ts:(j['ts'] as num?)?.toInt(), status:j['status'] as String);
}

class SignalEvent {
  SignalEvent({required this.id, required this.itemId, required this.blockIdx, required this.title, required this.eventTs, required this.category, required this.confidence, required this.evidence, required this.extractedTs, required this.status});
  final String id;
  final String itemId;
  final int blockIdx;
  final String title;
  final int eventTs;
  final String category;
  final double confidence;
  final String evidence;
  final int extractedTs;
  final String status;
  factory SignalEvent.fromJson(Map<String, dynamic> j) => SignalEvent(id:j['id'] as String,itemId:j['item_id'] as String,blockIdx:(j['block_idx'] as num).toInt(),title:j['title'] as String,eventTs:(j['event_ts'] as num).toInt(),category:j['category'] as String,confidence:(j['confidence'] as num).toDouble(),evidence:j['evidence'] as String,extractedTs:(j['extracted_ts'] as num).toInt(),status:j['status'] as String);
}

class SignalEdition {
  SignalEdition({required this.generatedTs, this.nextRefreshTs, required this.enabled, required this.entries, required this.events, required this.quiet, required this.message, required this.limitations});
  final int generatedTs;
  final int? nextRefreshTs;
  final bool enabled;
  final List<SignalEntry> entries;
  final List<SignalEvent> events;
  final bool quiet;
  final String message;
  final List<String> limitations;
  factory SignalEdition.fromJson(Map<String, dynamic> j) => SignalEdition(generatedTs:(j['generated_ts'] as num).toInt(),nextRefreshTs:(j['next_refresh_ts'] as num?)?.toInt(),enabled:j['enabled'] as bool,entries:(j['entries'] as List).map((e)=>SignalEntry.fromJson(e as Map<String,dynamic>)).toList(),events:(j['events'] as List).map((e)=>SignalEvent.fromJson(e as Map<String,dynamic>)).toList(),quiet:j['quiet'] as bool,message:j['message'] as String,limitations:(j['limitations'] as List).cast<String>());
}

class SignalContext {
  SignalContext({required this.enabled,required this.entries,required this.events,required this.message});
  final bool enabled;
  final List<SignalEntry> entries;
  final List<SignalEvent> events;
  final String message;
  factory SignalContext.fromJson(Map<String,dynamic> j)=>SignalContext(enabled:j['enabled'] as bool,entries:(j['entries'] as List).map((e)=>SignalEntry.fromJson(e as Map<String,dynamic>)).toList(),events:(j['events'] as List).map((e)=>SignalEvent.fromJson(e as Map<String,dynamic>)).toList(),message:j['message'] as String);
}

class RefractFailure implements Exception {
  RefractFailure(this.message);
  final String message;
  @override
  String toString() => 'RefractFailure: $message';
}
