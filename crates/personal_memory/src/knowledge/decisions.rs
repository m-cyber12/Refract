use super::*;
use rusqlite::OptionalExtension;
use serde::{Deserialize,Serialize};
use std::collections::BTreeSet;
#[derive(Debug,Clone,Default,Deserialize,Serialize)]
#[serde(default,deny_unknown_fields)]
pub struct DecisionInput{
 pub id:Option<String>,pub title:String,pub context:String,pub options:Vec<String>,pub selected_option:String,pub reasoning:String,
 pub decision_ts:i64,pub expected_outcome:String,pub review_ts:Option<i64>,pub project_id:Option<String>,pub source_ids:Vec<String>,
}
#[derive(Debug,Clone,Deserialize,Serialize)]
pub struct DecisionRecord{pub id:String,pub title:String,pub context:String,pub options:Vec<String>,pub selected_option:String,pub reasoning:String,pub decision_ts:i64,pub expected_outcome:String,pub review_ts:Option<i64>,pub project_id:Option<String>,pub source_ids:Vec<String>,pub created_ts:i64,pub updated_ts:i64,pub archived:bool,pub kind:String}
#[derive(Debug,Default,Deserialize)]
#[serde(default,deny_unknown_fields)]
pub struct DecisionQuery{pub query:String,pub project_id:Option<String>,pub include_archived:bool}
impl Store{
 pub fn decision_get(&self,id:&str)->RefractResult<DecisionRecord>{
  let mut d=self.conn.query_row("SELECT id,title,context,options_json,selected_option,reasoning,decision_ts,expected_outcome,review_ts,project_id,created_ts,updated_ts,archived FROM knowledge_decisions WHERE id=?1",params![id],|r|Ok(DecisionRecord{id:r.get(0)?,title:r.get(1)?,context:r.get(2)?,options:Vec::new(),selected_option:r.get(4)?,reasoning:r.get(5)?,decision_ts:r.get(6)?,expected_outcome:r.get(7)?,review_ts:r.get(8)?,project_id:r.get(9)?,source_ids:Vec::new(),created_ts:r.get(10)?,updated_ts:r.get(11)?,archived:r.get(12)?,kind:"user_recorded_decision".into()})).optional().map_err(err)?.ok_or_else(||RefractError::invalid("decision not found"))?;
  let options:String=self.conn.query_row("SELECT options_json FROM knowledge_decisions WHERE id=?1",params![id],|r|r.get(0)).map_err(err)?;d.options=serde_json::from_str(&options).map_err(err)?;
  let mut stmt=self.conn.prepare("SELECT item_id FROM decision_sources WHERE decision_id=?1 ORDER BY item_id").map_err(err)?;d.source_ids=stmt.query_map(params![id],|r|r.get(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;Ok(d)
 }
 pub fn decision_save(&self,input:&DecisionInput)->RefractResult<DecisionRecord>{
  if input.title.trim().is_empty()||input.title.chars().count()>200||input.reasoning.trim().is_empty()||[&input.context,&input.reasoning,&input.expected_outcome].iter().any(|s|s.chars().count()>10000)||input.options.is_empty()||input.options.len()>20||input.options.iter().any(|s|s.trim().is_empty()||s.chars().count()>500)||!input.options.contains(&input.selected_option)||input.decision_ts<0||input.decision_ts>7258118400||input.review_ts.is_some_and(|t|t<input.decision_ts||t>7258118400)||input.source_ids.len()>30{return Err(RefractError::invalid("invalid decision: title, reasoning, valid date, options and an exact selected option are required; at most 30 sources"));}
  let sources=input.source_ids.iter().cloned().collect::<BTreeSet<_>>();for id in &sources{self.knowledge_item(id)?;}
  if let Some(p)=&input.project_id{if !self.list_projects()?.iter().any(|v|v.id==*p){return Err(RefractError::invalid("decision project not found"));}}
  let ts=now()?;let (id,created,archived)=if let Some(id)=&input.id{let old=self.decision_get(id)?;(id.clone(),old.created_ts,old.archived)}else{(uuid::Uuid::new_v4().to_string(),ts,false)};
  let tx=self.conn.unchecked_transaction().map_err(err)?;
  tx.execute("INSERT INTO knowledge_decisions (id,title,context,options_json,selected_option,reasoning,decision_ts,expected_outcome,review_ts,project_id,created_ts,updated_ts,archived) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13) ON CONFLICT(id) DO UPDATE SET title=excluded.title,context=excluded.context,options_json=excluded.options_json,selected_option=excluded.selected_option,reasoning=excluded.reasoning,decision_ts=excluded.decision_ts,expected_outcome=excluded.expected_outcome,review_ts=excluded.review_ts,project_id=excluded.project_id,updated_ts=excluded.updated_ts",params![id,input.title.trim(),input.context,serde_json::to_string(&input.options).map_err(err)?,input.selected_option,input.reasoning,input.decision_ts,input.expected_outcome,input.review_ts,input.project_id,created,ts,archived]).map_err(err)?;
  tx.execute("DELETE FROM decision_sources WHERE decision_id=?1",params![id]).map_err(err)?;for source in sources{tx.execute("INSERT INTO decision_sources (decision_id,item_id) VALUES (?1,?2)",params![id,source]).map_err(err)?;}
  tx.execute("DELETE FROM signal_editions",[]).map_err(err)?;let record=self.decision_get(&id)?;tx.execute("INSERT INTO decision_revisions (decision_id,recorded_ts,snapshot_json) VALUES (?1,?2,?3)",params![id,ts,serde_json::to_string(&record).map_err(err)?]).map_err(err)?;tx.commit().map_err(err)?;Ok(record)
 }
 pub fn decision_archive(&self,id:&str,archived:bool)->RefractResult<()>{self.decision_get(id)?;let tx=self.conn.unchecked_transaction().map_err(err)?;tx.execute("UPDATE knowledge_decisions SET archived=?1,updated_ts=?2 WHERE id=?3",params![archived,now()?,id]).map_err(err)?;tx.execute("DELETE FROM signal_editions",[]).map_err(err)?;let record=self.decision_get(id)?;tx.execute("INSERT INTO decision_revisions (decision_id,recorded_ts,snapshot_json) VALUES (?1,?2,?3)",params![id,now()?,serde_json::to_string(&record).map_err(err)?]).map_err(err)?;tx.commit().map_err(err)}
 pub fn decision_history(&self,id:&str)->RefractResult<Vec<DecisionRecord>>{self.decision_get(id)?;let mut stmt=self.conn.prepare("SELECT snapshot_json FROM decision_revisions WHERE decision_id=?1 ORDER BY id DESC LIMIT 100").map_err(err)?;let rows=stmt.query_map(params![id],|r|r.get::<_,String>(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;rows.into_iter().map(|s|serde_json::from_str(&s).map_err(err)).collect()}
 pub fn decision_search(&self,q:&DecisionQuery)->RefractResult<Vec<DecisionRecord>>{
  if q.query.chars().count()>2000{return Err(RefractError::invalid("decision query too long"));}
  let stop=["why","did","i","choose","chose","this","for","the","project","what","was","my","decision","about","a","an","and","to","use","how","which"];
  let terms=q.query.split(|c:char|!c.is_alphanumeric()).map(str::to_lowercase).filter(|t|t.len()>1&&!stop.contains(&t.as_str())).take(32).collect::<Vec<_>>();
  let mut stmt=self.conn.prepare("SELECT id FROM knowledge_decisions WHERE (?1 OR archived=0) AND (?2 IS NULL OR project_id=?2) ORDER BY decision_ts DESC,id LIMIT 1000").map_err(err)?;let ids=stmt.query_map(params![q.include_archived,q.project_id],|r|r.get::<_,String>(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;drop(stmt);
  let mut matches=Vec::new();for id in ids{let record=self.decision_get(&id)?;let project=if let Some(p)=&record.project_id{self.list_projects()?.into_iter().find(|v|v.id==*p).map(|p|p.name).unwrap_or_default()}else{String::new()};let text=format!("{} {} {} {} {} {} {}",record.title,record.context,record.options.join(" "),record.selected_option,record.reasoning,record.expected_outcome,project).to_lowercase();let score=terms.iter().filter(|t|text.contains(t.as_str())).count();if q.query.trim().is_empty()||score>0{matches.push((score,record));}}
  matches.sort_by(|a,b|b.0.cmp(&a.0).then(b.1.decision_ts.cmp(&a.1.decision_ts)).then(a.1.id.cmp(&b.1.id)));Ok(matches.into_iter().take(100).map(|(_,r)|r).collect())
 }
}
