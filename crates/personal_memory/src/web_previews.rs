//! Explicitly approved, bounded fetched-page copies. Logical deletion is not
//! secure erasure of SQLite/WAL, filesystem snapshots, backups or memory.
use crate::Store;
use content_compiler::{sha256_hex, validate_source_url};
use refract_core::{RefractError, RefractResult};
use rusqlite::{params, OptionalExtension, TransactionBehavior};
use serde::Serialize;

const MAX_BYTES: usize = 2 * 1024 * 1024;
const MAX_TOTAL: i64 = 24 * 1024 * 1024;
const MAX_COUNT: i64 = 16;

#[derive(Serialize)]
pub struct WebPreview {
    pub id: String,
    pub requested_url: String,
    pub final_url: String,
    pub html: String,
    pub sha256: String,
    pub consent_ts: i64,
}
#[derive(Serialize)]
pub struct WebPreviewSummary {
    pub id: String,
    pub requested_url: String,
    pub final_url: String,
    pub byte_len: i64,
    pub consent_ts: i64,
}
fn err(e: impl std::fmt::Display) -> RefractError { RefractError::storage(e.to_string()) }
fn check_id(id: &str) -> RefractResult<()> {
    let parsed = uuid::Uuid::parse_str(id).map_err(|_| RefractError::invalid("Invalid preview ID"))?;
    if parsed.to_string() != id { return Err(RefractError::invalid("Invalid preview ID")); }
    Ok(())
}
impl Store {
    pub fn stage_web_preview(&mut self, id: &str, requested: &str, final_url: &str, html: &[u8], consent_ts: i64, approved: bool) -> RefractResult<()> {
        if !approved { return Err(RefractError::invalid("Explicit handoff-copy approval is required")); }
        check_id(id)?;
        validate_source_url(requested)?; validate_source_url(final_url)?;
        if html.is_empty() || html.len() > MAX_BYTES || consent_ts < 0 || consent_ts > 253402300799 {
            return Err(RefractError::invalid("Invalid preview size or approval time"));
        }
        let text = std::str::from_utf8(html).map_err(|_| RefractError::invalid("Preview is not UTF-8"))?;
        if text.contains('\0') { return Err(RefractError::invalid("Preview is not supported HTML text")); }
        let hash = sha256_hex(html);
        let tx = self.conn.transaction_with_behavior(TransactionBehavior::Immediate).map_err(err)?;
        // A repeated completed stage request with identical content is idempotent.
        let existing: Option<(String, String, Vec<u8>, i64)> = tx.query_row("SELECT requested_url, final_url, html, consent_ts FROM web_previews WHERE id=?1", [id], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).optional().map_err(err)?;
        if let Some((old_requested, old_final, old_html, old_ts)) = existing {
            if old_requested == requested && old_final == final_url && old_html == html && old_ts == consent_ts { return Ok(()); }
            return Err(RefractError::invalid("Preview ID is already used by another copy"));
        }
        let (count, total): (i64, i64) = tx.query_row("SELECT COUNT(*), COALESCE(SUM(length(html)),0) FROM web_previews", [], |r| Ok((r.get(0)?,r.get(1)?))).map_err(err)?;
        if count >= MAX_COUNT || total + html.len() as i64 > MAX_TOTAL { return Err(RefractError::invalid("Web preview storage is full; review or discard copies first")); }
        tx.execute("INSERT INTO web_previews(id,requested_url,final_url,html,sha256,consent_ts) VALUES(?1,?2,?3,?4,?5,?6)", params![id, requested, final_url, html, hash, consent_ts]).map_err(err)?;
        tx.commit().map_err(err)
    }
    pub fn list_web_previews(&self) -> RefractResult<Vec<WebPreviewSummary>> {
        let mut statement = self.conn.prepare("SELECT id,requested_url,final_url,length(html),consent_ts FROM web_previews ORDER BY consent_ts,id LIMIT 16").map_err(err)?;
        let rows = statement.query_map([], |r| Ok(WebPreviewSummary { id:r.get(0)?, requested_url:r.get(1)?, final_url:r.get(2)?, byte_len:r.get(3)?, consent_ts:r.get(4)? })).map_err(err)?;
        rows.collect::<Result<Vec<_>,_>>().map_err(err)
    }
    pub fn get_web_preview(&self, id: &str) -> RefractResult<WebPreview> {
        check_id(id)?;
        let row: Option<(String,String,Vec<u8>,String,i64)> = self.conn.query_row("SELECT requested_url,final_url,html,sha256,consent_ts FROM web_previews WHERE id=?1", [id], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?))).optional().map_err(err)?;
        let (requested_url,final_url,bytes,sha256,consent_ts) = row.ok_or_else(||RefractError::invalid("Preview not found"))?;
        if bytes.is_empty() || bytes.len() > MAX_BYTES || sha256_hex(&bytes) != sha256 || consent_ts < 0 || consent_ts > 253402300799 || validate_source_url(&requested_url).is_err() || validate_source_url(&final_url).is_err() { return Err(RefractError::invalid("Preview is damaged; discard it explicitly or try again")); }
        let html = String::from_utf8(bytes).map_err(|_|RefractError::invalid("Preview is damaged"))?;
        if html.contains('\0') { return Err(RefractError::invalid("Preview is damaged")); }
        Ok(WebPreview { id:id.to_string(), requested_url, final_url, html, sha256, consent_ts })
    }
    /// Idempotent explicit delete; never touches library originals or capture jobs.
    pub fn delete_web_preview(&mut self, id: &str) -> RefractResult<()> {
        check_id(id)?; self.conn.execute("DELETE FROM web_previews WHERE id=?1", [id]).map_err(err)?; Ok(())
    }
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn consent_durability_idempotence_and_explicit_deletion() {
        let dir = std::env::temp_dir().join(format!("web-preview-{}",uuid::Uuid::new_v4())); std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("db"); let id = uuid::Uuid::new_v4().to_string();
        let bytes = "\u{feff}<p>東京</p>".as_bytes();
        { let mut store=Store::open(&db).unwrap();
          assert!(store.stage_web_preview(&id,"https://public.com/a","https://public.com/b",bytes,123,false).is_err());
          assert!(store.list_web_previews().unwrap().is_empty());
          store.stage_web_preview(&id,"https://public.com/a","https://public.com/b",bytes,123,true).unwrap();
          store.stage_web_preview(&id,"https://public.com/a","https://public.com/b",bytes,123,true).unwrap();
          assert!(store.stage_web_preview(&id,"https://public.com/a","https://public.com/b",b"different",123,true).is_err()); }
        { let mut store=Store::open(&db).unwrap(); let item=store.get_web_preview(&id).unwrap();
          assert_eq!(item.html.as_bytes(),bytes); assert_eq!(item.consent_ts,123); assert_eq!(store.list_web_previews().unwrap().len(),1);
          store.delete_web_preview(&id).unwrap(); store.delete_web_preview(&id).unwrap(); assert!(store.list_web_previews().unwrap().is_empty()); }
        std::fs::remove_dir_all(dir).unwrap();
    }
    #[test] fn limits_and_corruption_are_reported_not_silently_removed() {
        let mut store=Store::open_in_memory().unwrap();
        for _ in 0..16 { let id=uuid::Uuid::new_v4().to_string(); store.stage_web_preview(&id,"https://public.com/","https://public.com/",b"<p>x</p>",1,true).unwrap(); }
        assert!(store.stage_web_preview(&uuid::Uuid::new_v4().to_string(),"https://public.com/","https://public.com/",b"x",1,true).is_err());
        let id=store.list_web_previews().unwrap().remove(0).id;
        store.conn.execute("UPDATE web_previews SET html=x'ff' WHERE id=?1",[&id]).unwrap();
        assert!(store.get_web_preview(&id).is_err()); assert_eq!(store.list_web_previews().unwrap().len(),16);
        store.delete_web_preview(&id).unwrap(); assert_eq!(store.list_web_previews().unwrap().len(),15);
    }
}
