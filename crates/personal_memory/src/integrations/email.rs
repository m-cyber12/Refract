use super::*;
use mailparse::MailHeaderMap;
use refract_core::{Item, SourceType};

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EmailCopyInput { pub raw: String, pub category: String, #[serde(default)] pub include_subject: bool, #[serde(default)] pub include_sender: bool, #[serde(default)] pub include_declared_date: bool, #[serde(default)] pub review_hash: String }
impl Default for EmailCopyInput { fn default()->Self{Self{raw:String::new(),category:"receipt".into(),include_subject:false,include_sender:false,include_declared_date:false,review_hash:String::new()}} }
#[derive(Debug, Serialize)]
pub struct EmailCopyPreview { pub copy_text: String, pub review_hash: String, pub category: String, pub statement: String }
const STATEMENT: &str = "This is a user-selected plain-text email copy, not the original .eml. Headers and category are unverified/user-selected. No sender identity, DKIM, purchase or obligation is authenticated. Only the reviewed copy enters the library; raw email and excluded headers are not written to library storage. OS/picker caches may retain the selected original; this is not secure erasure. No account is connected.";
fn header(headers:&[mailparse::MailHeader<'_>],name:&str)->RefractResult<String>{let value=headers.get_first_value(name).unwrap_or_default();if value.len()>2000||value.chars().any(|c|c.is_control()){return Err(invalid("Selected header is too long or contains control characters"));}Ok(value)}
impl Store {
 pub fn integration_email_preview(&self,input:&EmailCopyInput)->RefractResult<EmailCopyPreview>{
  let p=self.integration_require("selected_email",&input.category)?;
  if input.raw.is_empty()||input.raw.len()>262144||input.raw.contains('\0'){return Err(invalid("Select a nonempty UTF-8 email of at most 256 KiB, without NUL characters"));}
  // Parse only headers first; never recurse into an attacker-controlled MIME tree.
  let(headers,_)=mailparse::parse_headers(input.raw.as_bytes()).map_err(|_|invalid("Invalid email headers"))?;
  if headers.len()>100||headers.iter().any(|h|h.get_key_ref().len()>200){return Err(invalid("Too many/oversized email headers"));}
  let mime=mailparse::parse_content_type(&headers.get_first_value("Content-Type").unwrap_or_else(||"text/plain; charset=utf-8".into()));
  if mime.mimetype!="text/plain"||headers.get_first_value("Content-Disposition").is_some_and(|v|!v.trim().eq_ignore_ascii_case("inline")){return Err(invalid("Only a single-part inline text/plain email is supported. Select/copy the wanted text manually for HTML, multipart or attachments"));}
  let parsed=mailparse::parse_mail(input.raw.as_bytes()).map_err(|_|invalid("Cannot decode selected plain-text email"))?;
  if !parsed.subparts.is_empty(){return Err(invalid("Multipart email is not supported"));}
  let body=parsed.get_body().map_err(|_|invalid("Unsupported body encoding"))?;
  if body.trim().is_empty()||body.len()>48000||body.chars().any(|c|c.is_control()&&!['\n','\r','\t'].contains(&c)){return Err(invalid("Decoded plain-text body must be nonempty, at most 48 KB, and contain no hidden control characters"));}
  let mut text=format!("Selected email copy\n\n{STATEMENT}\n\nUser-selected category: {}\n",input.category);
  for(include,name,label)in[(input.include_subject,"Subject","Email-declared Subject (unverified)"),(input.include_sender,"From","Email-declared From (unverified)"),(input.include_declared_date,"Date","Email-declared Date (not capture time; unverified)")]{if include{text.push_str(&format!("{label}: {}\n",header(&headers,name)?));}}
  text.push_str("\nSelected plain-text body:\n");text.push_str(&body);
  let hash=evidence_engine::sha256_hex(json(&("selected-email-copy-v1",p.revision,&input.category,&text))?.as_bytes());
  Ok(EmailCopyPreview{copy_text:text,review_hash:hash,category:input.category.clone(),statement:STATEMENT.into()})
 }
 pub fn integration_email_import(&mut self,input:&EmailCopyInput)->RefractResult<Item>{
  let preview=self.integration_email_preview(input)?;
  if input.review_hash!=preview.review_hash{return Err(invalid("Review the exact email copy again: content, selection or local consent changed"));}
  let compiled=content_compiler::compile(&content_compiler::ContentInput{source_type:SourceType::EmailCopy,source_url:None,raw:preview.copy_text.into_bytes()},now()?)?;
  self.insert_item(&compiled.item,&compiled.original_bytes,&compiled.original_hash)?;
  Ok(compiled.item)
 }
}

#[derive(Debug,Serialize)]
pub struct SavedEmailCopy { pub id:String, pub title:String, pub captured_ts:i64 }
#[derive(Debug,Serialize)]
pub struct EmailCopyDeletion { pub library_removed:bool, pub input_blob_removed:bool, pub warning:String }
impl Store {
 /// Metadata only; deletion remains available even after local consent is disabled.
 pub fn integration_email_copies(&self)->RefractResult<Vec<SavedEmailCopy>>{
  let mut stmt=self.conn.prepare("SELECT id,COALESCE(title,'Selected email copy'),import_ts FROM items WHERE source_type='email_copy' ORDER BY import_ts DESC,id LIMIT 100").map_err(err)?;
  let rows=stmt.query_map([],|r|Ok(SavedEmailCopy{id:r.get(0)?,title:r.get(1)?,captured_ts:r.get(2)?})).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;Ok(rows)
 }
 pub fn integration_email_delete(&self,id:&str)->RefractResult<EmailCopyDeletion>{
  let uuid=uuid::Uuid::parse_str(id).map_err(|_|invalid("Invalid selected-copy ID"))?;
  if uuid.to_string()!=id{return Err(invalid("Noncanonical selected-copy ID"));}
  let kind:Option<String>=self.conn.query_row("SELECT source_type FROM items WHERE id=?1",params![id],|r|r.get(0)).optional().map_err(err)?;
  if kind.as_deref()!=Some("email_copy"){return Err(invalid("Only an existing selected email copy can be removed here; other originals are untouched"));}
  // Commit database removal first: never risk losing a referenced original if a
  // database commit fails. Report filesystem cleanup honestly; no secure erase claim.
  let tx=self.conn.unchecked_transaction().map_err(err)?;
  tx.execute("DELETE FROM consumer_subscription_claims WHERE claim_id IN (SELECT id FROM consumer_claims WHERE item_id=?1)",params![id]).map_err(err)?;
  tx.execute("DELETE FROM consumer_reviews WHERE claim_id IN (SELECT id FROM consumer_claims WHERE item_id=?1)",params![id]).map_err(err)?;
  for table in ["consumer_subscription_links","decision_sources","source_history"] { tx.execute(&format!("DELETE FROM {table} WHERE item_id=?1"),params![id]).map_err(err)?; }
  tx.execute("DELETE FROM items WHERE id=?1 AND source_type='email_copy'",params![id]).map_err(err)?;
  tx.execute("DELETE FROM signal_editions",[]).map_err(err)?;
  tx.commit().map_err(err)?;
  let path=self.blob_dir.join(format!("{id}.original"));
  let removed=match std::fs::remove_file(path){Ok(())=>true,Err(e)if e.kind()==std::io::ErrorKind::NotFound=>true,Err(_)=>false};
  Ok(EmailCopyDeletion{library_removed:true,input_blob_removed:removed,warning:if removed{"Removed from the active local library and its selected-copy input file. Source links/attached annotations/claim reviews are removed. Decisions, subscriptions and retained summary contents are not deleted or canceled. This is not secure erasure of SQLite free pages, OS caches, backups or previously shared/external copies."}else{"Removed from the active library, but the selected-copy input file could not be removed. Residual app storage requires cleanup. Related decisions/subscriptions/summaries remain. This is not secure erasure or removal of backups/external copies."}.into()})
 }
}
