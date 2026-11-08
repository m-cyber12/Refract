//! Advanced Knowledge: explicit decisions, navigable stored connections,
//! discardable extractive overviews and honest source history. No profiling.
use crate::Store;
use refract_core::{Item,RefractError,RefractResult};
use rusqlite::params;

mod decisions;
mod graph;
mod compression;
mod source;
pub use decisions::*;
pub use graph::*;
pub use compression::*;
pub use source::*;
fn err(e:impl std::fmt::Display)->RefractError{RefractError::storage(e.to_string())}
fn now()->RefractResult<i64>{Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_secs() as i64)}
fn fingerprint(item:&Item)->RefractResult<String>{Ok(evidence_engine::sha256_hex(serde_json::to_string(&item.blocks).map_err(err)?.as_bytes()))}
impl Store{
 fn knowledge_item(&self,id:&str)->RefractResult<Item>{self.get_item(id)?.ok_or_else(||RefractError::invalid("knowledge source not found"))}
 fn knowledge_eligible(&self,id:&str)->RefractResult<bool>{Ok(self.conn.query_row("SELECT COUNT(*) FROM items WHERE id=?1 AND sense_decision!='ignore'",params![id],|r|r.get::<_,i64>(0)).map_err(err)?>0)}
}

#[cfg(test)]mod tests{
 use super::*;use refract_core::{Block,BlockKind,ImportStatus,SourceType};
 fn add(s:&mut Store,id:&str,text:&str,ts:i64){s.insert_item(&Item{id:id.into(),title:Some(id.into()),source_url:Some("https://example.org/reference".into()),source_type:SourceType::Text,import_ts:ts,content_hash:evidence_engine::sha256_hex(text.as_bytes()),author:None,language:None,extraction_confidence:0.9,status:ImportStatus::Ready,blocks:vec![Block{idx:0,kind:BlockKind::Paragraph,text:text.into()}]},text.as_bytes(),&evidence_engine::sha256_hex(text.as_bytes())).unwrap();s.conn.execute("UPDATE items SET sense_decision='auto_save' WHERE id=?1",params![id]).unwrap();}
 fn decision()->DecisionInput{DecisionInput{title:"Choose SQLite".into(),context:"Local-first project database".into(),options:vec!["SQLite".into(),"Remote DB".into()],selected_option:"SQLite".into(),reasoning:"Offline operation and no external account".into(),decision_ts:1700000000,expected_outcome:"Local storage".into(),..Default::default()}}
 #[test]fn explicit_decisions_validation_revision_and_recall(){
  let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","SQLite supports local data.",1700000000);let mut input=decision();input.source_ids=vec!["a".into()];let d=s.decision_save(&input).unwrap();assert_eq!(d.kind,"user_recorded_decision");assert_eq!(s.decision_history(&d.id).unwrap().len(),1);
  input.id=Some(d.id.clone());input.reasoning="Transactional local storage".into();s.decision_save(&input).unwrap();assert_eq!(s.decision_history(&d.id).unwrap().len(),2);
  let result=s.recall(&crate::recall::RecallRequest{query:"Why did I choose SQLite for this project?".into(),mode:"answer".into(),..Default::default()}).unwrap();assert_eq!(result.decision_records[0].id,d.id);assert!(result.answer_kind.contains("user_record"));
  let filtered=s.recall(&crate::recall::RecallRequest{query:"SQLite".into(),mode:"answer".into(),source_type:Some("pdf".into()),..Default::default()}).unwrap();assert!(filtered.decision_records.is_empty());
  s.decision_archive(&d.id,true).unwrap();assert!(s.decision_search(&DecisionQuery::default()).unwrap().is_empty());assert!(s.decision_get(&d.id).unwrap().archived);s.decision_archive(&d.id,false).unwrap();assert_eq!(s.decision_search(&DecisionQuery::default()).unwrap().len(),1);
  input.selected_option="Not considered".into();assert!(s.decision_save(&input).is_err());assert_eq!(s.decision_get(&d.id).unwrap().selected_option,"SQLite");
 }
 #[test]fn decision_missing_source_rolls_back_and_no_inferred_decisions(){let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Decision: choose SQLite. This is merely imported text.",1700000000);assert!(s.decision_search(&DecisionQuery::default()).unwrap().is_empty());let mut i=decision();i.source_ids=vec!["missing".into()];assert!(s.decision_save(&i).is_err());assert!(s.decision_search(&DecisionQuery::default()).unwrap().is_empty());}
 #[test]fn graph_navigation_filters_pagination_and_dismissal(){
  let mut s=Store::open_in_memory().unwrap();for i in 0..4{add(&mut s,&format!("s{i}"),"Privacy GDPR reference",1700000000+i);}
  let page=s.knowledge_graph(&GraphRequest{category:Some("document".into()),limit:Some(2),..Default::default()}).unwrap();assert_eq!(page.nodes.len(),2);assert_eq!(page.next_offset,Some(2));assert!(page.edges.iter().all(|e|e.kind=="navigation_index"));
  let topic=s.list_topics().unwrap().remove(0);let children=s.knowledge_graph(&GraphRequest{kind:"topic".into(),id:topic.id,category:Some("document".into()),after:Some(1700000002),..Default::default()}).unwrap();assert_eq!(children.nodes.len(),2);assert!(children.edges.iter().all(|e|e.relationship_id.is_none()));
  let mut path=PathRequest{from_id:"s0".into(),to_id:"s1".into(),max_depth:Some(1)};let found=s.knowledge_path(&path).unwrap();assert!(found.found);s.dismiss_relationship(&found.steps[0].relationship_id).unwrap();assert!(!s.knowledge_path(&path).unwrap().found);path.max_depth=Some(0);assert!(s.knowledge_path(&path).is_err());
 }
 #[test]fn graph_contains_notes_events_decisions_and_projects(){
  let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy meeting 2027-01-01",1700000000);let project=s.create_project("Thesis",None).unwrap();s.project_add_item(&project.id,"a").unwrap();s.add_annotation("a","Privacy",Some("Question: what changed?"),Some(0)).unwrap();let mut i=decision();i.source_ids=vec!["a".into()];i.project_id=Some(project.id);s.decision_save(&i).unwrap();
  let page=s.knowledge_graph(&GraphRequest{kind:"document".into(),id:"a".into(),limit:Some(40),..Default::default()}).unwrap();for kind in["topic","project","note","event","decision"]{assert!(page.nodes.iter().any(|n|n.kind==kind),"missing {kind}");}
 }
 #[test]fn compression_is_source_backed_stale_aware_regenerable_and_discardable(){
  let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy GDPR. What is the policy?",1700000000);add(&mut s,"b","Privacy GDPR disagrees on retention.",1700000001);s.add_relationship("a","b","contradicting_source","user marked disagreement").unwrap();let before=s.get_item("a").unwrap();
  let c=s.compression_create(&CompressionInput{scope_kind:"selected".into(),item_ids:vec!["a".into(),"b".into()],..Default::default()}).unwrap();assert_eq!(c.excerpts.len(),2);assert!(!c.disagreements.is_empty());assert!(!c.questions.is_empty());for e in &c.excerpts{let item=s.knowledge_item(&e.item_id).unwrap();assert!(item.blocks[e.block_idx as usize].text.contains(&e.quote));}assert_eq!(before,s.get_item("a").unwrap());
  s.conn.execute("UPDATE blocks SET text='Changed privacy reference' WHERE item_id='a'",[]).unwrap();assert_eq!(s.compression_get(&c.id).unwrap().stale_source_ids,vec!["a"]);let regen=s.compression_regenerate(&c.id).unwrap();assert_eq!(regen.id,c.id);assert!(s.compression_get(&c.id).unwrap().stale_source_ids.is_empty());s.compression_discard(&c.id).unwrap();assert!(s.compression_get(&c.id).is_err());assert!(s.get_item("a").unwrap().is_some());
 }
 #[test]fn compression_detects_project_membership_changes(){let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy",1700000000);add(&mut s,"b","Security",1700000000);let p=s.create_project("P",None).unwrap();s.project_add_item(&p.id,"a").unwrap();let c=s.compression_create(&CompressionInput{scope_kind:"project".into(),scope_id:Some(p.id.clone()),..Default::default()}).unwrap();s.project_add_item(&p.id,"b").unwrap();assert!(s.compression_get(&c.id).unwrap().scope_changed);assert_eq!(s.compression_regenerate(&c.id).unwrap().source_ids.len(),2);}
 #[test]fn source_history_does_not_fabricate_legacy_processing_or_overwrite_versions(){let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","First archived line",100);add(&mut s,"b","Second archived line",200);let before=s.get_item("a").unwrap();let info=s.source_intelligence("a").unwrap();assert_eq!(info.history.len(),2);assert_eq!(info.versions[0].item_id,"b");s.knowledge_record_snapshot("a").unwrap();assert_eq!(s.source_intelligence("a").unwrap().history.len(),2);let diff=s.source_diff(&SourceDiffRequest{before_id:"a".into(),after_id:"b".into()}).unwrap();assert!(diff.same_saved_url);assert_eq!(diff.removed[0].quote,"First archived line");assert_eq!(diff.added[0].quote,"Second archived line");assert_eq!(before,s.get_item("a").unwrap());s.conn.execute("DELETE FROM source_history WHERE item_id='a'",[]).unwrap();assert!(s.source_intelligence("a").unwrap().history.is_empty());}
 #[test]fn v8_upgrade_and_ignored_map_sources(){let conn=rusqlite::Connection::open_in_memory().unwrap();for sql in[crate::MIGRATION_0001,crate::MIGRATION_0002,crate::MIGRATION_0003,crate::MIGRATION_0004,crate::MIGRATION_0005,crate::MIGRATION_0006,crate::MIGRATION_0007,crate::MIGRATION_0008]{conn.execute_batch(sql).unwrap();}let mut s=Store{conn,blob_dir:std::env::temp_dir().join(uuid::Uuid::new_v4().to_string())};s.migrate().unwrap();s.migrate().unwrap();add(&mut s,"a","Privacy",100);s.conn.execute("UPDATE items SET sense_decision='ignore' WHERE id='a'",[]).unwrap();assert!(s.knowledge_graph(&GraphRequest{kind:"document".into(),id:"a".into(),..Default::default()}).is_err());}
 #[test]fn derived_metadata_and_provenance_are_current_and_discard_isolated(){
  let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy GDPR reference?",100);let c=s.compression_create(&CompressionInput{scope_kind:"selected".into(),item_ids:vec!["a".into()],..Default::default()}).unwrap();assert!(!s.compression_get(&c.id).unwrap().metadata_changed);
  assert!(c.concepts.iter().all(|n|n.source_ids==vec!["a"]));assert!(s.source_intelligence("a").unwrap().artifacts.iter().any(|a|a.kind=="derived_extractive_compression"&&a.version==c.id));
  s.conn.execute("UPDATE items SET title='Renamed original' WHERE id='a'",[]).unwrap();assert!(s.compression_get(&c.id).unwrap().metadata_changed);assert!(s.compression_get(&c.id).unwrap().stale_source_ids.is_empty());s.compression_regenerate(&c.id).unwrap();assert!(!s.compression_get(&c.id).unwrap().metadata_changed);s.compression_discard(&c.id).unwrap();assert!(!s.source_intelligence("a").unwrap().artifacts.iter().any(|a|a.kind=="derived_extractive_compression"));assert!(s.get_item("a").unwrap().is_some());
 }
 #[test]fn explicit_project_decisions_suppress_only_the_corresponding_signal_gap(){
  let mut s=Store::open_in_memory().unwrap();let ts=now().unwrap();add(&mut s,"a","Privacy GDPR reference",ts);add(&mut s,"b","Privacy GDPR second reference",ts);let p=s.create_project("Thesis",None).unwrap();s.project_add_item(&p.id,"a").unwrap();s.project_add_item(&p.id,"b").unwrap();let key=format!("gap:project:{}",p.id);
  let before=s.daily_signal(true).unwrap();assert!(before.entries.iter().any(|e|e.key==key));let mut input=decision();input.project_id=Some(p.id);let d=s.decision_save(&input).unwrap();assert!(!s.daily_signal(true).unwrap().entries.iter().any(|e|e.key==key));s.decision_archive(&d.id,true).unwrap();assert!(s.daily_signal(true).unwrap().entries.iter().any(|e|e.key==key));
 }

}
