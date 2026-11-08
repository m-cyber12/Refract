use super::*;
use mailparse::MailHeaderMap;
use refract_core::{Item, SourceType};

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct EmailCopyInput { pub raw: String, pub category: String, pub include_subject: bool, pub include_sender: bool, pub include_declared_date: bool, pub review_hash: String }
impl Default for EmailCopyInput { fn default()->Self{Self{raw:String::new(),category:"receipt".into(),include_subject:false,include_sender:false,include_declared_date:false,review_hash:String::new()}} }
#[derive(Debug, Serialize)]
pub struct EmailCopyPreview { pub copy_text: String, pub review_hash: String, pub category: String, pub statement: String }
const STATEMENT: &str = "This is a user-selected plain-text email copy, not the original .eml. Headers and category are unverified/user-selected. No sender identity, DKIM, purchase or obligation is authenticated. Only the reviewed copy is retained; the raw email and excluded headers are not retained. No account is connected.";
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
