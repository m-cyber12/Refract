//! Explicit, local-only capture. Preview never persists user content. No fetch,
//! polling or background/restart queue; URL references are not webpage snapshots.
use crate::Store;
use base64::{engine::general_purpose::STANDARD, Engine};
use content_compiler::{compile, sha256_hex, validate_source_url, CompiledDocument, ContentInput};
use refract_core::{Item, RefractError, RefractResult, SourceType};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

fn invalid(s: &str) -> RefractError { RefractError::invalid(s) }
fn storage(e: impl std::fmt::Display) -> RefractError { RefractError::storage(e.to_string()) }
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all="snake_case")]
pub enum CaptureFormat { Text, Markdown, Html, Pdf, UrlReference }
impl CaptureFormat {
 fn source_type(self)->SourceType { match self { Self::Text=>SourceType::Text,Self::Markdown=>SourceType::Markdown,Self::Html=>SourceType::Html,Self::Pdf=>SourceType::Pdf,Self::UrlReference=>SourceType::UrlReference } }
}
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all="snake_case")]
pub enum CaptureChoice { #[default] Save, UseExisting, KeepCopy }
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CaptureDraft {
 pub format: CaptureFormat,
 #[serde(default)] pub text: Option<String>,
 #[serde(default)] pub pdf_base64: Option<String>,
 #[serde(default)] pub source_url: Option<String>,
 #[serde(default)] pub review_hash: Option<String>,
 #[serde(default)] pub choice: CaptureChoice,
 #[serde(default)] pub existing_id: Option<String>,
}
#[derive(Debug, Serialize)]
pub struct CaptureDuplicate { pub id: String, pub title: Option<String>, pub import_ts: i64 }
#[derive(Debug, Serialize)]
pub struct CapturePreview {
 pub format: CaptureFormat, pub review_hash: String, pub sha256: String,
 pub byte_len: usize, pub title: Option<String>, pub block_count: usize,
 pub excerpt: String, pub source_url: Option<String>, pub duplicate: Option<CaptureDuplicate>,
 pub other_saved_inputs_for_url: i64, pub warnings: Vec<String>,
}
#[derive(Debug, Serialize)]
pub struct CaptureResult { pub item: Item, pub reused_existing: bool }
fn prepare(d: &CaptureDraft) -> RefractResult<(CompiledDocument, String)> {
 let raw = match d.format {
  CaptureFormat::Pdf => {
   if d.text.is_some() { return Err(invalid("PDF must contain bytes, not a text field")); }
   let encoded = d.pdf_base64.as_deref().ok_or_else(||invalid("Select a PDF file"))?;
   if encoded.len()>13_981_016 { return Err(invalid("PDF exceeds 10 MiB")); }
   STANDARD.decode(encoded).map_err(|_|invalid("Invalid PDF bytes"))?
  },
  _ => {
   if d.pdf_base64.is_some() { return Err(invalid("Binary PDF bytes cannot be treated as text")); }
   let text = d.text.as_deref().ok_or_else(||invalid("Enter text or select a supported UTF-8 file"))?;
   if text.len()>2*1024*1024 { return Err(invalid("Text exceeds 2 MiB")); }
   text.as_bytes().to_vec()
  }
 };
 let source_url = if d.format == CaptureFormat::UrlReference {
  let address = std::str::from_utf8(&raw).map_err(|_|invalid("Invalid URL encoding"))?.trim();
  validate_source_url(address)?;
  if d.source_url.as_deref().is_some_and(|v| v!=address) { return Err(invalid("Reference and source address differ")); }
  Some(address.to_string())
 } else { d.source_url.clone() };
 let input = ContentInput { source_type:d.format.source_type(),source_url,raw };
 // Bound to exact original bytes, chosen parser and supplied source metadata.
 // A local review binding, not identity, legal authenticity or trusted time.
 let binding = serde_json::to_vec(&(&input.source_type,&input.source_url,sha256_hex(&input.raw))).map_err(storage)?;
 let review_hash = sha256_hex(&binding);
 let ts=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(storage)?.as_secs() as i64;
 Ok((compile(&input,ts)?,review_hash))
}
impl Store {
 fn capture_duplicate(&self, item:&Item)->RefractResult<Option<CaptureDuplicate>> {
  self.conn.query_row("SELECT id,title,import_ts FROM items WHERE content_hash=?1 AND source_type=?2 AND source_url IS ?3 AND status='ready' ORDER BY import_ts DESC,id LIMIT 1",params![item.content_hash,item.source_type.as_str(),item.source_url],|r|Ok(CaptureDuplicate{id:r.get(0)?,title:r.get(1)?,import_ts:r.get(2)?})).optional().map_err(storage)
 }
 pub fn capture_preview(&self,d:&CaptureDraft)->RefractResult<CapturePreview> {
  let (c,review_hash)=prepare(d)?;
  let duplicate=self.capture_duplicate(&c.item)?;
  let other_saved_inputs_for_url=if let Some(url)=&c.item.source_url { self.conn.query_row("SELECT COUNT(*) FROM items WHERE source_url=?1 AND content_hash<>?2",params![url,c.original_hash],|r|r.get(0)).map_err(storage)? } else { 0 };
  let mut warnings=vec!["Local capture only. Originals and extracted text are stored in the app library without app-level encryption. No content is fetched or sent to a provider.".into()];
  if d.format==CaptureFormat::UrlReference { warnings.push("Address only: no webpage, author, publication date or webpage content was fetched or verified. Query parameters are retained as entered.".into()); }
  if d.format==CaptureFormat::Pdf { warnings.push("Text extraction only, no OCR or visual/signature verification. Scanned portions can be absent from the reader. Input/page/output caps are not a hard parser RAM/CPU sandbox.".into()); }
  if d.format==CaptureFormat::Html { warnings.push("Reader text is sanitized; original HTML is kept unchanged and can contain scripts, hidden metadata or sensitive values. Nothing in it is executed or fetched.".into()); }
  if other_saved_inputs_for_url>0 { warnings.push("Other saved input exists for this address. A new capture preserves it; this is not evidence that the remote webpage changed.".into()); }
  Ok(CapturePreview{format:d.format,review_hash,sha256:c.original_hash,byte_len:c.original_bytes.len(),title:c.item.title,block_count:c.item.blocks.len(),excerpt:c.transformed_text.chars().take(1200).collect(),source_url:c.item.source_url,duplicate,other_saved_inputs_for_url,warnings})
 }
 pub fn capture_commit(&mut self,d:&CaptureDraft)->RefractResult<CaptureResult> {
  let (c,hash)=prepare(d)?;
  if d.review_hash.as_deref()!=Some(hash.as_str()) { return Err(invalid("Capture changed or has not been reviewed. Preview it again; nothing was saved.")); }
  if d.choice==CaptureChoice::UseExisting {
   let id=d.existing_id.as_deref().ok_or_else(||invalid("Choose the reviewed existing copy"))?;
   let item=self.get_item(id)?.ok_or_else(||invalid("Existing copy is no longer available; review again"))?;
   if item.content_hash!=c.item.content_hash || item.source_type!=c.item.source_type || item.source_url!=c.item.source_url || item.status!=refract_core::ImportStatus::Ready { return Err(invalid("Existing copy no longer matches the reviewed capture")); }
   let path=self.blob_dir.join(format!("{}.original",item.id));
   let mut file=std::fs::File::open(&path).map_err(|_|invalid("Existing original is missing; explicitly keep a separate copy instead"))?;
   let mut bytes=Vec::new();
   use std::io::Read;
   (&mut file).take(10*1024*1024+1).read_to_end(&mut bytes).map_err(storage)?;
   if bytes!=c.original_bytes { return Err(invalid("Existing original differs from the selected input; explicitly keep a separate copy instead")); }
   return Ok(CaptureResult{item,reused_existing:true});
  }
  if d.existing_id.is_some() { return Err(invalid("Existing-copy ID is only valid with use_existing")); }
  self.insert_item_inner(&c.item,&c.original_bytes,&c.original_hash,d.choice!=CaptureChoice::KeepCopy)?;
  Ok(CaptureResult{item:c.item,reused_existing:false})
 }
}

#[cfg(test)] mod tests;
