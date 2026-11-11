use super::*;
fn draft(format:CaptureFormat,text:&str)->CaptureDraft { CaptureDraft{format,text:Some(text.into()),pdf_base64:None,source_url:None,review_hash:None,choice:CaptureChoice::Save,existing_id:None} }
fn reviewed(s:&Store,mut d:CaptureDraft)->CaptureDraft { d.review_hash=Some(s.capture_preview(&d).unwrap().review_hash);d }
fn cleanup(s:Store) { let path=s.blob_dir.clone();drop(s);let _=std::fs::remove_dir_all(path); }
#[test] fn preview_is_ephemeral_and_save_requires_exact_review() {
 let mut s=Store::open_in_memory().unwrap();let mut d=draft(CaptureFormat::Markdown,"# Local\n\nUnchanged source text.");
 let p=s.capture_preview(&d).unwrap();assert_eq!(p.block_count,2);assert!(s.list_items(100,0).unwrap().is_empty());assert!(!s.blob_dir.exists());
 assert!(s.capture_commit(&d).is_err());d.review_hash=Some(p.review_hash);d.text=Some("Changed after review".into());assert!(s.capture_commit(&d).is_err());
 d=reviewed(&s,d);let r=s.capture_commit(&d).unwrap();assert!(!r.reused_existing);
 assert_eq!(std::fs::read(s.blob_dir.join(format!("{}.original",r.item.id))).unwrap(),d.text.unwrap().as_bytes());cleanup(s);
}
#[test] fn duplicate_choice_is_explicit_and_format_and_origin_are_not_conflated() {
 let mut s=Store::open_in_memory().unwrap();let mut d=reviewed(&s,draft(CaptureFormat::Text,"1 < 2 > 0"));let first=s.capture_commit(&d).unwrap().item;
 let p=s.capture_preview(&d).unwrap();assert_eq!(p.duplicate.unwrap().id,first.id);assert!(s.capture_commit(&d).is_err());
 d.choice=CaptureChoice::UseExisting;d.existing_id=Some(first.id.clone());assert!(s.capture_commit(&d).unwrap().reused_existing);assert_eq!(s.list_items(100,0).unwrap().len(),1);
 d.choice=CaptureChoice::KeepCopy;d.existing_id=None;let second=s.capture_commit(&d).unwrap().item;assert_ne!(first.id,second.id);
 d.format=CaptureFormat::Markdown;d.choice=CaptureChoice::Save;assert!(s.capture_commit(&d).is_err());d=reviewed(&s,d);assert!(s.capture_preview(&d).unwrap().duplicate.is_none());s.capture_commit(&d).unwrap();
 d.source_url=Some("https://example.test/source".into());d=reviewed(&s,d);assert!(s.capture_preview(&d).unwrap().duplicate.is_none());s.capture_commit(&d).unwrap();assert_eq!(s.list_items(100,0).unwrap().len(),4);cleanup(s);
}
#[test] fn reuse_detects_missing_or_modified_original() {
 let mut s=Store::open_in_memory().unwrap();let mut d=reviewed(&s,draft(CaptureFormat::Text,"Original text"));let r=s.capture_commit(&d).unwrap();d.choice=CaptureChoice::UseExisting;d.existing_id=Some(r.item.id.clone());
 let path=s.blob_dir.join(format!("{}.original",r.item.id));std::fs::write(&path,b"tampered").unwrap();assert!(s.capture_commit(&d).is_err());std::fs::remove_file(&path).unwrap();assert!(s.capture_commit(&d).is_err());cleanup(s);
}
#[test] fn changed_saved_input_keeps_prior_source_and_user_organization() {
 let mut s=Store::open_in_memory().unwrap();let mut d=draft(CaptureFormat::Html,"<article><h1>Version one</h1><p>Original body</p></article>");d.source_url=Some("https://example.test/article".into());d=reviewed(&s,d);let first=s.capture_commit(&d).unwrap().item;
 let before=std::fs::read(s.blob_dir.join(format!("{}.original",first.id))).unwrap();
 s.conn.execute("INSERT INTO tags(id,name) VALUES('manual-tag','My explicit tag')",[]).unwrap();s.conn.execute("INSERT INTO item_tags(item_id,tag_id) VALUES(?1,'manual-tag')",params![first.id]).unwrap();
 d.text=Some("<article><h1>Version two</h1><p>Revised body</p></article>".into());let p=s.capture_preview(&d).unwrap();assert_eq!(p.other_saved_inputs_for_url,1);assert!(p.duplicate.is_none());d.review_hash=Some(p.review_hash);let second=s.capture_commit(&d).unwrap().item;
 assert_ne!(first.id,second.id);assert_eq!(std::fs::read(s.blob_dir.join(format!("{}.original",first.id))).unwrap(),before);assert!(s.get_item(&first.id).unwrap().unwrap().blocks.iter().any(|b|b.text=="Original body"));
 assert_eq!(s.conn.query_row("SELECT COUNT(*) FROM item_tags WHERE item_id=?1 AND tag_id='manual-tag'",params![first.id],|r|r.get::<_,i64>(0)).unwrap(),1);cleanup(s);
}
#[test] fn reference_only_is_not_html_and_cannot_fetch_or_save_invalid_urls() {
 let mut s=Store::open_in_memory().unwrap();let d=reviewed(&s,draft(CaptureFormat::UrlReference,"https://example.test/no-fetch?q=kept"));let r=s.capture_commit(&d).unwrap();assert_eq!(r.item.source_type,SourceType::UrlReference);assert_eq!(r.item.source_url.as_deref(),Some("https://example.test/no-fetch?q=kept"));assert_eq!(r.item.blocks.len(),1);
 for bad in ["", "https://", "file:///secret", "https://user:password@example.test", "https:example.test"] {assert!(s.capture_preview(&draft(CaptureFormat::UrlReference,bad)).is_err());}cleanup(s);
}
#[test] fn failed_sql_write_removes_new_blob_and_rolls_back_all_rows() {
 let mut s=Store::open_in_memory().unwrap();let d=reviewed(&s,draft(CaptureFormat::Text,"Never published"));
 s.conn.execute_batch("CREATE TRIGGER simulated_failure BEFORE INSERT ON blocks BEGIN SELECT RAISE(ABORT,'simulated block write failure'); END;").unwrap();
 assert!(s.capture_commit(&d).is_err());assert!(s.list_items(100,0).unwrap().is_empty());assert_eq!(std::fs::read_dir(&s.blob_dir).unwrap().count(),0);
 assert_eq!(s.conn.query_row("SELECT COUNT(*) FROM blobs",[],|r|r.get::<_,i64>(0)).unwrap(),0);assert_eq!(s.conn.query_row("SELECT COUNT(*) FROM blocks_fts",[],|r|r.get::<_,i64>(0)).unwrap(),0);cleanup(s);
}
#[test] fn duplicate_item_id_never_truncates_original_and_path_traversal_is_rejected() {
 let mut s=Store::open_in_memory().unwrap();let d=reviewed(&s,draft(CaptureFormat::Text,"Immutable original"));let first=s.capture_commit(&d).unwrap().item;
 let path=s.blob_dir.join(format!("{}.original",first.id));let before=std::fs::read(&path).unwrap();
 assert!(s.insert_item(&first,b"Overwrite attempt","wrong hash").is_err());assert_eq!(std::fs::read(&path).unwrap(),before);
 let mut bad=first.clone();bad.id="../escape".into();assert!(s.insert_item(&bad,b"bad","bad").is_err());assert_eq!(s.list_items(100,0).unwrap().len(),1);cleanup(s);
}
#[test] fn binary_pdf_roundtrip_survives_restart_and_migration_is_idempotent() {
 let dir=std::env::temp_dir().join(format!("refract-capture-restart-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let db=dir.join("library.db");
 let mut s=Store::open(&db).unwrap();let bytes=include_bytes!("../../../../shared/fixtures/capture/compressed-text.pdf");let mut d=draft(CaptureFormat::Pdf,"");d.text=None;d.pdf_base64=Some(STANDARD.encode(bytes));d=reviewed(&s,d);let item=s.capture_commit(&d).unwrap().item;drop(s);
 let s=Store::open(&db).unwrap();assert_eq!(s.conn.query_row("SELECT value FROM meta WHERE key='schema_version'",[],|r|r.get::<_,String>(0)).unwrap(),"16");assert_eq!(s.get_item(&item.id).unwrap().unwrap().source_type,SourceType::Pdf);assert_eq!(std::fs::read(s.blob_dir.join(format!("{}.original",item.id))).unwrap(),bytes);assert!(s.capture_preview(&d).unwrap().duplicate.is_some());drop(s);std::fs::remove_dir_all(dir).unwrap();
}
#[test] fn wrong_format_invalid_utf8_unsupported_and_oversize_inputs_fail_closed() {
 let s=Store::open_in_memory().unwrap();assert!(serde_json::from_str::<CaptureDraft>(r#"{"format":"docx","text":"bad"}"#).is_err());assert!(serde_json::from_str::<CaptureDraft>(r#"{"format":"text","text":"bad","fetch":true}"#).is_err());
 let mut d=draft(CaptureFormat::Pdf,"not bytes");assert!(s.capture_preview(&d).is_err());d.text=None;d.pdf_base64=Some(STANDARD.encode(b"not PDF"));assert!(s.capture_preview(&d).is_err());d.format=CaptureFormat::Text;assert!(s.capture_preview(&d).is_err());
 for body in ["\0binary".to_string()," ".repeat(2*1024*1024+1)] {assert!(s.capture_preview(&draft(CaptureFormat::Text,&body)).is_err());}assert!(!s.blob_dir.exists());cleanup(s);
}
#[test] fn non_extractable_pdf_is_not_saved_and_suggests_the_ocr_limitation() {
 let mut s=Store::open_in_memory().unwrap();let mut d=draft(CaptureFormat::Pdf,"");d.text=None;
 d.pdf_base64=Some(STANDARD.encode(include_bytes!("../../../../shared/fixtures/capture/no-extractable-text.pdf")));
 let error=s.capture_preview(&d).unwrap_err().to_string();assert!(error.contains("OCR is not available"));
 assert!(s.capture_commit(&d).is_err());assert!(s.list_items(100,0).unwrap().is_empty());assert!(!s.blob_dir.exists());cleanup(s);
}
#[test] fn independent_connections_cannot_silently_double_save_a_reviewed_draft() {
 let dir=std::env::temp_dir().join(format!("refract-capture-race-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let db=dir.join("library.db");let a=Store::open(&db).unwrap();let b=Store::open(&db).unwrap();let d=reviewed(&a,draft(CaptureFormat::Text,"One reviewed capture"));let barrier=std::sync::Arc::new(std::sync::Barrier::new(2));
 let mut threads=Vec::new();for mut s in [a,b] {let gate=barrier.clone();let draft=d.clone();threads.push(std::thread::spawn(move||{gate.wait();s.capture_commit(&draft).is_ok()}));}
 let count:usize=threads.into_iter().map(|t|usize::from(t.join().unwrap())).sum();assert_eq!(count,1);let s=Store::open(&db).unwrap();assert_eq!(s.list_items(100,0).unwrap().len(),1);assert_eq!(std::fs::read_dir(&s.blob_dir).unwrap().count(),1);drop(s);std::fs::remove_dir_all(dir).unwrap();
}
#[test] fn migration_13_to_14_preserves_existing_rows_and_reopens_idempotently() {
 let dir=std::env::temp_dir().join(format!("refract-capture-migration-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let db=dir.join("library.db");
 let conn=rusqlite::Connection::open(&db).unwrap();
 for sql in [crate::MIGRATION_0001,crate::MIGRATION_0002,crate::MIGRATION_0003,crate::MIGRATION_0004,crate::MIGRATION_0005,crate::MIGRATION_0006,crate::MIGRATION_0007,crate::MIGRATION_0008,crate::MIGRATION_0009,crate::MIGRATION_0010,crate::MIGRATION_0011,crate::MIGRATION_0012,crate::MIGRATION_0013] {conn.execute_batch(sql).unwrap();}
 conn.execute("INSERT INTO items(id,source_type,import_ts,content_hash,title) VALUES('legacy','text',42,'legacy-hash','Explicit title')",[]).unwrap();drop(conn);
 for _ in 0..2 {let s=Store::open(&db).unwrap();assert_eq!(s.get_item("legacy").unwrap().unwrap().title.as_deref(),Some("Explicit title"));assert_eq!(s.conn.query_row("SELECT value FROM meta WHERE key='schema_version'",[],|r|r.get::<_,String>(0)).unwrap(),"16");}std::fs::remove_dir_all(dir).unwrap();
}
