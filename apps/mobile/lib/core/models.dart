library;

/// Data model mirroring the Rust core's JSON contract (crates/refract_core).

enum SourceType { url, sharedText, html, pdf, markdown, text, file }

SourceType sourceTypeFromString(String s) => switch (s) {
      'url' => SourceType.url,
      'shared_text' => SourceType.sharedText,
      'html' => SourceType.html,
      'pdf' => SourceType.pdf,
      'markdown' => SourceType.markdown,
      'file' => SourceType.file,
      _ => SourceType.text,
    };

String sourceTypeLabel(SourceType t) => switch (t) {
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

class RefractFailure implements Exception {
  RefractFailure(this.message);
  final String message;
  @override
  String toString() => 'RefractFailure: $message';
}
