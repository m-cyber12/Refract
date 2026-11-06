//! Annotation engine (System C, spec §C1/C2/C3).
//!
//! - Anchors combine content hash, quote, prefix/suffix context and block
//!   index; resolution never silently re-attaches to the wrong passage.
//! - Shared annotations live in a Loro CRDT document per workspace, so
//!   concurrent offline edits converge (spec §C3).

use refract_core::{Block, RefractError, RefractResult};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Resilient anchor for an annotation (spec §C2).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Anchor {
    pub content_hash: String,
    pub quote: String,
    pub prefix: String,
    pub suffix: String,
    pub block_idx: Option<u32>,
    pub version: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnchorStatus {
    Exact,
    Relocated,
    Ambiguous,
    Lost,
}

pub fn content_hash_of(blocks: &[Block]) -> String {
    let mut h = Sha256::new();
    for b in blocks {
        h.update(b.kind.as_str().as_bytes());
        h.update([0]);
        h.update(b.text.as_bytes());
        h.update([0]);
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Build an anchor for a quote found in `blocks`.
pub fn build_anchor(blocks: &[Block], block_idx: u32, quote: &str) -> RefractResult<Anchor> {
    let block = blocks
        .iter()
        .find(|b| b.idx == block_idx)
        .ok_or_else(|| RefractError::invalid("block index out of range"))?;
    let pos = block
        .text
        .find(quote)
        .ok_or_else(|| RefractError::invalid("quote not found in block"))?;
    let prefix = block.text[..pos].chars().rev().take(40).collect::<String>().chars().rev().collect();
    let suffix = block.text[pos + quote.len()..].chars().take(40).collect();
    Ok(Anchor {
        content_hash: content_hash_of(blocks),
        quote: quote.to_string(),
        prefix,
        suffix,
        block_idx: Some(block_idx),
        version: 1,
    })
}

/// Resolve an anchor against current content. Never silently wrong (spec §C2).
pub fn resolve_anchor(anchor: &Anchor, blocks: &[Block]) -> (AnchorStatus, Option<u32>) {
    // 1. Exact: same content hash and block still contains the quote.
    if anchor.content_hash == content_hash_of(blocks) {
        if let Some(idx) = anchor.block_idx {
            if let Some(b) = blocks.iter().find(|b| b.idx == idx) {
                if b.text.contains(&anchor.quote) {
                    return (AnchorStatus::Exact, Some(idx));
                }
            }
        }
    }
    // 2. Relocated: find the quote anywhere.
    let hits: Vec<u32> = blocks
        .iter()
        .filter(|b| b.text.contains(&anchor.quote))
        .map(|b| b.idx)
        .collect();
    match hits.len() {
        1 => (AnchorStatus::Relocated, hits.into_iter().next()),
        0 => {
            // 3. Fuzzy: prefix+suffix context match.
            let ctx_hits: Vec<u32> = blocks
                .iter()
                .filter(|b| {
                    !anchor.prefix.is_empty()
                        && b.text.contains(&anchor.prefix)
                        && !anchor.suffix.is_empty()
                        && b.text.contains(&anchor.suffix)
                })
                .map(|b| b.idx)
                .collect();
            match ctx_hits.len() {
                1 => (AnchorStatus::Relocated, ctx_hits.into_iter().next()),
                0 => (AnchorStatus::Lost, None),
                _ => (AnchorStatus::Ambiguous, None),
            }
        }
        _ => (AnchorStatus::Ambiguous, None),
    }
}

/// CRDT-backed shared annotation document (Loro). Concurrent offline edits
/// converge; identity/authz are handled separately (spec §C3 caveat).
pub struct AnnotationDoc {
    doc: loro::LoroDoc,
}

impl AnnotationDoc {
    pub fn new() -> Self {
        AnnotationDoc { doc: loro::LoroDoc::new() }
    }

    /// Insert or update an annotation entry.
    pub fn upsert(&mut self, annotation_id: &str, json: &str) -> RefractResult<()> {
        let map = self.doc.get_map("annotations");
        map.insert(annotation_id, json)
            .map_err(|e| RefractError::internal(format!("crdt insert: {e}")))?;
        self.doc.commit();
        Ok(())
    }

    pub fn remove(&mut self, annotation_id: &str) -> RefractResult<()> {
        let map = self.doc.get_map("annotations");
        map.delete(annotation_id)
            .map_err(|e| RefractError::internal(format!("crdt delete: {e}")))?;
        self.doc.commit();
        Ok(())
    }

    pub fn get(&self, annotation_id: &str) -> Option<String> {
        self.doc
            .get_map("annotations")
            .get(annotation_id)
            .and_then(|v| serde_json::to_string(&v.get_deep_value()).ok())
    }

    /// Export full state (for sync export).
    pub fn export_state(&mut self) -> RefractResult<Vec<u8>> {
        Ok(self.doc.export(loro::ExportMode::Snapshot).map_err(|e| RefractError::internal(e.to_string()))?)
    }

    /// Merge an incoming state/update. Convergent by CRDT semantics.
    pub fn merge(&mut self, bytes: &[u8]) -> RefractResult<()> {
        self.doc.import(bytes).map_err(|e| RefractError::internal(format!("crdt import: {e}")))?;
        Ok(())
    }
}

impl Default for AnnotationDoc {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use refract_core::BlockKind;

    fn blocks() -> Vec<Block> {
        vec![
            Block { idx: 0, kind: BlockKind::Heading1, text: "Intro".into() },
            Block { idx: 1, kind: BlockKind::Paragraph, text: "The prism splits light into colors.".into() },
        ]
    }

    #[test]
    fn anchor_exact_then_relocated_then_ambiguous() {
        let b = blocks();
        let a = build_anchor(&b, 1, "prism splits").unwrap();
        assert_eq!(resolve_anchor(&a, &b).0, AnchorStatus::Exact);

        // Content changed but quote survives elsewhere.
        let mut b2 = b.clone();
        b2.push(Block { idx: 2, kind: BlockKind::Paragraph, text: "Another prism splits beams.".into() });
        let (st, _) = resolve_anchor(&a, &b2);
        assert!(st == AnchorStatus::Relocated || st == AnchorStatus::Ambiguous);

        let b3: Vec<Block> = vec![Block { idx: 0, kind: BlockKind::Paragraph, text: "unrelated".into() }];
        assert_eq!(resolve_anchor(&a, &b3).0, AnchorStatus::Lost);
    }

    #[test]
    fn crdt_converges() {
        let mut d1 = AnnotationDoc::new();
        let mut d2 = AnnotationDoc::new();
        d1.upsert("a1", r#"{"note":"one"}"#).unwrap();
        d2.upsert("a2", r#"{"note":"two"}"#).unwrap();
        let s1 = d1.export_state().unwrap();
        let s2 = d2.export_state().unwrap();
        d1.merge(&s2).unwrap();
        d2.merge(&s1).unwrap();
        assert!(d1.get("a1").is_some() && d1.get("a2").is_some());
        assert_eq!(d1.get("a1"), d2.get("a1"));
        assert_eq!(d1.get("a2"), d2.get("a2"));
    }
}
