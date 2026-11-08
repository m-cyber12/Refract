use super::*;
use serde::{Deserialize,Serialize};
use rusqlite::OptionalExtension;
use std::collections::{BTreeMap,BTreeSet};
#[derive(Debug,Default,Deserialize)]#[serde(default,deny_unknown_fields)]
pub struct CompressionInput{pub title:String,pub scope_kind:String,pub scope_id:Option<String>,pub item_ids:Vec<String>}
#[derive(Debug,Clone,Serialize,Deserialize)]pub struct KnowledgeExcerpt{pub item_id:String,pub title:String,pub block_idx:u32,pub quote:String,pub kind:String}
#[derive(Debug,Clone,Serialize,Deserialize)]pub struct KnowledgeTime{pub item_id:String,pub kind:String,pub ts:i64,pub note:Option<String>}
#[derive(Debug,Clone,Serialize,Deserialize)]pub struct NamedCount{pub name:String,pub count:usize,#[serde(default)]pub source_ids:Vec<String>}
#[derive(Debug,Clone,Serialize,Deserialize)]pub struct CompressionLink{pub source_item_id:String,pub target_item_id:String,pub basis:String,pub confidence:f64}
#[derive(Debug,Clone,Serialize,Deserialize)]pub struct MemoryCompression{
 pub id:String,pub title:String,pub scope_kind:String,pub scope_id:Option<String>,pub selected_ids:Vec<String>,pub source_ids:Vec<String>,pub generated_ts:i64,
 pub excerpts:Vec<KnowledgeExcerpt>,pub concepts:Vec<NamedCount>,pub entities:Vec<NamedCount>,pub timeline:Vec<KnowledgeTime>,pub disagreements:Vec<CompressionLink>,pub questions:Vec<KnowledgeExcerpt>,pub source_hashes:BTreeMap<String,String>,pub scope_hash:String,pub stale_source_ids:Vec<String>,pub scope_changed:bool,#[serde(default)]pub basis_hash:String,#[serde(default)]pub metadata_changed:bool,pub limitations:Vec<String>,pub kind:String,
}
#[derive(Debug,Serialize)]pub struct CompressionSummary{pub id:String,pub title:String,pub generated_ts:i64,pub scope_kind:String}
impl Store{
 fn compression_basis(&self,ids:&[String])->RefractResult<String>{
  let mut basis=Vec::<serde_json::Value>::new();
  for id in ids{
   let item=self.knowledge_item(id)?;basis.push(serde_json::json!([id,item.title,item.import_ts]));
   for sql in ["SELECT 'topic',n.id,n.name FROM topics n JOIN item_topics l ON l.topic_id=n.id WHERE l.item_id=?1 ORDER BY n.id","SELECT 'entity',n.id,n.name FROM entities n JOIN item_entities l ON l.entity_id=n.id WHERE l.item_id=?1 ORDER BY n.id"]{
    let mut stmt=self.conn.prepare(sql).map_err(err)?;
    let rows=stmt.query_map(params![id],|r|Ok(serde_json::json!([r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?]))).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;basis.push(serde_json::json!(rows));
   }
   let mut stmt=self.conn.prepare("SELECT kind,ts,note FROM item_times WHERE item_id=?1 ORDER BY ts,id LIMIT 20").map_err(err)?;
   let times=stmt.query_map(params![id],|r|Ok(serde_json::json!([r.get::<_,String>(0)?,r.get::<_,i64>(1)?,r.get::<_,Option<String>>(2)?]))).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;basis.push(serde_json::json!(times));
  }
  for link in self.list_relationships(None,2000)?{if link.kind=="contradicting_source"&&ids.contains(&link.source_item_id)&&ids.contains(&link.target_item_id){basis.push(serde_json::json!([link.id,link.source_item_id,link.target_item_id,link.basis,link.confidence]));}}
  Ok(evidence_engine::sha256_hex(serde_json::to_vec(&basis).map_err(err)?.as_slice()))
 }
 fn compression_scope(&self,input:&CompressionInput)->RefractResult<(Vec<String>,String,bool)>{
  if input.title.chars().count()>200||input.item_ids.len()>30{return Err(RefractError::invalid("compression title exceeds 200 characters"));}
  let(mut ids,total)=if input.scope_kind=="selected"{
   let ids=input.item_ids.iter().cloned().collect::<BTreeSet<_>>();if ids.is_empty()||ids.len()>30{return Err(RefractError::invalid("select 1–30 sources for compression"));}for id in &ids{if !self.knowledge_eligible(id)?{return Err(RefractError::invalid("selected compression source is missing or ignored"));}}let total=ids.len();(ids.into_iter().collect::<Vec<_>>(),total)
  }else{
   let(table,column,parent)=match input.scope_kind.as_str(){"project"=>("project_items","project_id","projects"),"topic"=>("item_topics","topic_id","topics"),"collection"=>("item_collections","collection_id","collections"),_=>return Err(RefractError::invalid("invalid compression scope"))};let scope=input.scope_id.as_deref().ok_or_else(||RefractError::invalid("scope ID is required"))?;
   let exists:i64=self.conn.query_row(&format!("SELECT COUNT(*) FROM {parent} WHERE id=?1"),params![scope],|r|r.get(0)).map_err(err)?;if exists==0{return Err(RefractError::invalid("compression scope not found"));}
   let where_sql=format!("FROM {table} m JOIN items i ON i.id=m.item_id WHERE m.{column}=?1 AND i.sense_decision!='ignore'");let total:i64=self.conn.query_row(&format!("SELECT COUNT(*) {where_sql}"),params![scope],|r|r.get(0)).map_err(err)?;
   let mut stmt=self.conn.prepare(&format!("SELECT i.id {where_sql} ORDER BY i.id LIMIT 30")).map_err(err)?;let rows=stmt.query_map(params![scope],|r|r.get::<_,String>(0)).map_err(err)?;let ids=rows.collect::<Result<Vec<_>,_>>().map_err(err)?;(ids,total as usize)
  };
  ids.sort();let hash=evidence_engine::sha256_hex(format!("{total}:{ids:?}").as_bytes());Ok((ids,hash,total>30))
 }
 pub fn compression_create(&self,input:&CompressionInput)->RefractResult<MemoryCompression>{self.compression_generate(input,None)}
 fn compression_generate(&self,input:&CompressionInput,existing:Option<&str>)->RefractResult<MemoryCompression>{
  let(ids,scope_hash,truncated)=self.compression_scope(input)?;if ids.is_empty(){return Err(RefractError::invalid("no available sources in this scope"));}
  let id=existing.map(str::to_string).unwrap_or_else(||uuid::Uuid::new_v4().to_string());let ts=now()?;
  let mut c=MemoryCompression{id:id.clone(),title:if input.title.trim().is_empty(){format!("{} — extractive overview",input.scope_kind)}else{input.title.trim().into()},scope_kind:input.scope_kind.clone(),scope_id:input.scope_id.clone(),selected_ids:input.item_ids.clone(),source_ids:ids.clone(),generated_ts:ts,excerpts:Vec::new(),concepts:Vec::new(),entities:Vec::new(),timeline:Vec::new(),disagreements:Vec::new(),questions:Vec::new(),source_hashes:BTreeMap::new(),scope_hash,stale_source_ids:Vec::new(),scope_changed:false,basis_hash:self.compression_basis(&ids)?,metadata_changed:false,kind:"derived_extractive_snapshot".into(),limitations:vec!["Optional, derived excerpts; not a replacement for originals or an exhaustive summary. No model interpretation or inferred beliefs are included.".into(),"At most 30 sources, one 600-character excerpt and two literal question excerpts per source, and 20 stored timestamps per source. Questions are recorded text, not proof that they remain unresolved.".into(),"Disagreements are existing contradicting-source links (suggestions/user assertions), not automatically established contradictions. Entities/topics retain their extraction uncertainty.".into()]};
  if truncated{c.limitations.push("Scope exceeds 30 sources: first 30 by ID only. Membership freshness checks use this window and total count, not every unrepresented source.".into());}
  let mut entities=BTreeMap::<String,BTreeSet<String>>::new();let mut concepts=BTreeMap::<String,BTreeSet<String>>::new();
  for source in &ids{
   let item=self.knowledge_item(source)?;c.source_hashes.insert(source.clone(),fingerprint(&item)?);let title=item.title.unwrap_or_else(||"Untitled source".into());
   if let Some(block)=item.blocks.iter().find(|b|!b.text.trim().is_empty()){c.excerpts.push(KnowledgeExcerpt{item_id:source.clone(),title:title.clone(),block_idx:block.idx,quote:block.text.chars().take(600).collect(),kind:"direct_quote".into()});}
   for block in &item.blocks{if c.questions.iter().filter(|q|q.item_id==*source).count()>=2{break;}for sentence in block.text.split_inclusive('?').filter(|s|s.ends_with('?')&&s.chars().count()<=600).take(2){c.questions.push(KnowledgeExcerpt{item_id:source.clone(),title:title.clone(),block_idx:block.idx,quote:sentence.into(),kind:"literal_question_not_inferred_gap".into()});if c.questions.iter().filter(|q|q.item_id==*source).count()>=2{break;}}}
   for(table,link,field)in[("topics","item_topics","topic_id"),("entities","item_entities","entity_id")]{let mut stmt=self.conn.prepare(&format!("SELECT n.name FROM {table} n JOIN {link} l ON l.{field}=n.id WHERE l.item_id=?1")).map_err(err)?;let names=stmt.query_map(params![source],|r|r.get::<_,String>(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;for name in names{if table=="topics"{concepts.entry(name).or_default().insert(source.clone());;}else{entities.entry(name).or_default().insert(source.clone());;}}}
   let mut stmt=self.conn.prepare("SELECT kind,ts,note FROM item_times WHERE item_id=?1 ORDER BY ts,id LIMIT 20").map_err(err)?;let times=stmt.query_map(params![source],|r|Ok(KnowledgeTime{item_id:source.clone(),kind:r.get(0)?,ts:r.get(1)?,note:r.get(2)?})).map_err(err)?;c.timeline.extend(times.collect::<Result<Vec<_>,_>>().map_err(err)?);
   if !c.timeline.iter().any(|t|t.item_id==*source&&t.kind=="capture"){c.timeline.push(KnowledgeTime{item_id:source.clone(),kind:"capture".into(),ts:item.import_ts,note:Some("Recorded source capture metadata".into())});}
  }
  c.concepts=concepts.into_iter().map(|(name,ids)|NamedCount{name,count:ids.len(),source_ids:ids.into_iter().collect()}).collect();c.entities=entities.into_iter().filter(|(_,ids)|ids.len()>1).map(|(name,ids)|NamedCount{name,count:ids.len(),source_ids:ids.into_iter().collect()}).collect();c.timeline.sort_by_key(|t|t.ts);
  for link in self.list_relationships(None,2000)?{if link.kind=="contradicting_source"&&ids.contains(&link.source_item_id)&&ids.contains(&link.target_item_id){c.disagreements.push(CompressionLink{source_item_id:link.source_item_id,target_item_id:link.target_item_id,basis:link.basis,confidence:link.confidence});}}
  let tx=self.conn.unchecked_transaction().map_err(err)?;
  tx.execute("INSERT INTO knowledge_compressions (id,title,scope_kind,scope_id,selection_json,payload_json,created_ts,generated_ts) VALUES (?1,?2,?3,?4,?5,?6,?7,?7) ON CONFLICT(id) DO UPDATE SET title=excluded.title,selection_json=excluded.selection_json,payload_json=excluded.payload_json,generated_ts=excluded.generated_ts",params![id,c.title,input.scope_kind,input.scope_id,serde_json::to_string(&input.item_ids).map_err(err)?,serde_json::to_string(&c).map_err(err)?,ts]).map_err(err)?;
  tx.execute("DELETE FROM compression_sources WHERE compression_id=?1",params![id]).map_err(err)?;
  for(source,hash)in &c.source_hashes{tx.execute("INSERT INTO compression_sources (compression_id,item_id,source_fingerprint) VALUES (?1,?2,?3)",params![id,source,hash]).map_err(err)?;}
  tx.commit().map_err(err)?;Ok(c)
 }
 pub fn compression_get(&self,id:&str)->RefractResult<MemoryCompression>{
  let json:String=self.conn.query_row("SELECT payload_json FROM knowledge_compressions WHERE id=?1",params![id],|r|r.get(0)).optional().map_err(err)?.ok_or_else(||RefractError::invalid("compression not found"))?;let mut c:MemoryCompression=serde_json::from_str(&json).map_err(err)?;c.stale_source_ids.clear();c.metadata_changed=self.compression_basis(&c.source_ids).map(|basis|basis!=c.basis_hash).unwrap_or(true);
  for source in &c.source_ids{let current=self.get_item(source)?;let matches=if let Some(i)=current{self.knowledge_eligible(source)?&&c.source_hashes.get(source)==Some(&fingerprint(&i)?)}else{false};if !matches{c.stale_source_ids.push(source.clone());}}
  let input=CompressionInput{title:c.title.clone(),scope_kind:c.scope_kind.clone(),scope_id:c.scope_id.clone(),item_ids:c.selected_ids.clone()};c.scope_changed=self.compression_scope(&input).map(|(_,hash,_)|hash!=c.scope_hash).unwrap_or(true);Ok(c)
 }
 pub fn compression_regenerate(&self,id:&str)->RefractResult<MemoryCompression>{let old=self.compression_get(id)?;self.compression_generate(&CompressionInput{title:old.title,scope_kind:old.scope_kind,scope_id:old.scope_id,item_ids:old.selected_ids},Some(id))}
 pub fn compression_discard(&self,id:&str)->RefractResult<()>{if self.conn.execute("DELETE FROM knowledge_compressions WHERE id=?1",params![id]).map_err(err)?==0{return Err(RefractError::invalid("compression not found"));}Ok(())}
 pub fn compression_list(&self)->RefractResult<Vec<CompressionSummary>>{let mut stmt=self.conn.prepare("SELECT id,title,generated_ts,scope_kind FROM knowledge_compressions ORDER BY generated_ts DESC,id LIMIT 100").map_err(err)?;let rows=stmt.query_map([],|r|Ok(CompressionSummary{id:r.get(0)?,title:r.get(1)?,generated_ts:r.get(2)?,scope_kind:r.get(3)?})).map_err(err)?;rows.collect::<Result<Vec<_>,_>>().map_err(err)}
}
