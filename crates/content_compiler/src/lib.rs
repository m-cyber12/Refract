//! Reality Compiler engine (System A, A2).
//!
//! Pipeline: acquisition -> extraction -> sanitization -> metadata ->
//! structure -> noise classification -> normalization -> compiled document.
//!
//! The original bytes are hashed (SHA-256) and must be stored untouched
//! alongside the transformed representation; this crate never mutates input.

use document_parser::ParsedDocument;
use refract_core::{Block, Item, RefractError, RefractResult, SourceType};
use sha2::{Digest, Sha256};

/// Raw input handed to the compiler.
pub struct ContentInput {
    pub source_type: SourceType,
    pub source_url: Option<String>,
    /// Original, unmodified bytes. For text inputs this is the UTF-8 text.
    pub raw: Vec<u8>,
}

/// A fully compiled document, ready for storage.
pub struct CompiledDocument {
    pub item: Item,
    /// SHA-256 hex of the original bytes.
    pub original_hash: String,
    /// Original bytes to persist as the immutable "original" blob.
    pub original_bytes: Vec<u8>,
    /// Normalized plain text of the transformed representation.
    pub transformed_text: String,
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    hex_encode(&h.finalize())
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Run the full pipeline for one input.
pub fn compile(input: &ContentInput, import_ts: i64) -> RefractResult<CompiledDocument> {
    let original_hash = sha256_hex(&input.raw);

    let text = std::str::from_utf8(&input.raw)
        .map_err(|_| RefractError::invalid("input is not valid UTF-8"))?;

    let parsed: ParsedDocument = match input.source_type {
        SourceType::Html | SourceType::Url | SourceType::File => document_parser::parse_html(text)?,
        SourceType::Markdown => document_parser::parse_markdown(text)?,
        SourceType::Pdf => document_parser::parse_pdf(&input.raw)?,
        SourceType::SharedText | SourceType::Text | SourceType::EmailCopy => document_parser::parse_text(text)?,
    };

    // Normalization is already applied per block by the parsers; here we
    // compute a heuristic extraction confidence and finalize the item.
    let confidence = confidence(&parsed);

    let title = parsed
        .title
        .clone()
        .or_else(|| first_heading(&parsed.blocks).map(|h| h.text.clone()))
        .or_else(|| {
            let t = parsed.plain_text.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.chars().take(80).collect())
            }
        });

    let item = Item {
        id: uuid::Uuid::new_v4().to_string(),
        source_url: input.source_url.clone(),
        source_type: input.source_type,
        import_ts,
        content_hash: original_hash.clone(),
        title,
        author: parsed.author.clone(),
        language: parsed.language.clone(),
        extraction_confidence: confidence,
        status: refract_core::ImportStatus::Ready,
        blocks: parsed.blocks.clone(),
    };

    Ok(CompiledDocument {
        item,
        original_hash,
        original_bytes: input.raw.clone(),
        transformed_text: parsed.plain_text,
    })
}

fn first_heading(blocks: &[Block]) -> Option<&Block> {
    blocks.iter().find(|b| {
        matches!(
            b.kind,
            refract_core::BlockKind::Heading1
                | refract_core::BlockKind::Heading2
                | refract_core::BlockKind::Heading3
        )
    })
}

/// Heuristic confidence: share of blocks that are real content (not images),
/// scaled by whether we found a title and a reasonable amount of text.
fn confidence(doc: &ParsedDocument) -> f32 {
    if doc.blocks.is_empty() {
        return 0.0;
    }
    let content_blocks = doc
        .blocks
        .iter()
        .filter(|b| b.kind != refract_core::BlockKind::Image)
        .count() as f32;
    let ratio = content_blocks / doc.blocks.len() as f32;
    let length_factor = (doc.plain_text.len() as f32 / 2000.0).min(1.0);
    let title_bonus = if doc.title.is_some() { 0.1 } else { 0.0 };
    (ratio * 0.6 + length_factor * 0.3 + title_bonus).min(1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compiles_html_end_to_end() {
        let html = "<html><head><title>Doc</title></head><body><article>\
            <h1>Title</h1><p>Some body text here.</p><script>x()</script></article></body></html>";
        let input = ContentInput {
            source_type: SourceType::Html,
            source_url: Some("https://example.com/a".into()),
            raw: html.as_bytes().to_vec(),
        };
        let out = compile(&input, 1_700_000_000).unwrap();
        assert_eq!(out.item.title.as_deref(), Some("Doc"));
        assert_eq!(out.item.blocks.len(), 2);
        assert!(out.item.extraction_confidence > 0.0);
        assert_eq!(out.original_hash.len(), 64);
        assert_eq!(out.original_bytes, html.as_bytes());
    }

    #[test]
    fn compiles_plain_text() {
        let input = ContentInput {
            source_type: SourceType::Text,
            source_url: None,
            raw: b"Hello world.\n\nSecond paragraph.".to_vec(),
        };
        let out = compile(&input, 0).unwrap();
        assert_eq!(out.item.blocks.len(), 2);
    }

    #[test]
    fn rejects_invalid_utf8_for_text() {
        let input = ContentInput {
            source_type: SourceType::Text,
            source_url: None,
            raw: vec![0xff, 0xfe, 0x00],
        };
        assert!(compile(&input, 0).is_err());
    }
}
