//! Document parsers.
//!
//! Each parser converts raw input bytes into a [`ParsedDocument`]: metadata
//! plus an ordered stream of raw blocks. Parsers are *sanitizing by
//! construction*: HTML is parsed (never executed) and only allowlisted
//! elements are read out as text, so imported scripts can never run.

pub mod html;
pub mod markdown;
pub mod pdf;
pub mod text;

use refract_core::{Block, BlockKind, RefractError, RefractResult};

/// Output of a parser before compilation/normalization.
#[derive(Debug, Clone, Default)]
pub struct ParsedDocument {
    pub title: Option<String>,
    pub author: Option<String>,
    pub language: Option<String>,
    pub blocks: Vec<Block>,
    /// Plain text of the whole document (used for hashing/search fallback).
    pub plain_text: String,
    /// Non-content diagnostics about known extraction limitations, never proof of completeness.
    pub warnings: Vec<String>,
}

fn push_block(blocks: &mut Vec<Block>, kind: BlockKind, text: &str) {
    let text = normalize_ws(text);
    if text.is_empty() {
        return;
    }
    let idx = blocks.len() as u32;
    blocks.push(Block { idx, kind, text });
}

/// Collapse all whitespace runs to single spaces and trim.
pub fn normalize_ws(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Split plain text into paragraphs on blank or whitespace-only lines.
/// Line endings are normalized only in derived blocks, not in stored originals.
pub fn paragraphs_from_plain(text: &str) -> Vec<Block> {
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let mut blocks = Vec::new();
    let mut paragraph = String::new();
    for line in normalized.split('\n') {
        if line.trim().is_empty() {
            push_block(&mut blocks, BlockKind::Paragraph, &paragraph);
            paragraph.clear();
        } else {
            if !paragraph.is_empty() { paragraph.push(' '); }
            paragraph.push_str(line);
        }
    }
    push_block(&mut blocks, BlockKind::Paragraph, &paragraph);
    blocks
}

#[cfg(test)]
mod paragraph_tests {
    use super::*;

    #[test]
    fn line_endings_and_whitespace_only_lines_split_paragraphs() {
        for input in ["one\n\ntwo", "one\r\n\r\ntwo", "one\r\rtwo", "one\n  \t\ntwo"] {
            let blocks = paragraphs_from_plain(input);
            assert_eq!(blocks.iter().map(|b| b.text.as_str()).collect::<Vec<_>>(), vec!["one", "two"]);
        }
        let blocks = paragraphs_from_plain("one\r\ntwo\r\n\r\nthree");
        assert_eq!(blocks.iter().map(|b| b.text.as_str()).collect::<Vec<_>>(), vec!["one two", "three"]);
    }
}

pub fn parse_text(input: &str) -> RefractResult<ParsedDocument> {
    if input.trim().is_empty() {
        return Err(RefractError::invalid("empty text input"));
    }
    Ok(text::parse(input))
}

pub fn parse_markdown(input: &str) -> RefractResult<ParsedDocument> {
    if input.trim().is_empty() {
        return Err(RefractError::invalid("empty markdown input"));
    }
    Ok(markdown::parse(input))
}

pub fn parse_html(input: &str) -> RefractResult<ParsedDocument> {
    if input.trim().is_empty() {
        return Err(RefractError::invalid("empty html input"));
    }
    html::parse(input)
}

pub fn parse_pdf(bytes: &[u8]) -> RefractResult<ParsedDocument> {
    if bytes.is_empty() {
        return Err(RefractError::invalid("empty pdf input"));
    }
    pdf::parse(bytes)
}
