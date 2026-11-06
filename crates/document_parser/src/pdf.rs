//! Memory-bounded PDF text extraction (MVP quality, honest confidence).

use super::{paragraphs_from_plain, ParsedDocument};
use refract_core::{RefractError, RefractResult};

pub fn parse(bytes: &[u8]) -> RefractResult<ParsedDocument> {
    let doc = lopdf::Document::load_mem(bytes)
        .map_err(|e| RefractError::parse(format!("cannot open pdf: {e}")))?;
    let mut text = String::new();
    // Cap the number of pages processed to stay memory-bounded on huge files.
    let max_pages = 200usize;
    for (i, page_id) in doc.get_pages().keys().take(max_pages).enumerate() {
        if let Ok(content) = doc.extract_text(&[*page_id]) {
            if i > 0 {
                text.push_str("\n\n");
            }
            text.push_str(&content);
        }
    }
    if text.trim().is_empty() {
        return Err(RefractError::parse("pdf contains no extractable text"));
    }
    let blocks = paragraphs_from_plain(&text);
    Ok(ParsedDocument {
        title: doc
            .get_metadata()
            .ok()
            .and_then(|m| m.get(b"Title").ok().and_then(|v| v.as_str().ok().map(String::from))),
        author: None,
        language: None,
        plain_text: text,
        blocks,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_garbage() {
        assert!(parse(b"not a pdf").is_err());
        assert!(parse(b"").is_err());
    }
}
