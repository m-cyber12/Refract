use super::*;
fn draft(s:&Store,choice:CaptureChoice)->CaptureDraft {
 let mut d=CaptureDraft{format:CaptureFormat::Text,text:Some("Approved source only. Unicode café 東京.".into()),pdf_base64:None,source_url:None,review_hash:None,choice,existing_id:None};
 d.review_hash=Some(s.capture_preview(&d).unwrap().review_hash);d
}
const ID:&str="approved-job-token-1234567890";
fn cleanup(s:Store){let path=s.blob_dir.clone();drop(s);let _=std::fs::remove_dir_all(path);}
#[test] fn only_reviewed_input_is_staged_and_tokens_are_bound() {
 let mut s=Store::open_in_memory().unwrap();let mut d=draft(&s,CaptureChoice::Save);d.review_hash=None;
 assert!(s.capture_enqueue(ID,&d).is_err());assert!(s.capture_jobs(100,0).unwrap().is_empty());assert!(!s.blob_dir.exists());
 d=draft(&s,CaptureChoice::Save);assert_eq!(s.capture_enqueue(ID,&d).unwrap().status,"queued");
 assert!(s.list_items(100,0).unwrap().is_empty());assert!(!s.blob_dir.exists());
 assert_eq!(s.capture_enqueue(ID,&d).unwrap().id,ID);assert_eq!(s.capture_jobs(100,0).unwrap().len(),1);
 d.text=Some("Changed approved input".into());d.review_hash=Some(s.capture_preview(&d).unwrap().review_hash);assert!(s.capture_enqueue(ID,&d).is_err());
 assert!(!serde_json::to_string(&s.capture_jobs(100,0).unwrap()).unwrap().contains("Unicode café"));cleanup(s);
}
#[test] fn completed_job_is_idempotent_even_for_keep_copy_and_clears_active_payload() {
 let mut s=Store::open_in_memory().unwrap();let d=draft(&s,CaptureChoice::KeepCopy);s.capture_enqueue(ID,&d).unwrap();
 s.conn.execute("UPDATE capture_jobs SET created_ts=42 WHERE id=?1",params![ID]).unwrap();
 let first=s.capture_run(ID).unwrap();assert_eq!(first.status,"completed");
 assert!(s.get_item(first.result_item_id.as_deref().unwrap()).unwrap().unwrap().import_ts>42);assert_eq!(first.attempts,1);
 let again=s.capture_run(ID).unwrap();assert_eq!(first.result_item_id,again.result_item_id);assert_eq!(again.attempts,1);assert_eq!(s.list_items(100,0).unwrap().len(),1);
 let payload:Option<String>=s.conn.query_row("SELECT payload FROM capture_jobs WHERE id=?1",params![ID],|r|r.get(0)).unwrap();assert!(payload.is_none());assert!(s.capture_cancel(ID).is_err());
 let original=std::fs::read(s.blob_dir.join(format!("{}.original",first.result_item_id.unwrap()))).unwrap();assert_eq!(original,d.text.unwrap().as_bytes());cleanup(s);
}
#[test] fn failure_retains_input_retry_succeeds_and_cancel_is_terminal() {
 let mut s=Store::open_in_memory().unwrap();let d=draft(&s,CaptureChoice::Save);s.capture_enqueue(ID,&d).unwrap();
 s.conn.execute_batch("CREATE TRIGGER fail_capture BEFORE INSERT ON blocks BEGIN SELECT RAISE(ABORT,'failure'); END").unwrap();
 let failed=s.capture_run(ID).unwrap();assert_eq!(failed.status,"failed");assert!(failed.error.is_some());assert!(s.list_items(100,0).unwrap().is_empty());
 assert!(s.conn.query_row("SELECT payload IS NOT NULL FROM capture_jobs WHERE id=?1",params![ID],|r|r.get::<_,bool>(0)).unwrap());
 s.conn.execute_batch("DROP TRIGGER fail_capture").unwrap();let done=s.capture_run(ID).unwrap();assert_eq!(done.status,"completed");assert_eq!(done.attempts,2);
 let other="other-approved-token-123456";s.capture_enqueue(other,&d).unwrap();assert_eq!(s.capture_run(other).unwrap().status,"failed");
 assert_eq!(s.capture_cancel(other).unwrap().status,"cancelled");assert!(s.capture_run(other).is_err());assert_eq!(s.list_items(100,0).unwrap().len(),1);cleanup(s);
}
#[test] fn active_worker_lock_cannot_be_stolen_or_cancelled() {
 let mut s=Store::open_in_memory().unwrap();let d=draft(&s,CaptureChoice::Save);s.capture_enqueue(ID,&d).unwrap();
 let lock=lock_job(&s.blob_dir,ID).unwrap();assert!(s.capture_run(ID).is_err());assert!(s.capture_cancel(ID).is_err());assert_eq!(s.capture_job(ID).unwrap().status,"queued");
 drop(lock);assert_eq!(s.capture_run(ID).unwrap().status,"completed");cleanup(s);
}
#[test] fn orphan_cleanup_is_scoped_and_referenced_files_are_never_deleted() {
 let mut s=Store::open_in_memory().unwrap();let d=draft(&s,CaptureChoice::Save);s.capture_enqueue(ID,&d).unwrap();
 let reserved:String=s.conn.query_row("SELECT item_id FROM capture_jobs WHERE id=?1",params![ID],|r|r.get(0)).unwrap();std::fs::create_dir_all(&s.blob_dir).unwrap();
 let orphan=s.blob_dir.join(format!("{reserved}.original"));std::fs::write(&orphan,b"partial").unwrap();let unrelated=s.blob_dir.join("unrelated.original");std::fs::write(&unrelated,b"keep").unwrap();
 assert_eq!(s.capture_run(ID).unwrap().status,"completed");assert_eq!(std::fs::read(&unrelated).unwrap(),b"keep");assert_eq!(std::fs::read(&orphan).unwrap(),d.text.unwrap().as_bytes());
 assert!(remove_owned_orphan(&s.conn,&orphan,&reserved).is_err());assert!(orphan.exists());cleanup(s);
}
#[test] fn staging_capacity_is_bounded() {
 let mut s=Store::open_in_memory().unwrap();let d=draft(&s,CaptureChoice::Save);
 for n in 0..64{s.capture_enqueue(&format!("capacity-job-token-{n:04}"),&d).unwrap();}
 assert!(s.capture_enqueue("capacity-job-token-overflow",&d).is_err());assert_eq!(s.capture_jobs(100,0).unwrap().len(),64);
 s.capture_cancel("capacity-job-token-0000").unwrap();s.capture_enqueue("capacity-job-token-replacement",&d).unwrap();cleanup(s);
}
// The parent launches this exact test in a separate process and kills it after
// a test-only fault hook signals a durable boundary. No fault hooks ship in FFI.
#[test] fn crash_worker() {
 if let Ok(path)=std::env::var("REFRACT_JOB_TEST_DB") { let mut s=Store::open(path).unwrap();s.capture_run(ID).unwrap(); }
}
#[test] fn real_process_kill_recovers_before_commit_and_never_duplicates_after_commit() {
 use std::io::BufRead;
 for point in ["after_original_sync","before_commit","after_commit"] {
  let dir=std::env::temp_dir().join(format!("refract-job-kill-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let db=dir.join("library.db");
  let mut s=Store::open(&db).unwrap();let d=draft(&s,CaptureChoice::KeepCopy);s.capture_enqueue(ID,&d).unwrap();drop(s);
  let mut child=std::process::Command::new(std::env::current_exe().unwrap()).args(["--exact","capture::jobs::tests::crash_worker","--nocapture"]).env("REFRACT_JOB_TEST_DB",&db).env("REFRACT_JOB_FAULT",point).stdout(std::process::Stdio::piped()).spawn().unwrap();
  let reader=std::io::BufReader::new(child.stdout.take().unwrap());let mut reached=false;
  for line in reader.lines(){if line.unwrap().contains("CAPTURE_FAULT_READY"){reached=true;break;}}
  if !reached {let _=child.kill();let _=child.wait();panic!("Child did not reach {point}");}
  child.kill().unwrap();child.wait().unwrap();
  let mut s=Store::open(&db).unwrap();let state=s.capture_job(ID).unwrap();assert_eq!(state.status,if point=="after_commit"{"completed"}else{"processing"});
  let resumed=s.capture_run(ID).unwrap();assert_eq!(resumed.status,"completed");assert_eq!(s.list_items(100,0).unwrap().len(),1);
  assert_eq!(std::fs::read(s.blob_dir.join(format!("{}.original",resumed.result_item_id.unwrap()))).unwrap(),d.text.unwrap().as_bytes());
  assert_eq!(s.capture_run(ID).unwrap().status,"completed");assert_eq!(s.list_items(100,0).unwrap().len(),1);drop(s);std::fs::remove_dir_all(dir).unwrap();
 }
}

#[test] fn migration_14_to_15_preserves_sources_and_is_repeatable() {
 let dir=std::env::temp_dir().join(format!("refract-v14-jobs-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let db=dir.join("library.db");
 let mut s=Store::open(&db).unwrap();let d=draft(&s,CaptureChoice::Save);let saved=s.capture_commit(&d).unwrap().item;
 let original=std::fs::read(s.blob_dir.join(format!("{}.original",saved.id))).unwrap();
 s.conn.execute_batch("DROP TABLE capture_jobs; UPDATE meta SET value='14' WHERE key='schema_version';").unwrap();drop(s);
 for _ in 0..2 {let s=Store::open(&db).unwrap();assert!(s.capture_jobs(100,0).unwrap().is_empty());assert_eq!(s.get_item(&saved.id).unwrap().unwrap().blocks[0].text,saved.blocks[0].text);assert_eq!(std::fs::read(s.blob_dir.join(format!("{}.original",saved.id))).unwrap(),original);assert_eq!(s.conn.query_row("SELECT value FROM meta WHERE key='schema_version'",[],|r|r.get::<_,String>(0)).unwrap(),"16");}
 std::fs::remove_dir_all(dir).unwrap();
}
