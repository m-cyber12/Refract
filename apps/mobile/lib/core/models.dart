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
      title ?? (sourceUrl != null ? 'Imported ${sourceType.name}' : 'Untitled note');

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

class RefractFailure implements Exception {
  RefractFailure(this.message);
  final String message;
  @override
  String toString() => 'RefractFailure: $message';
}
