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

/// Split plain text into paragraph blocks on blank lines.
pub fn paragraphs_from_plain(text: &str) -> Vec<Block> {
    let mut blocks = Vec::new();
    for para in text.split("\n\n") {
        push_block(&mut blocks, BlockKind::Paragraph, para);
    }
    blocks
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
