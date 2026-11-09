//! Durable, explicitly approved saves. No automatic startup parsing or OS service.
//! An OS file lock, not a clock lease, protects each processing attempt. A dead
//! process releases its lock; a live worker is never stolen by another connection.
use super::*;
use fs2::FileExt;
use std::{fs::{File, OpenOptions}, path::Path};

#[derive(Debug, Serialize)]
pub struct CaptureJob {
 pub id: String, pub format: String, pub status: String,
 pub created_ts: i64, pub updated_ts: i64, pub attempts: i64,
 pub error: Option<String>, pub result_item_id: Option<String>,
}
pub(crate) fn now()->RefractResult<i64>{Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(storage)?.as_secs() as i64)}
fn valid_id(id:&str)->RefractResult<()> {
 if id.len()<16 || id.len()>128 || !id.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'||b==b'_') { return Err(invalid("Invalid capture job identifier")); } Ok(())
}
fn row(r:&rusqlite::Row<'_>)->rusqlite::Result<CaptureJob> {
 Ok(CaptureJob{id:r.get("id")?,format:r.get("format")?,status:r.get("status")?,created_ts:r.get("created_ts")?,updated_ts:r.get("updated_ts")?,attempts:r.get("attempts")?,error:r.get("error")?,result_item_id:r.get("result_item_id")?})
}
fn lock_job(dir:&Path,id:&str)->RefractResult<File> {
 valid_id(id)?;
 let locks=dir.join(".capture-locks");std::fs::create_dir_all(&locks).map_err(storage)?;
 let mut options=OpenOptions::new();options.read(true).write(true).create(true).truncate(false);
 #[cfg(unix)] {use std::os::unix::fs::OpenOptionsExt;options.mode(0o600);}
 let file=options.open(locks.join(format!("{id}.lock"))).map_err(storage)?;
 file.try_lock_exclusive().map_err(|_|invalid("This capture is active in another worker. Wait for its result; it was not cancelled or retried."))?;
 // Keep the inode. Unlinking a lock file would permit a second live lock inode.
 Ok(file)
}
/// Only a job's reserved UUID is eligible. Never sweep the blob directory or
/// remove a file referenced by any item/blob. Caller holds job lock + write tx.
pub(crate) fn remove_owned_orphan(conn:&rusqlite::Connection,path:&Path,item_id:&str)->RefractResult<()> {
 let referenced:bool=conn.query_row("SELECT EXISTS(SELECT 1 FROM items WHERE id=?1) OR EXISTS(SELECT 1 FROM blobs WHERE item_id=?1 OR path=?2)",params![item_id,path.to_string_lossy()],|r|r.get(0)).map_err(storage)?;
 if referenced { return Err(invalid("Reserved capture original is already referenced; no file was removed. Inspect library integrity before retrying.")); }
 match std::fs::remove_file(path) {Ok(())=>Ok(()),Err(e) if e.kind()==std::io::ErrorKind::NotFound=>Ok(()),Err(_)=>Err(invalid("Interrupted capture file could not be removed; retry cleanup after checking storage access"))}
}
impl Store {
 pub fn capture_job(&self,id:&str)->RefractResult<CaptureJob> {
  valid_id(id)?;
  self.conn.query_row("SELECT * FROM capture_jobs WHERE id=?1",params![id],row).optional().map_err(storage)?.ok_or_else(||invalid("Capture job not found"))
 }
 pub fn capture_jobs(&self,limit:u32,offset:u32)->RefractResult<Vec<CaptureJob>> {
  let mut stmt=self.conn.prepare("SELECT * FROM capture_jobs ORDER BY CASE WHEN status IN ('completed','cancelled') THEN 1 ELSE 0 END,created_ts DESC,id LIMIT ?1 OFFSET ?2").map_err(storage)?;
  let rows=stmt.query_map(params![limit.clamp(1,100),offset],row).map_err(storage)?;
  rows.collect::<Result<Vec<_>,_>>().map_err(storage)
 }
 pub fn capture_enqueue(&mut self,id:&str,d:&CaptureDraft)->RefractResult<CaptureJob> {
  valid_id(id)?;
  if d.choice==CaptureChoice::UseExisting { return Err(invalid("Opening an existing copy does not require a durable save job")); }
  // Verify actual current input and review before writing any staging content.
  let (_,hash)=prepare(d)?;
  if d.review_hash.as_deref()!=Some(hash.as_str()) { return Err(invalid("Preview changed input before approving a durable save")); }
  let payload=serde_json::to_string(d).map_err(storage)?;
  let request_hash=sha256_hex(payload.as_bytes());
  let ts=now()?;
  let tx=self.conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate).map_err(storage)?;
  let existing:Option<String>=tx.query_row("SELECT request_hash FROM capture_jobs WHERE id=?1",params![id],|r|r.get(0)).optional().map_err(storage)?;
  if let Some(existing)=existing {
   if existing!=request_hash { return Err(invalid("This save token belongs to different approved input; it cannot be reused")); }
  } else {
   let (count,bytes):(i64,i64)=tx.query_row("SELECT COUNT(*),COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM capture_jobs WHERE payload IS NOT NULL",[],|r|Ok((r.get(0)?,r.get(1)?))).map_err(storage)?;
   if count>=64 || bytes+payload.len() as i64>256*1024*1024 { return Err(invalid("Pending capture staging is full (64 jobs / 256 MiB). Complete or cancel jobs before adding more.")); }
   tx.execute("INSERT INTO capture_jobs(id,request_hash,item_id,format,status,payload,created_ts,updated_ts) VALUES(?1,?2,?3,?4,'queued',?5,?6,?6)",params![id,request_hash,uuid::Uuid::new_v4().to_string(),d.format.source_type().as_str(),payload,ts]).map_err(storage)?;
  }
  tx.commit().map_err(storage)?;
  self.capture_job(id)
 }
 pub fn capture_run(&mut self,id:&str)->RefractResult<CaptureJob> {
  let first=self.capture_job(id)?;
  if first.status=="completed" { return Ok(first); }
  if first.status=="cancelled" { return Err(invalid("Cancelled captures cannot be retried; review a new capture instead")); }
  let _lock=lock_job(&self.blob_dir,id)?;
  let job=self.capture_job(id)?;
  if job.status=="completed" { return Ok(job); }
  if job.status=="cancelled" { return Err(invalid("Capture was cancelled")); }
  self.conn.execute("UPDATE capture_jobs SET status='processing',attempts=attempts+1,error=NULL,updated_ts=?2 WHERE id=?1",params![id,now()?]).map_err(storage)?;
  let outcome=(||->RefractResult<()> {
   let (payload,item_id,request_hash,created):(String,String,String,i64)=self.conn.query_row("SELECT payload,item_id,request_hash,created_ts FROM capture_jobs WHERE id=?1",params![id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).map_err(storage)?;
   if sha256_hex(payload.as_bytes())!=request_hash { return Err(invalid("Staged capture is damaged; cancel it and review the source again")); }
   let draft:CaptureDraft=serde_json::from_str(&payload).map_err(|_|invalid("Invalid staged capture"))?;
   let (mut compiled,hash)=prepare(&draft)?;
   if draft.review_hash.as_deref()!=Some(hash.as_str()) || draft.choice==CaptureChoice::UseExisting { return Err(invalid("Stored approval does not match staged input")); }
   compiled.item.id=item_id;compiled.item.import_ts=created;
   self.insert_item_with_job(&compiled.item,&compiled.original_bytes,&compiled.original_hash,draft.choice!=CaptureChoice::KeepCopy,Some(id))
  })();
  if let Err(error)=outcome {
   // Do not put source snippets, filenames or parser diagnostics in job history.
   let message=match error {RefractError::InvalidInput(_)=>"Capture needs attention: input/approval, duplicate, or reserved-original conflict. Review the source or cancel this job.",RefractError::Parse(_)=>"Extraction failed. Input is retained for explicit retry or cancellation; no automatic parser retry.",_=>"Storage/processing failed. Check storage access and capacity before retrying."};
   self.conn.execute("UPDATE capture_jobs SET status='failed',error=?2,updated_ts=?3 WHERE id=?1 AND status='processing'",params![id,message,now()?]).map_err(storage)?;
  }
  self.capture_job(id)
 }
 pub fn capture_cancel(&mut self,id:&str)->RefractResult<CaptureJob> {
  self.capture_job(id)?;
  let _lock=lock_job(&self.blob_dir,id)?;
  let tx=self.conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate).map_err(storage)?;
  let (status,item_id):(String,String)=tx.query_row("SELECT status,item_id FROM capture_jobs WHERE id=?1",params![id],|r|Ok((r.get(0)?,r.get(1)?))).map_err(storage)?;
  if status=="completed" { return Err(invalid("Completed captures are library items; cancelling must not delete them")); }
  if status!="cancelled" {
   remove_owned_orphan(&tx,&self.blob_dir.join(format!("{item_id}.original")),&item_id)?;
   tx.execute("UPDATE capture_jobs SET status='cancelled',payload=NULL,error=NULL,updated_ts=?2 WHERE id=?1",params![id,now()?]).map_err(storage)?;
  }
  tx.commit().map_err(storage)?;self.capture_job(id)
 }
}

#[cfg(test)]
pub(crate) fn fault_point(point:&str) {
 if std::env::var("REFRACT_JOB_FAULT").ok().as_deref()==Some(point) {
  use std::io::Write;
  println!("CAPTURE_FAULT_READY");std::io::stdout().flush().unwrap();
  loop {std::thread::park();}
 }
}
#[cfg(test)] mod tests;
