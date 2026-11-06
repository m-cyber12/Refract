//! AI runtime (spec §5.2/§5.3/§5.4).
//!
//! The app must work with no model downloaded, so the default engine is
//! **deterministic and extractive**. A local model slot exists behind the
//! `AiEngine` trait; when no model is available the runtime transparently
//! falls back. Every output carries a `kind` label so the UI can always
//! distinguish evidence from interpretation.

use refract_core::{Block, RefractError, RefractResult};

/// What kind of output this is — surfaced to the UI for labeling (spec §3.5).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputKind {
    /// Deterministic extraction from the source (quotes, headings).
    Extractive,
    /// Local model interpretation. Never presented as verified fact.
    Interpretation,
}

/// A generated result with provenance.
#[derive(Debug, Clone)]
pub struct AiOutput {
    pub kind: OutputKind,
    pub text: String,
    /// Source block indices this output is based on.
    pub source_blocks: Vec<u32>,
    /// Whether a real local model produced this (false = fallback).
    pub model_used: bool,
}

/// The runtime abstraction. Implementations: extractive (always available),
/// local model (optional, resource-aware).
pub trait AiEngine {
    fn is_available(&self) -> bool;
    fn summarize(&self, blocks: &[Block], max_sentences: usize) -> RefractResult<AiOutput>;
    fn suggest_tags(&self, blocks: &[Block], max_tags: usize) -> RefractResult<AiOutput>;
}

/// Deterministic engine: always available, never fails, no model needed.
pub struct ExtractiveEngine;

fn sentences(text: &str) -> Vec<&str> {
    text.split_inclusive(['.', '!', '?'])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect()
}

impl AiEngine for ExtractiveEngine {
    fn is_available(&self) -> bool {
        true
    }

    fn summarize(&self, blocks: &[Block], max_sentences: usize) -> RefractResult<AiOutput> {
        let mut out = String::new();
        let mut used: Vec<u32> = Vec::new();
        let mut count = 0;
        for b in blocks {
            if matches!(b.kind, refract_core::BlockKind::Heading1 | refract_core::BlockKind::Heading2) {
                if !out.is_empty() {
                    out.push('\n');
                }
                out.push_str(&b.text);
                out.push('\n');
                used.push(b.idx);
            }
        }
        for b in blocks {
            if count >= max_sentences {
                break;
            }
            if b.kind == refract_core::BlockKind::Paragraph {
                for s in sentences(&b.text) {
                    if count >= max_sentences {
                        break;
                    }
                    if !out.contains(s) {
                        if !out.is_empty() {
                            out.push(' ');
                        }
                        out.push_str(s);
                        used.push(b.idx);
                        count += 1;
                    }
                }
            }
        }
        if out.is_empty() {
            return Err(RefractError::invalid("nothing to summarize"));
        }
        Ok(AiOutput {
            kind: OutputKind::Extractive,
            text: out,
            source_blocks: used,
            model_used: false,
        })
    }

    fn suggest_tags(&self, blocks: &[Block], max_tags: usize) -> RefractResult<AiOutput> {
        // Deterministic: most frequent content words (len >= 5, stoplisted).
        const STOP: &[&str] = &[
            "the", "and", "that", "with", "this", "from", "have", "not", "are", "for",
            "you", "your", "about", "into", "than", "then", "them", "they", "been",
            "were", "will", "would", "could", "should",
        ];
        let mut freq: Vec<(String, usize)> = Vec::new();
        for b in blocks {
            if b.kind != refract_core::BlockKind::Paragraph && b.kind != refract_core::BlockKind::Heading1 {
                continue;
            }
            for w in b.text.split_whitespace() {
                let w = w.trim_matches(|c: char| !c.is_alphanumeric()).to_lowercase();
                if w.len() >= 5 && !STOP.contains(&w.as_str()) {
                    if let Some(e) = freq.iter_mut().find(|(k, _)| *k == w) {
                        e.1 += 1;
                    } else {
                        freq.push((w, 1));
                    }
                }
            }
        }
        freq.sort_by(|a, b| b.1.cmp(&a.1));
        let tags: Vec<String> = freq.into_iter().take(max_tags).map(|(w, _)| w).collect();
        if tags.is_empty() {
            return Err(RefractError::invalid("no tag candidates"));
        }
        Ok(AiOutput {
            kind: OutputKind::Extractive,
            text: tags.join(", "),
            source_blocks: blocks.iter().map(|b| b.idx).collect(),
            model_used: false,
        })
    }
}

/// Runtime: picks a model engine if one is installed, else the extractive one.
pub struct AiRuntime {
    extractive: ExtractiveEngine,
}

impl AiRuntime {
    pub fn new() -> Self {
        AiRuntime { extractive: ExtractiveEngine }
    }

    /// Summarize with graceful degradation (spec §3.6): falls back to
    /// extractive output if no local model is available.
    pub fn summarize(&self, blocks: &[Block], max_sentences: usize) -> RefractResult<AiOutput> {
        // Model slot: when a local model is installed and resources allow,
        // it would run here. Today: extractive fallback, always.
        self.extractive.summarize(blocks, max_sentences)
    }

    pub fn suggest_tags(&self, blocks: &[Block], max_tags: usize) -> RefractResult<AiOutput> {
        self.extractive.suggest_tags(blocks, max_tags)
    }
}

impl Default for AiRuntime {
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
            Block { idx: 0, kind: BlockKind::Heading1, text: "On Prisms".into() },
            Block { idx: 1, kind: BlockKind::Paragraph, text: "Light bends when it enters glass. A prism splits white light into a spectrum. This is refraction.".into() },
        ]
    }

    #[test]
    fn extractive_summary_labels_and_sources() {
        let rt = AiRuntime::new();
        let out = rt.summarize(&blocks(), 2).unwrap();
        assert_eq!(out.kind, OutputKind::Extractive);
        assert!(!out.model_used);
        assert!(out.text.contains("On Prisms"));
        assert!(!out.source_blocks.is_empty());
    }

    #[test]
    fn tags_are_deterministic() {
        let rt = AiRuntime::new();
        let a = rt.suggest_tags(&blocks(), 3).unwrap();
        let b = rt.suggest_tags(&blocks(), 3).unwrap();
        assert_eq!(a.text, b.text);
    }
}
