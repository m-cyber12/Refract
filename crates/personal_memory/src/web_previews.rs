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
#[derive(Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WebPreviewSummary {
    pub id: String,
    pub requested_url: String,
    pub final_url: String,
    pub byte_len: i64,
    pub sha256: String,
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
        let existing: Option<(String, String, Option<Vec<u8>>, i64)> = tx.query_row("SELECT requested_url, final_url, CASE WHEN length(html) BETWEEN 1 AND ?2 THEN html ELSE NULL END, consent_ts FROM web_previews WHERE id=?1", params![id,MAX_BYTES as i64], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).optional().map_err(err)?;
        if let Some((old_requested, old_final, old_html, old_ts)) = existing {
            if old_requested == requested && old_final == final_url && old_html.as_deref() == Some(html) && old_ts == consent_ts { return Ok(()); }
            return Err(RefractError::invalid("Preview ID is already used by another copy"));
        }
        let (count, total): (i64, i64) = tx.query_row("SELECT COUNT(*), COALESCE(SUM(length(html)),0) FROM web_previews", [], |r| Ok((r.get(0)?,r.get(1)?))).map_err(err)?;
        if count >= MAX_COUNT || total + html.len() as i64 > MAX_TOTAL { return Err(RefractError::invalid("Web preview storage is full; review or discard copies first")); }
        tx.execute("INSERT INTO web_previews(id,requested_url,final_url,html,sha256,consent_ts) VALUES(?1,?2,?3,?4,?5,?6)", params![id, requested, final_url, html, hash, consent_ts]).map_err(err)?;
        tx.commit().map_err(err)
    }
    pub fn list_web_previews(&self) -> RefractResult<Vec<WebPreviewSummary>> {
        let mut statement = self.conn.prepare("SELECT id,requested_url,final_url,length(html),sha256,consent_ts FROM web_previews ORDER BY consent_ts,id LIMIT 16").map_err(err)?;
        let rows = statement.query_map([], |r| Ok(WebPreviewSummary { id:r.get(0)?, requested_url:r.get(1)?, final_url:r.get(2)?, byte_len:r.get(3)?, sha256:r.get(4)?, consent_ts:r.get(5)? })).map_err(err)?;
        rows.collect::<Result<Vec<_>,_>>().map_err(err)
    }
    pub fn get_web_preview(&self, id: &str) -> RefractResult<WebPreview> {
        check_id(id)?;
        let row: Option<(String,String,Option<Vec<u8>>,String,i64)> = self.conn.query_row("SELECT requested_url,final_url,CASE WHEN length(html) BETWEEN 1 AND ?2 THEN html ELSE NULL END,sha256,consent_ts FROM web_previews WHERE id=?1", params![id,MAX_BYTES as i64], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?))).optional().map_err(err)?;
        let (requested_url,final_url,bytes,sha256,consent_ts) = row.ok_or_else(||RefractError::invalid("Preview not found"))?;
        let bytes=bytes.ok_or_else(||RefractError::invalid("Preview is damaged; discard it explicitly or try again"))?;
        if sha256_hex(&bytes) != sha256 || consent_ts < 0 || consent_ts > 253402300799 || validate_source_url(&requested_url).is_err() || validate_source_url(&final_url).is_err() { return Err(RefractError::invalid("Preview is damaged; discard it explicitly or try again")); }
        let html = String::from_utf8(bytes).map_err(|_|RefractError::invalid("Preview is damaged"))?;
        if html.contains('\0') { return Err(RefractError::invalid("Preview is damaged")); }
        Ok(WebPreview { id:id.to_string(), requested_url, final_url, html, sha256, consent_ts })
    }
    /// Cleanup after saving a reviewed preview. A write transaction binds the
    /// check and delete; SHA-256 is a consistency check, not authenticity.
    pub fn delete_saved_web_preview(&mut self, id: &str, requested: &str, final_url: &str, hash: &str, consent_ts: i64) -> RefractResult<bool> {
        check_id(id)?;
        if hash.len()!=64 || !hash.bytes().all(|b|b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) || consent_ts < 0 || consent_ts > 253402300799 { return Err(RefractError::invalid("Invalid preview cleanup binding")); }
        let tx=self.conn.transaction_with_behavior(TransactionBehavior::Immediate).map_err(err)?;
        let bytes:Option<Vec<u8>>=tx.query_row("SELECT html FROM web_previews WHERE id=?1 AND requested_url=?2 AND final_url=?3 AND sha256=?4 AND consent_ts=?5 AND length(html) BETWEEN 1 AND ?6",
            params![id,requested,final_url,hash,consent_ts,MAX_BYTES as i64],|row|row.get(0)).optional().map_err(err)?;
        let Some(bytes)=bytes else { return Ok(false); };
        if sha256_hex(&bytes)!=hash { return Ok(false); }
        tx.execute("DELETE FROM web_previews WHERE id=?1",[id]).map_err(err)?;
        tx.commit().map_err(err)?; Ok(true)
    }
    /// Explicit UI discard is scoped to the summary the user selected. This
    /// still permits discarding damaged bytes; metadata is not authentication.
    pub fn delete_selected_web_preview(&mut self, selected:&WebPreviewSummary) -> RefractResult<bool> {
        check_id(&selected.id)?;
        let n=self.conn.execute("DELETE FROM web_previews WHERE id=?1 AND requested_url=?2 AND final_url=?3 AND length(html)=?4 AND sha256=?5 AND consent_ts=?6",
            params![selected.id,selected.requested_url,selected.final_url,selected.byte_len,selected.sha256,selected.consent_ts]).map_err(err)?;
        Ok(n==1)
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
    #[test] fn saved_cleanup_only_deletes_the_exact_bound_copy() {
        let mut store=Store::open_in_memory().unwrap();let id=uuid::Uuid::new_v4().to_string();
        let requested="https://public.com/a";let final_url="https://public.com/b";let html="\u{feff}<p>東京</p>";let hash=sha256_hex(html.as_bytes());let other=sha256_hex(b"changed");
        store.stage_web_preview(&id,requested,final_url,html.as_bytes(),123,true).unwrap();
        for (r,f,h,t) in [("https://public.com/changed",final_url,hash.as_str(),123),(requested,"https://public.com/changed",hash.as_str(),123),(requested,final_url,other.as_str(),123),(requested,final_url,hash.as_str(),124)] {
            assert!(!store.delete_saved_web_preview(&id,r,f,h,t).unwrap());assert_eq!(store.get_web_preview(&id).unwrap().html,html);
        }
        store.conn.execute("UPDATE web_previews SET html=x'4142' WHERE id=?1",[&id]).unwrap();
        assert!(!store.delete_saved_web_preview(&id,requested,final_url,&hash,123).unwrap());
        store.conn.execute("UPDATE web_previews SET html=?2 WHERE id=?1",params![id,html.as_bytes()]).unwrap();
        store.conn.execute("UPDATE web_previews SET sha256='damaged' WHERE id=?1",[&id]).unwrap();
        assert!(!store.delete_saved_web_preview(&id,requested,final_url,&hash,123).unwrap());
        store.delete_web_preview(&id).unwrap();
        store.stage_web_preview(&id,requested,final_url,b"replacement",124,true).unwrap();
        assert!(!store.delete_saved_web_preview(&id,requested,final_url,&hash,123).unwrap());
        assert_eq!(store.get_web_preview(&id).unwrap().html,"replacement");
        assert!(store.delete_saved_web_preview(&id,requested,final_url,&sha256_hex(b"replacement"),124).unwrap());
        assert!(!store.delete_saved_web_preview(&id,requested,final_url,&sha256_hex(b"replacement"),124).unwrap());
    }
    #[test] fn selected_discard_leaves_replacement_and_can_remove_damaged_copy() {
        let mut s=Store::open_in_memory().unwrap();let id=uuid::Uuid::new_v4().to_string();
        s.stage_web_preview(&id,"https://public.com/a","https://public.com/b",b"first",12,true).unwrap();
        let selected=s.list_web_previews().unwrap().remove(0);
        s.delete_web_preview(&id).unwrap();s.stage_web_preview(&id,"https://public.com/a","https://public.com/b",b"later",12,true).unwrap();
        assert!(!s.delete_selected_web_preview(&selected).unwrap());assert_eq!(s.get_web_preview(&id).unwrap().html,"later");
        s.conn.execute("UPDATE web_previews SET html=x'ff' WHERE id=?1",[&id]).unwrap();
        let damaged=s.list_web_previews().unwrap().remove(0);assert!(s.get_web_preview(&id).is_err());
        assert!(s.delete_selected_web_preview(&damaged).unwrap());assert!(s.list_web_previews().unwrap().is_empty());
    }
    #[test] fn oversized_damaged_preview_is_retained_and_never_loaded_as_valid() {
        let mut s=Store::open_in_memory().unwrap();let id=uuid::Uuid::new_v4().to_string();
        s.stage_web_preview(&id,"https://public.com/a","https://public.com/b",b"first",12,true).unwrap();
        s.conn.execute("UPDATE web_previews SET html=zeroblob(?2) WHERE id=?1",params![id,MAX_BYTES as i64+1]).unwrap();
        assert!(s.get_web_preview(&id).err().unwrap().to_string().contains("damaged"));
        assert!(s.stage_web_preview(&id,"https://public.com/a","https://public.com/b",b"first",12,true).is_err());
        let item=s.list_web_previews().unwrap().remove(0);assert_eq!(item.byte_len,MAX_BYTES as i64+1);
        assert!(s.delete_selected_web_preview(&item).unwrap());
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
