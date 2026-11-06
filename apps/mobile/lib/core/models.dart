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

class RefractFailure implements Exception {
  RefractFailure(this.message);
  final String message;
  @override
  String toString() => 'RefractFailure: $message';
}
