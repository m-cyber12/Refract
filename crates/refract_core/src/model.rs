use serde::{Deserialize, Serialize};

use crate::error::RefractError;

/// How the content originally entered REFRACT.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceType {
    Url,
    SharedText,
    Html,
    Pdf,
    Markdown,
    Text,
    File,
}

impl SourceType {
    pub fn as_str(self) -> &'static str {
        match self {
            SourceType::Url => "url",
            SourceType::SharedText => "shared_text",
            SourceType::Html => "html",
            SourceType::Pdf => "pdf",
            SourceType::Markdown => "markdown",
            SourceType::Text => "text",
            SourceType::File => "file",
        }
    }
}

/// Lifecycle status of an imported item.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportStatus {
    Processing,
    Ready,
    Failed,
}

/// Semantic kind of a content block produced by the Reality Compiler.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockKind {
    Heading1,
    Heading2,
    Heading3,
    Paragraph,
    ListItem,
    Quote,
    Code,
    Image,
    Divider,
}

impl BlockKind {
    pub fn as_str(self) -> &'static str {
        match self {
            BlockKind::Heading1 => "heading1",
            BlockKind::Heading2 => "heading2",
            BlockKind::Heading3 => "heading3",
            BlockKind::Paragraph => "paragraph",
            BlockKind::ListItem => "list_item",
            BlockKind::Quote => "quote",
            BlockKind::Code => "code",
            BlockKind::Image => "image",
            BlockKind::Divider => "divider",
        }
    }
}

/// One structured block of a transformed document.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Block {
    pub idx: u32,
    pub kind: BlockKind,
    /// Normalized text content (for images: the alt text / caption).
    pub text: String,
}

/// A library item: one imported piece of content plus its provenance metadata.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Item {
    pub id: String,
    pub source_url: Option<String>,
    pub source_type: SourceType,
    pub import_ts: i64,
    /// SHA-256 of the original, unmodified input bytes.
    pub content_hash: String,
    pub title: Option<String>,
    pub author: Option<String>,
    pub language: Option<String>,
    /// 0.0 - 1.0 heuristic confidence in the extraction quality.
    pub extraction_confidence: f32,
    pub status: ImportStatus,
    pub blocks: Vec<Block>,
}

/// A user-defined tag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tag {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
}

/// A user-defined collection of items.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Collection {
    pub id: String,
    pub name: String,
    pub created_ts: i64,
}

/// An annotation (highlight/note) anchored to content, not screen coordinates.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Annotation {
    pub id: String,
    pub item_id: String,
    pub quote: String,
    pub note: Option<String>,
    pub block_idx: Option<u32>,
    /// private | shared | workspace | public
    pub visibility: String,
    pub created_ts: i64,
}

/// Subscription lifecycle state (spec §B1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubscriptionStatus {
    Confirmed,
    Imported,
    Suspected,
    Unverified,
}

impl SubscriptionStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            SubscriptionStatus::Confirmed => "confirmed",
            SubscriptionStatus::Imported => "imported",
            SubscriptionStatus::Suspected => "suspected",
            SubscriptionStatus::Unverified => "unverified",
        }
    }
}

/// A subscription record (spec §B1). Never auto-marked active from an old receipt.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Subscription {
    pub id: String,
    pub service: String,
    pub plan: Option<String>,
    pub price: Option<f64>,
    pub currency: Option<String>,
    pub frequency: Option<String>,
    pub renewal_date: Option<i64>,
    pub trial_end: Option<i64>,
    pub status: SubscriptionStatus,
    pub confidence: f32,
    pub source_doc_id: Option<String>,
    pub created_ts: i64,
}

/// An append-only evidence record (spec §B4).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvidenceRecord {
    pub id: String,
    pub kind: String,
    pub note: Option<String>,
    pub blob_path: String,
    pub sha256: String,
    pub imported_ts: i64,
}

/// A claim extracted from evidence, linked to its record (spec §B2/B3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EvidenceClaim {
    pub id: String,
    pub record_id: String,
    /// quote | extracted | interpretation
    pub claim_type: String,
    pub text: String,
    pub offset: Option<i64>,
    pub confidence: f32,
}

/// A stored blob (original or transformed representation of an item).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Blob {
    pub item_id: String,
    /// "original" | "transformed"
    pub kind: String,
    pub path: String,
    pub sha256: String,
}

/// Envelope returned across the FFI boundary for every call:
/// `{"ok": true, "payload": ...}` or `{"ok": false, "error": {...}}`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FfiResponse<T: Serialize> {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payload: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RefractError>,
}
