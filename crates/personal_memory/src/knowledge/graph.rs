use super::*;
use rusqlite::OptionalExtension;
use serde::{Deserialize,Serialize};
use std::collections::{BTreeSet,BTreeMap,VecDeque};
const KINDS:[&str;7]=["document","topic","project","entity","note","event","decision"];
#[derive(Debug,Default,Deserialize)]#[serde(default,deny_unknown_fields)]
pub struct GraphRequest{pub kind:String,pub id:String,pub category:Option<String>,pub after:Option<i64>,pub before:Option<i64>,pub offset:u32,pub limit:Option<u32>}
#[derive(Debug,Clone,Serialize)]pub struct GraphNode{pub key:String,pub kind:String,pub id:String,pub label:String,pub ts:i64,pub source_item_id:Option<String>,pub block_idx:Option<u32>,pub detail:String}
#[derive(Debug,Clone,Serialize)]pub struct GraphEdge{pub source_key:String,pub target_key:String,pub kind:String,pub basis:String,pub confidence:f64,pub relationship_id:Option<String>}
#[derive(Debug,Serialize)]pub struct GraphPage{pub focus:GraphNode,pub nodes:Vec<GraphNode>,pub edges:Vec<GraphEdge>,pub next_offset:Option<u32>,pub explanation:String}
fn node(r:&rusqlite::Row)->rusqlite::Result<GraphNode>{let kind:String=r.get(0)?;let id:String=r.get(1)?;Ok(GraphNode{key:format!("{kind}:{id}"),kind,id,label:r.get(2)?,ts:r.get(3)?,source_item_id:r.get(4)?,block_idx:r.get(5)?,detail:r.get(6)?})}
#[derive(Debug,Deserialize)]#[serde(deny_unknown_fields)]pub struct PathRequest{pub from_id:String,pub to_id:String,pub max_depth:Option<usize>}
#[derive(Debug,Clone,Serialize)]pub struct PathStep{pub from_id:String,pub to_id:String,pub original_source_id:String,pub original_target_id:String,pub relationship_id:String,pub kind:String,pub basis:String,pub confidence:f64}
#[derive(Debug,Serialize)]pub struct KnowledgePath{pub found:bool,pub steps:Vec<PathStep>,pub limited:bool,pub explanation:String}
impl Store{
 pub fn knowledge_graph(&self,q:&GraphRequest)->RefractResult<GraphPage>{
  let kind=if q.kind.is_empty(){"library"}else{q.kind.as_str()};if kind!="library"&&!KINDS.contains(&kind)||q.category.as_ref().is_some_and(|c|!KINDS.contains(&c.as_str()))||q.offset>100000||q.after.zip(q.before).is_some_and(|(a,b)|a>b){return Err(RefractError::invalid("invalid graph kind, category, date range or offset"));}
  let focus=if kind=="library"{GraphNode{key:"library:".into(),kind:"library".into(),id:String::new(),label:"Stored knowledge".into(),ts:0,source_item_id:None,block_idx:None,detail:"Navigation index, not a semantic relationship".into()}}else{self.conn.query_row("SELECT kind,id,label,ts,source_item_id,block_idx,detail FROM knowledge_nodes WHERE kind=?1 AND id=?2",params![kind,q.id],node).optional().map_err(err)?.ok_or_else(||RefractError::invalid("graph node not found, archived, dismissed or ignored"))?};
  let limit=q.limit.unwrap_or(20).clamp(1,40);let mut nodes=if kind=="library"{
   let mut stmt=self.conn.prepare("SELECT kind,id,label,ts,source_item_id,block_idx,detail FROM knowledge_nodes WHERE (?1 IS NULL OR kind=?1) AND (?2 IS NULL OR ts>=?2) AND (?3 IS NULL OR ts<=?3) ORDER BY ts DESC,kind,id LIMIT ?4 OFFSET ?5").map_err(err)?;
   let rows=stmt.query_map(params![q.category,q.after,q.before,limit+1,q.offset],node).map_err(err)?;rows.collect::<Result<Vec<_>,_>>().map_err(err)?
  }else{
   let mut stmt=self.conn.prepare("SELECT DISTINCT n.kind,n.id,n.label,n.ts,n.source_item_id,n.block_idx,n.detail FROM knowledge_nodes n JOIN knowledge_edges e ON (e.source_key=?1 AND n.kind||':'||n.id=e.target_key) OR (e.target_key=?1 AND n.kind||':'||n.id=e.source_key) WHERE (?2 IS NULL OR n.kind=?2) AND (?3 IS NULL OR n.ts>=?3) AND (?4 IS NULL OR n.ts<=?4) AND n.kind||':'||n.id!=?1 ORDER BY n.ts DESC,n.kind,n.id LIMIT ?5 OFFSET ?6").map_err(err)?;
   let rows=stmt.query_map(params![focus.key,q.category,q.after,q.before,limit+1,q.offset],node).map_err(err)?;rows.collect::<Result<Vec<_>,_>>().map_err(err)?
  };
  let more=nodes.len()>limit as usize;nodes.truncate(limit as usize);let keys=nodes.iter().map(|n|n.key.as_str()).collect::<BTreeSet<_>>();
  let edges=if kind=="library"{nodes.iter().map(|n|GraphEdge{source_key:focus.key.clone(),target_key:n.key.clone(),kind:"navigation_index".into(),basis:"Listed in this filtered navigation window; not evidence of conceptual relatedness".into(),confidence:1.0,relationship_id:None}).collect()}else{
   let mut stmt=self.conn.prepare("SELECT source_key,target_key,kind,basis,confidence,relationship_id FROM knowledge_edges WHERE source_key=?1 OR target_key=?1 LIMIT 2000").map_err(err)?;
   let rows=stmt.query_map(params![focus.key],|r|Ok(GraphEdge{source_key:r.get(0)?,target_key:r.get(1)?,kind:r.get(2)?,basis:r.get(3)?,confidence:r.get(4)?,relationship_id:r.get(5)?})).map_err(err)?;
   rows.collect::<Result<Vec<_>,_>>().map_err(err)?.into_iter().filter(|e|keys.contains(e.source_key.as_str())||keys.contains(e.target_key.as_str())).collect()
  };
  Ok(GraphPage{focus,nodes,edges,next_offset:if more{Some(q.offset+limit)}else{None},explanation:"One-hop navigation window. Expand nodes or page through neighbors; type/date filters apply to neighbor nodes, not the focus. Document dates are capture times; events use event dates and decisions their user-recorded date. Membership edges are associations, and suggested links are not factual proof. Up to 2000 focus edges are displayed.".into()})
 }
 pub fn knowledge_path(&self,q:&PathRequest)->RefractResult<KnowledgePath>{
  let max=q.max_depth.unwrap_or(3);if max==0||max>4||q.from_id==q.to_id||!self.knowledge_eligible(&q.from_id)?||!self.knowledge_eligible(&q.to_id)?{return Err(RefractError::invalid("choose two distinct available sources and a path depth of 1–4"));}
  let mut links=self.list_relationships(None,2001)?;let mut limited=links.len()>2000;links.truncate(2000);let mut adjacency=BTreeMap::<String,Vec<PathStep>>::new();
  for r in links{if !self.knowledge_eligible(&r.source_item_id)?||!self.knowledge_eligible(&r.target_item_id)?{continue;}for(from,to)in[(&r.source_item_id,&r.target_item_id),(&r.target_item_id,&r.source_item_id)]{adjacency.entry(from.clone()).or_default().push(PathStep{from_id:from.clone(),to_id:to.clone(),original_source_id:r.source_item_id.clone(),original_target_id:r.target_item_id.clone(),relationship_id:r.id.clone(),kind:r.kind.clone(),basis:r.basis.clone(),confidence:r.confidence});}}
  let mut queue=VecDeque::from([(q.from_id.clone(),Vec::<PathStep>::new())]);let mut seen=BTreeSet::from([q.from_id.clone()]);let mut found=None;
  'search:while let Some((current,path))=queue.pop_front(){if path.len()>=max{continue;}for step in adjacency.get(&current).into_iter().flatten(){if seen.contains(&step.to_id){continue;}if seen.len()>=200{limited=true;break 'search;}let mut next=path.clone();next.push(step.clone());if step.to_id==q.to_id{found=Some(next);break 'search;}seen.insert(step.to_id.clone());queue.push_back((step.to_id.clone(),next));}}
  Ok(KnowledgePath{found:found.is_some(),steps:found.unwrap_or_default(),limited,explanation:"Bounded, undirected traversal of non-dismissed stored document links: at most 2000 links, 200 visited sources and 4 hops. A chain of suggestions does not establish factual entailment. No path found is not proof that no connection exists.".into()})
 }
}
