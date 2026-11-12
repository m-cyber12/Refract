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
    let mut doc = lopdf::Document::load_mem(bytes)
        .map_err(|e| RefractError::parse(format!("cannot open pdf: {e}")))?;
    if doc.is_encrypted() { return Err(RefractError::parse("Encrypted PDFs are not supported; provide an authorized unlocked copy")); }
    let pages = doc.get_pages();
    if pages.is_empty() { return Err(RefractError::parse("PDF has no pages; nothing was saved")); }
    if pages.len() > 200 { return Err(RefractError::parse("PDF exceeds 200 pages; no partial document was saved")); }
    let mut text = String::new();
    let mut pages_without_text = 0usize;
    let mut decoded_total = 0usize;
    // Reject, never silently truncate, oversized page counts.
    let max_pages = 200usize;
    let mut resources = std::collections::BTreeMap::new();
    for (i, (page_number, page_id)) in pages.iter().take(max_pages).enumerate() {
        inherit_resources(&mut doc, *page_id, &mut resources)?;
        let decoded_len = validate_text_objects(&doc, *page_id)?;
        decoded_total = decoded_total.checked_add(decoded_len).ok_or_else(|| RefractError::parse("PDF decoded content size overflow; nothing was saved"))?;
        if decoded_total > 32 * 1024 * 1024 { return Err(RefractError::parse("PDF decoded page content exceeds 32 MiB total; nothing was saved")); }
        let content = doc.extract_text(&[*page_number]).map_err(|_| RefractError::parse("A PDF page could not be extracted; no partial document was saved"))?;
        if content.trim().is_empty() { pages_without_text += 1; }
        if text.len() + content.len() + 2 > 2 * 1024 * 1024 { return Err(RefractError::parse("PDF extracted text exceeds 2 MiB; nothing was saved")); }
        if i > 0 { text.push_str("\n\n"); }
        text.push_str(&content);
    }
    if text.trim().is_empty() {
        return Err(RefractError::parse("No text could be extracted from this PDF. It may contain scanned images or unsupported text encoding. OCR is not available in REFRACT yet; no original was saved."));
    }
    let blocks = paragraphs_from_plain(&text);
    Ok(ParsedDocument {
        title: None,
        author: None,
        language: None,
        plain_text: text,
        blocks,
        warnings: if pages_without_text == 0 { Vec::new() } else { vec![format!("{pages_without_text} of {} PDF pages produced no extractable text. They may be blank, scanned, or use unsupported text encoding. Other pages may also be incomplete. OCR is not available.", pages.len())] },
    })
}

// The upstream content decoder can accept a valid prefix and ignore a broken
// trailing operation. Reject unfinished/nested text objects rather than saving
// an earlier readable page as if that known failure were a successful capture.
// This is a conservative check, NOT complete PDF syntax/semantic validation.
fn validate_text_objects(doc: &lopdf::Document, page: lopdf::ObjectId) -> RefractResult<usize> {
    let failure = || RefractError::parse("A PDF page could not be extracted; no partial document was saved");
    let data = doc.get_page_content(page).map_err(|_|failure())?;
    if data.len() > 16 * 1024 * 1024 { return Err(RefractError::parse("Decoded PDF page content exceeds 16 MiB; nothing was saved")); }
    let content = lopdf::content::Content::decode(&data).map_err(|_|failure())?;
    let mut inside = false;
    for op in content.operations {
        match op.operator.as_str() {
            "BT" => { if inside { return Err(failure()); } inside = true; },
            "ET" => { if !inside { return Err(failure()); } inside = false; },
            _ => {},
        }
    }
    if inside { return Err(failure()); }
    Ok(data.len())
}

// lopdf 0.34 collects inherited Resources only when they are references, not
// inline parent dictionaries (valid PDF). Resolve the nearest inherited value
// explicitly in the in-memory extraction document, never changing source bytes.
// Cache by owning node so large inline dictionaries aren't cloned per page.
fn inherit_resources(doc: &mut lopdf::Document, page: lopdf::ObjectId, cache: &mut std::collections::BTreeMap<lopdf::ObjectId, lopdf::Object>) -> RefractResult<()> {
    let mut current = page;
    let mut seen = std::collections::BTreeSet::new();
    let resource = loop {
        if !seen.insert(current) || seen.len() > 128 { return Err(RefractError::parse("PDF resource inheritance is cyclic or exceeds 128 levels")); }
        if let Some(r) = cache.get(&current) { break Some(r.clone()); }
        let dict = doc.get_dictionary(current).map_err(|_|RefractError::parse("Cannot read PDF page resource hierarchy"))?;
        if let Ok(r) = dict.get(b"Resources") {
            let r = r.clone();
            let r = match r { lopdf::Object::Reference(_)=>r, lopdf::Object::Dictionary(_)=>lopdf::Object::Reference(doc.add_object(r)), _=>return Err(RefractError::parse("Invalid PDF page resources")) };
            cache.insert(current,r.clone()); break Some(r);
        }
        match dict.get(b"Parent") {
            Ok(lopdf::Object::Reference(parent))=>current=*parent,
            Ok(_)=>return Err(RefractError::parse("Invalid PDF page parent")),
            Err(_)=>break None,
        }
    };
    if let Some(r) = resource { doc.get_object_mut(page).and_then(lopdf::Object::as_dict_mut).map_err(|_|RefractError::parse("Cannot normalize PDF page resources"))?.set("Resources",r); }
    Ok(())
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
  let empty=include_bytes!("../../../shared/fixtures/capture/no-extractable-text.pdf");
  let message=parse(empty).unwrap_err().to_string();
  assert!(message.contains("OCR is not available"));
  assert!(message.contains("no original was saved"));
  let total=include_bytes!("../../../shared/fixtures/capture/excess-decoded-pages.pdf");
  assert!(parse(total).unwrap_err().to_string().contains("32 MiB total"));
  let zero=include_bytes!("../../../shared/fixtures/capture/no-pages.pdf");
  assert!(parse(zero).unwrap_err().to_string().contains("no pages"));
  let bad=include_bytes!("../../../shared/fixtures/capture/corrupt-second-page.pdf");
  assert!(parse(bad).unwrap_err().to_string().contains("page could not be extracted"));
  let too_many=include_bytes!("../../../shared/fixtures/capture/too-many-pages.pdf");
  assert!(parse(too_many).unwrap_err().to_string().contains("200 pages"));
 }
}
