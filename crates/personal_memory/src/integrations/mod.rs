//! Optional, consent-gated adapters. No polling, credentials or network clients.
use crate::Store;
use refract_core::{RefractError, RefractResult};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
mod calendar;
mod email;
pub use calendar::*;
pub use email::*;
#[cfg(test)] mod tests;

pub(super) fn invalid(s: impl Into<String>) -> RefractError { RefractError::invalid(s.into()) }
pub(super) fn err(e: impl std::fmt::Display) -> RefractError { RefractError::storage(e.to_string()) }
pub(super) fn json<T: Serialize>(v: &T) -> RefractResult<String> { serde_json::to_string(v).map_err(err) }
pub(super) fn now() -> RefractResult<i64> { Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_secs() as i64) }
const EMAIL_CATEGORIES: &[&str] = &["receipt", "order", "subscription", "travel", "delivery", "appointment", "document", "account"];

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct IntegrationPolicy { pub connector_id: String, pub enabled: bool, pub categories: Vec<String>, #[serde(default)] pub revision: i64 }
#[derive(Debug, Serialize)]
pub struct IntegrationCapability { pub id: String, pub name: String, pub availability: String, pub scope: String, pub limitations: String, pub categories: Vec<String>, pub policy: IntegrationPolicy }
fn categories(id: &str) -> Option<&'static [&'static str]> { match id { "selected_email" => Some(EMAIL_CATEGORIES), "calendar_export" => Some(&["confirmed_dates"]), _ => None } }

impl Store {
 pub fn integration_policy(&self, id: &str) -> RefractResult<IntegrationPolicy> {
  if categories(id).is_none() { return Err(invalid("Adapter is unavailable; no authorization or connection is established")); }
  let row: Option<(bool, String, i64)> = self.conn.query_row("SELECT enabled,categories_json,revision FROM integration_policies WHERE connector_id=?1",params![id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional().map_err(err)?;
  match row { Some((enabled,c,revision))=>Ok(IntegrationPolicy{connector_id:id.into(),enabled,categories:serde_json::from_str(&c).map_err(err)?,revision}), None=>Ok(IntegrationPolicy{connector_id:id.into(),..Default::default()}) }
 }
 pub fn integration_set_policy(&self, p: &IntegrationPolicy) -> RefractResult<IntegrationPolicy> {
  let allowed=categories(&p.connector_id).ok_or_else(||invalid("Adapter unavailable: cannot authorize an unimplemented provider or OS listener"))?;
  if p.categories.iter().any(|c|!allowed.contains(&c.as_str())) || p.categories.iter().collect::<BTreeSet<_>>().len()!=p.categories.len() || p.enabled&&p.categories.is_empty() { return Err(invalid("Select explicit supported categories; broad/all-category grants are not accepted")); }
  let cats=if p.enabled {p.categories.clone()}else{Vec::new()};
  self.conn.execute("INSERT INTO integration_policies(connector_id,enabled,categories_json,revision) VALUES(?1,?2,?3,1) ON CONFLICT(connector_id) DO UPDATE SET enabled=excluded.enabled,categories_json=excluded.categories_json,revision=integration_policies.revision+1",params![p.connector_id,p.enabled,json(&cats)?]).map_err(err)?;
  self.integration_policy(&p.connector_id)
 }
 pub(super) fn integration_require(&self, id: &str, category: &str) -> RefractResult<IntegrationPolicy> {
  let p=self.integration_policy(id)?;if !p.enabled||!p.categories.iter().any(|c|c==category){return Err(invalid("Local adapter/category is disabled. Explicitly allow it before processing"));}Ok(p)
 }
 pub fn integration_catalog(&self) -> RefractResult<Vec<IntegrationCapability>> {
  let specs=[
   ("selected_email","Selected email copy","available_local","One explicitly selected single-part plain-text .eml; chosen categories only. No account access.","Only the reviewed copy enters the library; OS/picker caches are not a secure-erasure boundary. No HTML/multipart/attachments, DKIM or sender verification."),
   ("calendar_export","Reviewed calendar file","available_local","At most 20 explicitly selected, confirmed, still-source-backed date mentions per ICS file.","Date-only export, not a scheduled appointment. No calendar account access, reminders, background writes or import confirmation."),
   ("gmail","Google mailbox adapter","research_only","Future delegated authorization; body-reading scope is broader than a receipt category.","No OAuth flow, tokens, mailbox access or polling is implemented."),
   ("microsoft_mail","Microsoft mailbox adapter","research_only","Future delegated authorization; basic metadata permission does not grant message-body access.","No OAuth flow, tokens, mailbox access or polling is implemented."),
   ("android_notifications","Android notification intelligence","research_only","Future explicit OS access plus package/category allowlists before reading content.","No listener, permission request or collection ships. No equivalent unrestricted iOS monitoring."),
   ("provenance_research","Advanced provenance adapters","research_only","TLSNotary/zkTLS, C2PA, external signatures and signed timestamp trust models.","No external proof technology is implemented or marked verified. Existing local Merkle proofs do not establish identity, truth or legal authenticity."),
  ];
  specs.into_iter().map(|(id,name,status,scope,limits)|Ok(IntegrationCapability{id:id.into(),name:name.into(),availability:status.into(),scope:scope.into(),limitations:limits.into(),categories:categories(id).unwrap_or(&[]).iter().map(|s|(*s).into()).collect(),policy:if categories(id).is_some(){self.integration_policy(id)?}else{IntegrationPolicy{connector_id:id.into(),..Default::default()}}})).collect()
 }
}
