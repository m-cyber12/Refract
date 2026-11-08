//! Capped PDF extraction. Input/page/output bounds are not a hard parser RAM/CPU sandbox.

use super::{paragraphs_from_plain, ParsedDocument};
use refract_core::{RefractError, RefractResult};

pub fn parse(bytes: &[u8]) -> RefractResult<ParsedDocument> {
    // Ordinary parser panics become an error. This cannot catch allocation
    // failure, stack overflow or OS termination; it is not process isolation.
    std::panic::catch_unwind(|| parse_inner(bytes)).unwrap_or_else(|_|Err(RefractError::parse("PDF parser failed; no text was extracted")))
}
fn parse_inner(bytes: &[u8]) -> RefractResult<ParsedDocument> {
    if bytes.len() > 10 * 1024 * 1024 { return Err(RefractError::invalid("PDF exceeds 10 MiB")); }
    let doc = lopdf::Document::load_mem(bytes)
        .map_err(|e| RefractError::parse(format!("cannot open pdf: {e}")))?;
    if doc.is_encrypted() { return Err(RefractError::parse("Encrypted PDFs are not supported; provide an authorized unlocked copy")); }
    if doc.get_pages().len() > 200 { return Err(RefractError::parse("PDF exceeds 200 pages; no partial document was saved")); }
    let mut text = String::new();
    // Reject, never silently truncate, oversized page counts.
    let max_pages = 200usize;
    for (i, page_id) in doc.get_pages().keys().take(max_pages).enumerate() {
        let content = doc.extract_text(&[*page_id]).map_err(|_| RefractError::parse("A PDF page could not be extracted; no partial document was saved"))?;
        if text.len() + content.len() + 2 > 2 * 1024 * 1024 { return Err(RefractError::parse("PDF extracted text exceeds 2 MiB; nothing was saved")); }
        if i > 0 { text.push_str("\n\n"); }
        text.push_str(&content);
    }
    if text.trim().is_empty() {
        return Err(RefractError::parse("pdf contains no extractable text"));
    }
    let blocks = paragraphs_from_plain(&text);
    Ok(ParsedDocument {
        title: None,
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

#[cfg(test)] mod capture_tests {
 use super::*;
 #[test] fn no_silent_truncation_or_skipped_bad_page() {
  let bad=include_bytes!("../../../shared/fixtures/capture/corrupt-second-page.pdf");
  assert!(parse(bad).unwrap_err().to_string().contains("page could not be extracted"));
  let too_many=include_bytes!("../../../shared/fixtures/capture/too-many-pages.pdf");
  assert!(parse(too_many).unwrap_err().to_string().contains("200 pages"));
 }
}
