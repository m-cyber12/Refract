//! Quiet, optional, local Daily Signal. Observations describe stored evidence,
//! never a person's beliefs or duties. Dates are candidates until user-confirmed.
use crate::Store;
use refract_core::{RefractError, RefractResult};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const SECTIONS: [&str; 9] = ["recent", "topics", "discoveries", "upcoming", "unfinished", "changes", "reading", "gaps", "suggestions"];
fn err(e: impl std::fmt::Display) -> RefractError { RefractError::storage(e.to_string()) }
fn now() -> RefractResult<i64> { Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_secs() as i64) }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SignalConfig {
    pub enabled: bool,
    pub context_enabled: bool,
    pub frequency: String,
    pub lookback_days: u32,
    pub upcoming_days: u32,
    pub max_per_section: usize,
    pub show_unconfirmed: bool,
    pub sections: Vec<String>,
}
impl Default for SignalConfig {
    fn default() -> Self { Self { enabled: true, context_enabled: true, frequency: "daily".into(), lookback_days: 7, upcoming_days: 30, max_per_section: 3, show_unconfirmed: true, sections: SECTIONS.iter().map(|s| s.to_string()).collect() } }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalEntry {
    pub key: String, pub section: String, pub title: String, pub explanation: String,
    pub item_ids: Vec<String>, pub project_id: Option<String>, pub block_idx: Option<u32>,
    pub ts: Option<i64>, pub status: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalEvent {
    pub id: String, pub item_id: String, pub block_idx: u32, pub title: String,
    pub event_ts: i64, pub category: String, pub confidence: f64, pub evidence: String,
    pub extracted_ts: i64, pub status: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalEdition {
    pub generated_ts: i64, pub next_refresh_ts: Option<i64>, pub enabled: bool,
    pub entries: Vec<SignalEntry>, pub events: Vec<SignalEvent>, pub quiet: bool,
    pub message: String, pub limitations: Vec<String>,
}
#[derive(Debug, Serialize)]
pub struct ContextResponse { pub enabled: bool, pub entries: Vec<SignalEntry>, pub events: Vec<SignalEvent>, pub message: String }
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContextRequest { pub item_id: Option<String>, pub project_id: Option<String> }
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadingUpdate { pub item_id: String, pub block_idx: Option<u32>, pub status: String }

fn entry(key: String, section: &str, title: String, explanation: String, ids: Vec<String>) -> SignalEntry {
    SignalEntry { key, section: section.into(), title, explanation, item_ids: ids, project_id: None, block_idx: None, ts: None, status: "observation".into() }
}

impl Store {
    pub fn signal_config(&self) -> RefractResult<SignalConfig> {
        let json: Option<String> = self.conn.query_row("SELECT config_json FROM signal_settings WHERE id=1", [], |r| r.get(0)).optional().map_err(err)?;
        json.map(|s| serde_json::from_str(&s).map_err(err)).unwrap_or_else(|| Ok(SignalConfig::default()))
    }
    pub fn signal_set_config(&self, c: &SignalConfig) -> RefractResult<()> {
        if !["daily", "weekly", "manual"].contains(&c.frequency.as_str()) || !(1..=90).contains(&c.lookback_days) || !(1..=365).contains(&c.upcoming_days) || !(1..=5).contains(&c.max_per_section) || c.sections.iter().any(|s| !SECTIONS.contains(&s.as_str())) {
            return Err(RefractError::invalid("invalid Signal frequency, date window, section or section limit"));
        }
        self.conn.execute("INSERT INTO signal_settings (id,config_json) VALUES (1,?1) ON CONFLICT(id) DO UPDATE SET config_json=excluded.config_json", params![serde_json::to_string(c).map_err(err)?]).map_err(err)?;
        self.invalidate_signal()
    }
    fn invalidate_signal(&self) -> RefractResult<()> { self.conn.execute("DELETE FROM signal_editions", []).map_err(err)?; Ok(()) }
    fn eligible(&self, id: &str) -> RefractResult<bool> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM items WHERE id=?1 AND sense_decision!='ignore'", params![id], |r| r.get::<_,i64>(0)).map_err(err)? > 0)
    }
    pub fn signal_dismiss(&self, key: &str) -> RefractResult<()> {
        if key.is_empty() || key.len() > 512 { return Err(RefractError::invalid("invalid entry key")); }
        self.conn.execute("INSERT OR IGNORE INTO signal_dismissals (entry_key,dismissed_ts) VALUES (?1,?2)", params![key,now()?]).map_err(err)?;
        self.invalidate_signal()
    }
    pub fn signal_reset_dismissals(&self) -> RefractResult<()> {
        self.conn.execute("DELETE FROM signal_dismissals", []).map_err(err)?; self.invalidate_signal()
    }
    pub fn signal_reading_update(&self, update: &ReadingUpdate) -> RefractResult<()> {
        let item = self.get_item(&update.item_id)?.ok_or_else(|| RefractError::invalid("reading source not found"))?;
        if !["started", "completed"].contains(&update.status.as_str()) || update.block_idx.is_some_and(|idx| !item.blocks.iter().any(|b| b.idx == idx)) {
            return Err(RefractError::invalid("invalid reading status or block"));
        }
        self.conn.execute("INSERT INTO reading_places (item_id,block_idx,status,updated_ts) VALUES (?1,?2,?3,?4) ON CONFLICT(item_id) DO UPDATE SET block_idx=excluded.block_idx,status=excluded.status,updated_ts=excluded.updated_ts", params![update.item_id,update.block_idx,update.status,now()?]).map_err(err)?;
        self.invalidate_signal()
    }
    pub fn signal_clear_reading(&self) -> RefractResult<()> {
        self.conn.execute("DELETE FROM reading_places", []).map_err(err)?; self.invalidate_signal()
    }
    /// ISO dates only, taken from user-imported blocks. Keyword category and
    /// exact source window are retained; dates are never implicitly confirmed.
    pub fn signal_extract_events(&self, item_id: &str) -> RefractResult<usize> {
        let item = self.get_item(item_id)?.ok_or_else(|| RefractError::invalid("event source not found"))?;
        let mut added = 0;
        for block in &item.blocks {
            for (offset, bytes) in block.text.as_bytes().windows(10).enumerate() {
                if !bytes.iter().enumerate().all(|(i,b)| if i==4 || i==7 { *b==b'-' } else { b.is_ascii_digit() }) { continue; }
                let date = std::str::from_utf8(bytes).map_err(err)?;
                let Some(ts) = crate::smart_memory::parse_date(date) else { continue; };
                let at = block.text[..offset].chars().count();
                let evidence: String = block.text.chars().skip(at.saturating_sub(100)).take(260).collect();
                let text = evidence.to_lowercase();
                let category = if text.contains("renew") { "renewal" } else if text.contains("trial") { "trial_end" }
                    else if text.contains("warranty") { "warranty_expiry" } else if text.contains("appointment") || text.contains("meeting") { "appointment" }
                    else if text.contains("deliver") { "delivery" } else if text.contains("deadline") || text.contains("due date") { "project_deadline" }
                    else if text.contains("expir") { "document_expiry" } else { "date_mention" };
                let confidence = if category == "date_mention" { 0.35 } else { 0.6 };
                added += self.conn.execute("INSERT OR IGNORE INTO signal_events (id,item_id,block_idx,title,event_ts,category,confidence,evidence,extracted_ts) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                    params![uuid::Uuid::new_v4().to_string(),item_id,block.idx,format!("{} candidate — {}",category.replace('_'," "),item.title.as_deref().unwrap_or("Untitled source")),ts,category,confidence,evidence,now()?]).map_err(err)?;
            }
        }
        Ok(added)
    }
    pub fn signal_review_event(&self, id: &str, status: &str) -> RefractResult<()> {
        if !["confirmed", "dismissed", "unconfirmed"].contains(&status) { return Err(RefractError::invalid("invalid event review status")); }
        if self.conn.execute("UPDATE signal_events SET status=?1 WHERE id=?2", params![status,id]).map_err(err)? == 0 { return Err(RefractError::invalid("event not found")); }
        self.invalidate_signal()
    }
    fn signal_events_between(&self, start: i64, end: i64, candidates: bool) -> RefractResult<Vec<SignalEvent>> {
        self.signal_events_filtered(start,end,candidates,None)
    }
    fn signal_events_filtered(&self, start: i64, end: i64, candidates: bool, source:Option<&str>) -> RefractResult<Vec<SignalEvent>> {
        let mut stmt = self.conn.prepare("SELECT e.id,e.item_id,e.block_idx,e.title,e.event_ts,e.category,e.confidence,e.evidence,e.extracted_ts,e.status FROM signal_events e JOIN items i ON i.id=e.item_id WHERE i.sense_decision!='ignore' AND e.status!='dismissed' AND (?3 OR e.status='confirmed') AND e.event_ts BETWEEN ?1 AND ?2 AND (?4 IS NULL OR e.item_id=?4) ORDER BY e.event_ts,e.id LIMIT 100").map_err(err)?;
        let rows = stmt.query_map(params![start,end,candidates,source], |r| Ok(SignalEvent { id:r.get(0)?,item_id:r.get(1)?,block_idx:r.get(2)?,title:r.get(3)?,event_ts:r.get(4)?,category:r.get(5)?,confidence:r.get(6)?,evidence:r.get(7)?,extracted_ts:r.get(8)?,status:r.get(9)? })).map_err(err)?;
        rows.collect::<Result<Vec<_>,_>>().map_err(err)
    }
    fn signal_source_ids(&self) -> RefractResult<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT id FROM items WHERE sense_decision!='ignore' ORDER BY id LIMIT 2000").map_err(err)?;
        let rows = stmt.query_map([], |r| r.get(0)).map_err(err)?; rows.collect::<Result<Vec<_>,_>>().map_err(err)
    }
    pub fn daily_signal(&self, refresh: bool) -> RefractResult<SignalEdition> { self.daily_signal_at(now()?, refresh) }
    fn daily_signal_at(&self, ts: i64, refresh: bool) -> RefractResult<SignalEdition> {
        let c = self.signal_config()?;
        let interval = match c.frequency.as_str() { "weekly"=>7*86400, "manual"=>0, _=>86400 };
        let mut edition = SignalEdition { generated_ts:ts,next_refresh_ts:if interval>0 { Some(ts+interval) } else { None },enabled:c.enabled,entries:Vec::new(),events:Vec::new(),quiet:true,message:String::new(),limitations:vec!["Local rule-based observations, not obligations. Missing information may exist outside REFRACT or outside the scanned scope.".into(),"At most 2000 non-ignored sources, 100 upcoming events and 1000 relationships are scanned. Refresh is local and on-demand; there are no background notifications.".into()] };
        if !c.enabled { edition.message="Daily Signal is off.".into(); return Ok(edition); }
        if !refresh {
            let cached: Option<String> = self.conn.query_row("SELECT edition_json FROM signal_editions WHERE id=1", [], |r| r.get(0)).optional().map_err(err)?;
            if let Some(json) = cached {
                let mut old: SignalEdition = serde_json::from_str(&json).map_err(err)?;
                if old.generated_ts <= ts && (interval==0 || ts < old.generated_ts+interval) {
                    self.sanitize_signal(&mut old)?; return Ok(old);
                }
            }
            if interval==0 { edition.message="Manual mode: generate an edition when you want one.".into(); return Ok(edition); }
        }
        let ids = self.signal_source_ids()?;
        if c.sections.iter().any(|s| s=="upcoming") { for id in &ids { self.signal_extract_events(id)?; } }
        let since = ts-c.lookback_days as i64*86400;
        let mut items = Vec::new();
        for id in &ids { if let Some(item) = self.get_item(id)? { items.push(item); } }
        items.sort_by(|a,b| b.import_ts.cmp(&a.import_ts).then(a.id.cmp(&b.id)));
        let mut entries = Vec::new();
        for item in &items {
            let title = item.title.clone().unwrap_or_else(|| "Untitled source".into());
            if item.import_ts >= since && item.import_ts <= ts {
                let mut e=entry(format!("recent:{}",item.id),"recent",title.clone(),"Captured in your configured lookback window; not ranked as objectively important.".into(),vec![item.id.clone()]); e.ts=Some(item.import_ts); entries.push(e);
            }
            let unclassified: i64 = self.conn.query_row("SELECT COUNT(*) FROM item_topics WHERE item_id=?1",params![item.id],|r|r.get(0)).map_err(err)?;
            let decision: String = self.conn.query_row("SELECT sense_decision FROM items WHERE id=?1",params![item.id],|r|r.get(0)).map_err(err)?;
            let complete: i64 = self.conn.query_row("SELECT COUNT(*) FROM reading_places WHERE item_id=?1 AND status='completed'",params![item.id],|r|r.get(0)).map_err(err)?;
            if complete==0 && (unclassified==0 || decision=="smart_suggest") {
                entries.push(entry(format!("unfinished:{}",item.id),"unfinished",title.clone(),"No topic classification or capture review is recorded. This is optional, not a task you must complete.".into(),vec![item.id.clone()]));
            }
            let place: Option<(Option<u32>,String,i64)> = self.conn.query_row("SELECT block_idx,status,updated_ts FROM reading_places WHERE item_id=?1",params![item.id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional().map_err(err)?;
            if let Some((block,status,updated))=place {
                if status=="started" { let mut e=entry(format!("reading:{}",item.id),"reading",title.clone(),"You explicitly saved this reading place; no reading percentage is inferred.".into(),vec![item.id.clone()]); e.block_idx=block; e.ts=Some(updated); e.status="user_recorded".into(); entries.push(e); }
            }
        }
        let allowed: BTreeSet<_> = ids.iter().cloned().collect();
        let item_by_id=items.iter().map(|i|(i.id.as_str(),i)).collect::<std::collections::HashMap<_,_>>();
        for topic in self.list_topics()? {
            let relevant=self.items_for_topic(&topic.id,2000)?.into_iter().filter(|i|allowed.contains(&i.id)&&i.import_ts>=since&&i.import_ts<=ts).collect::<Vec<_>>();
            if relevant.len()>=2 { entries.push(entry(format!("topic:{}",topic.id),"topics",topic.name.clone(),format!("{} sources captured for this topic in the lookback window. This describes your saved information, not a belief or external trend.",relevant.len()),relevant.into_iter().map(|i|i.id).collect())); }
        }
        for r in self.list_relationships(None,1000)? {
            if !allowed.contains(&r.source_item_id)||!allowed.contains(&r.target_item_id) { continue; }
            if r.created_ts>=since && r.created_ts<=ts {
                let changed=["earlier_version","follow_up","contradicting_source"].contains(&r.kind.as_str());
                let mut e=entry(format!("link:{}",r.id),if changed {"changes"}else{"discoveries"},r.kind.replace('_'," "),format!("Stored link: {}. Score {:.2}; a suggestion/user assertion, not proof that understanding changed.",r.basis,r.confidence),vec![r.source_item_id.clone(),r.target_item_id.clone()]); e.status="suggestion".into(); e.ts=Some(r.created_ts); entries.push(e);
            }
        }
        for p in self.list_projects()?.into_iter().take(100) {
            let refs=self.project_items(&p.id,2000)?.into_iter().filter_map(|i|item_by_id.get(i.id.as_str()).copied()).collect::<Vec<_>>();
            if refs.len()>=2 {
                let decision_found=refs.iter().any(|i|i.blocks.iter().any(|b|["decision:","decided:"].iter().any(|s|b.text.to_lowercase().contains(s))));
                if !decision_found {
                    let mut e=entry(format!("gap:project:{}",p.id),"gaps",format!("{}: no decision marker found",p.name),"Not found in scanned project source text using 'decision:' / 'decided:' markers. A decision may exist in another form or outside REFRACT; no action is required.".into(),refs.iter().map(|i|i.id.clone()).collect()); e.project_id=Some(p.id.clone()); e.status="not_found_in_refract".into(); entries.push(e);
                }
                let first=&refs[0]; let mut e=entry(format!("suggest:project:{}",p.id),"suggestions",first.title.clone().unwrap_or_else(||"Project reference".into()),format!("A reference in Project Space '{}'; offered for relevance, not because of inferred personal interests.",p.name),vec![first.id.clone()]); e.project_id=Some(p.id); e.status="suggestion".into(); entries.push(e);
            }
        }
        for item in &items {
            let text=item.blocks.iter().map(|b|b.text.to_lowercase()).collect::<Vec<_>>().join(" ");
            let (marker, label) = if text.contains("receipt") { ("warranty", "warranty reference") }
                else if text.contains("subscription") && text.contains("renew") { ("cancellation", "cancellation policy marker") } else { continue; };
            let mut scope=vec![item.id.clone()];
            for r in self.list_relationships(Some(&item.id),100)? { let other=if r.source_item_id==item.id {r.target_item_id}else{r.source_item_id}; if allowed.contains(&other) {scope.push(other);} }
            let mut found=text.contains(marker);
            for id in scope.iter().skip(1) { if let Some(other)=self.get_item(id)? { found |= other.blocks.iter().any(|b| b.text.to_lowercase().contains(marker)); } }
            if !found { let mut e=entry(format!("gap:{marker}:{}",item.id),"gaps",format!("No {label} found"),format!("Not found using the '{marker}' keyword in this source and up to 100 non-dismissed linked sources. It may exist elsewhere or use different wording. This is an optional observation, not confirmed absence."),scope); e.status="not_found_in_refract".into(); entries.push(e); }
        }
        entries.retain(|e|c.sections.contains(&e.section));
        entries.sort_by(|a,b|a.section.cmp(&b.section).then(b.ts.cmp(&a.ts)).then(a.key.cmp(&b.key)));
        let mut counts=std::collections::HashMap::<String,usize>::new();
        for e in entries {
            let dismissed: i64=self.conn.query_row("SELECT COUNT(*) FROM signal_dismissals WHERE entry_key=?1",params![e.key],|r|r.get(0)).map_err(err)?;
            if dismissed>0 {continue;}
            let count=counts.entry(e.section.clone()).or_default();
            if *count<c.max_per_section {edition.entries.push(e);*count+=1;}
        }
        if c.sections.iter().any(|s|s=="upcoming") { edition.events=self.signal_events_between(ts-ts.rem_euclid(86400),ts+c.upcoming_days as i64*86400,c.show_unconfirmed)?.into_iter().filter(|e|allowed.contains(&e.item_id)).take(c.max_per_section).collect(); }
        self.sanitize_signal(&mut edition)?;
        self.conn.execute("INSERT INTO signal_editions (id,generated_ts,edition_json) VALUES (1,?1,?2) ON CONFLICT(id) DO UPDATE SET generated_ts=excluded.generated_ts,edition_json=excluded.edition_json",params![ts,serde_json::to_string(&edition).map_err(err)?]).map_err(err)?;
        Ok(edition)
    }
    fn sanitize_signal(&self, edition: &mut SignalEdition) -> RefractResult<()> {
        let mut entries=Vec::new();
        for e in edition.entries.drain(..) { let mut valid=true; for id in &e.item_ids {valid &= self.eligible(id)?;} if valid {entries.push(e);} }
        edition.entries=entries;
        let mut events=Vec::new(); for e in edition.events.drain(..) {if self.eligible(&e.item_id)? {events.push(e);}} edition.events=events;
        edition.quiet=edition.entries.is_empty()&&edition.events.is_empty();
        edition.message=if edition.quiet {"A quiet edition. Nothing meaningful to surface from the enabled sections and scanned sources."}else{"A small, source-linked edition. Observations are optional; nothing requires action."}.into(); Ok(())
    }
    pub fn signal_context(&self, request: &ContextRequest) -> RefractResult<ContextResponse> {
        let c=self.signal_config()?;
        if !c.context_enabled {return Ok(ContextResponse {enabled:false,entries:Vec::new(),events:Vec::new(),message:"Context is off.".into()});}
        if request.item_id.is_some()==request.project_id.is_some() {return Err(RefractError::invalid("provide exactly one item or project context"));}
        let mut ids=BTreeSet::new(); let mut entries=Vec::new();
        if let Some(id)=&request.item_id {
            if !self.eligible(id)? {return Err(RefractError::invalid("context source is missing or ignored"));} ids.insert(id.clone());
            for r in self.list_relationships(Some(id),10)? {
                let other=if r.source_item_id==*id {r.target_item_id.clone()}else{r.source_item_id.clone()};
                if !self.eligible(&other)? {continue;} ids.insert(other.clone());
                let title=self.get_item(&other)?.and_then(|i|i.title).unwrap_or_else(||"Related source".into());
                let mut e=entry(format!("context:{}",r.id),"suggestions",title,format!("Stored {} link: {}. Score {:.2}, not verified fact.",r.kind,r.basis,r.confidence),vec![other]);e.status="suggestion".into();entries.push(e);
            }
        } else if let Some(id)=&request.project_id {
            if !self.list_projects()?.iter().any(|p|p.id==*id) {return Err(RefractError::invalid("project not found"));}
            for i in self.project_items(id,10)? {if self.eligible(&i.id)? {ids.insert(i.id.clone());entries.push(entry(format!("context:project:{}",i.id),"suggestions",i.title.unwrap_or_else(||"Project reference".into()),"Explicitly added project reference; no inferred decision or interest.".into(),vec![i.id]));}}
        }
        for id in &ids {
            for a in self.list_annotations(id)?.into_iter().take(3) {
                let mut e=entry(format!("annotation:{}",a.id),"notes","Saved annotation".into(),format!("Quote: {}\nNote: {}",a.quote,a.note.unwrap_or_default()),vec![id.clone()]);e.block_idx=a.block_idx;e.status="user_recorded".into();entries.push(e);
            }
            for p in self.list_projects()?.into_iter().take(100) {if self.project_items(&p.id,2000)?.iter().any(|i|i.id==*id) {let mut e=entry(format!("context:space:{}:{id}",p.id),"projects",p.name,"Explicit project membership.".into(),vec![id.clone()]);e.project_id=Some(p.id);entries.push(e);}}
            self.signal_extract_events(id)?;
        }
        for sub in self.list_subscriptions()?.into_iter().take(100) {
            if let Some(id)=sub.source_doc_id.filter(|id|ids.contains(id)) {
                let mut e=entry(format!("context:subscription:{}",sub.id),"subscriptions",sub.service,format!("Stored subscription record; status {}. This record and its dates are not independently verified.",sub.status.as_str()),vec![id]);e.ts=sub.renewal_date.or(sub.trial_end);e.status="stored_record".into();entries.push(e);
            }
        }
        let mut events=Vec::new();
        for id in &ids { events.extend(self.signal_events_filtered(i64::MIN,i64::MAX,c.show_unconfirmed,Some(id))?); }
        events.sort_by_key(|e|e.event_ts);events.truncate(10);
        entries.truncate(20);
        Ok(ContextResponse {enabled:true,entries,events,message:"Optional local context: stored links, project references, annotations and date candidates. No popup, external lookup or inferred beliefs.".into()})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use refract_core::{Block,BlockKind,ImportStatus,Item,SourceType};
    fn add(s:&mut Store,id:&str,text:&str,ts:i64) {
        s.insert_item(&Item {id:id.into(),title:Some(id.into()),source_url:None,source_type:SourceType::Text,import_ts:ts,content_hash:id.into(),author:None,language:None,extraction_confidence:0.9,status:ImportStatus::Ready,blocks:vec![Block{idx:0,kind:BlockKind::Paragraph,text:text.into()}]},text.as_bytes(),id).unwrap();
        s.conn.execute("UPDATE items SET sense_decision='auto_save' WHERE id=?1",params![id]).unwrap();
    }
    fn ts()->i64 {crate::smart_memory::parse_date("2027-01-01").unwrap()}
    #[test]
    fn empty_library_is_quiet_and_manual_mode_waits() {
        let s=Store::open_in_memory().unwrap();let e=s.daily_signal_at(ts(),false).unwrap();assert!(e.quiet);assert!(e.entries.is_empty());assert!(e.events.is_empty());
        let mut c=s.signal_config().unwrap();c.frequency="manual".into();s.signal_set_config(&c).unwrap();
        assert!(s.daily_signal_at(ts(),false).unwrap().message.contains("Manual mode"));
        assert!(s.daily_signal_at(ts(),true).unwrap().quiet);
    }
    #[test]
    fn cadence_sections_and_small_limits() {
        let mut s=Store::open_in_memory().unwrap();let mut c=s.signal_config().unwrap();c.frequency="weekly".into();c.sections=vec!["recent".into()];c.max_per_section=1;s.signal_set_config(&c).unwrap();
        add(&mut s,"a","Privacy GDPR information",ts());let first=s.daily_signal_at(ts(),false).unwrap();assert_eq!(first.entries.len(),1);
        add(&mut s,"b","More privacy information",ts()+10);
        let cached=s.daily_signal_at(ts()+20,false).unwrap();assert_eq!(cached.generated_ts,ts());assert_eq!(cached.entries[0].item_ids,vec!["a"]);
        let refreshed=s.daily_signal_at(ts()+20,true).unwrap();assert_eq!(refreshed.entries.len(),1);assert_eq!(refreshed.entries[0].item_ids,vec!["b"]);
        c.enabled=false;s.signal_set_config(&c).unwrap();assert!(!s.daily_signal_at(ts(),true).unwrap().enabled);
        c.frequency="hourly".into();assert!(s.signal_set_config(&c).is_err());
    }
    #[test]
    fn event_evidence_status_and_reextraction() {
        let mut s=Store::open_in_memory().unwrap();let text="Subscription renewal on 2027-01-10. Not guaranteed.";add(&mut s,"a",text,ts());
        let e=s.daily_signal_at(ts(),true).unwrap();let event=&e.events[0];assert_eq!(event.status,"unconfirmed");assert_eq!(event.category,"renewal");assert!(text.contains(&event.evidence));assert_eq!(event.block_idx,0);
        s.signal_review_event(&event.id,"confirmed").unwrap();s.signal_extract_events("a").unwrap();assert_eq!(s.daily_signal_at(ts(),true).unwrap().events[0].status,"confirmed");
        s.signal_review_event(&event.id,"dismissed").unwrap();s.signal_extract_events("a").unwrap();assert!(s.daily_signal_at(ts(),true).unwrap().events.is_empty());
        assert!(s.signal_review_event("missing","confirmed").is_err());assert!(s.signal_review_event(&event.id,"verified").is_err());
    }
    #[test]
    fn unconfirmed_filter_and_invalid_dates_unicode() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","中文🙂 trial ends 2027-01-10, not 2027-02-30",ts());
        assert_eq!(s.signal_events_between(ts(),ts()+60*86400,true).unwrap().len(),1);
        let mut c=s.signal_config().unwrap();c.show_unconfirmed=false;s.signal_set_config(&c).unwrap();assert!(s.daily_signal_at(ts(),true).unwrap().events.is_empty());
    }
    #[test]
    fn explicit_reading_places_and_completion() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy GDPR reference",ts());
        let before=s.get_item("a").unwrap();let mut u=ReadingUpdate{item_id:"a".into(),block_idx:Some(0),status:"started".into()};s.signal_reading_update(&u).unwrap();
        let e=s.daily_signal_at(ts(),true).unwrap();assert!(e.entries.iter().any(|e|e.section=="reading"&&e.block_idx==Some(0)));
        u.status="completed".into();s.signal_reading_update(&u).unwrap();assert!(s.daily_signal_at(ts(),true).unwrap().entries.iter().all(|e|e.section!="reading"));
        u.block_idx=Some(99);assert!(s.signal_reading_update(&u).is_err());assert_eq!(before,s.get_item("a").unwrap());s.signal_clear_reading().unwrap();
    }
    #[test]
    fn gaps_are_optional_not_found_observations_and_dismissible() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Receipt for a purchase",ts());
        let mut c=s.signal_config().unwrap();c.sections=vec!["gaps".into()];s.signal_set_config(&c).unwrap();
        let e=s.daily_signal_at(ts(),true).unwrap();assert_eq!(e.entries[0].status,"not_found_in_refract");assert!(e.entries[0].explanation.contains("may exist"));
        s.signal_dismiss(&e.entries[0].key).unwrap();assert!(s.daily_signal_at(ts(),true).unwrap().quiet);s.signal_reset_dismissals().unwrap();assert!(!s.daily_signal_at(ts(),true).unwrap().quiet);
        add(&mut s,"b","Warranty information for purchase",ts());s.add_relationship("a","b","supporting_reference","user linked warranty").unwrap();assert!(s.daily_signal_at(ts(),true).unwrap().quiet);
    }
    #[test]
    fn context_is_optional_source_backed_and_non_mutating() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy GDPR",ts());add(&mut s,"b","Privacy GDPR sources",ts());
        let before=s.get_item("a").unwrap();let r=ContextRequest{item_id:Some("a".into()),project_id:None};let ctx=s.signal_context(&r).unwrap();assert!(ctx.enabled);assert!(ctx.entries.iter().any(|e|e.item_ids==vec!["b"]));assert_eq!(before,s.get_item("a").unwrap());
        let mut c=s.signal_config().unwrap();c.context_enabled=false;s.signal_set_config(&c).unwrap();assert!(!s.signal_context(&r).unwrap().enabled);
        assert!(s.signal_context(&ContextRequest{item_id:None,project_id:None}).unwrap().entries.is_empty());
    }
    #[test]
    fn ignored_sources_disappear_even_from_cached_editions() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Renewal 2027-01-10",ts());assert!(!s.daily_signal_at(ts(),true).unwrap().quiet);
        s.conn.execute("UPDATE items SET sense_decision='ignore' WHERE id='a'",[]).unwrap();assert!(s.daily_signal_at(ts()+10,false).unwrap().quiet);
    }
    #[test]
    fn v6_upgrade_preserves_legacy_sources() {
        let conn=rusqlite::Connection::open_in_memory().unwrap();for sql in [crate::MIGRATION_0001,crate::MIGRATION_0002,crate::MIGRATION_0003,crate::MIGRATION_0004,crate::MIGRATION_0005,crate::MIGRATION_0006]{conn.execute_batch(sql).unwrap();}
        conn.execute("INSERT INTO items (id,source_type,import_ts,content_hash) VALUES ('legacy','text',100,'hash')",[]).unwrap();
        let s=Store{conn,blob_dir:std::env::temp_dir().join(uuid::Uuid::new_v4().to_string())};s.migrate().unwrap();s.migrate().unwrap();assert!(s.get_item("legacy").unwrap().is_some());assert!(s.daily_signal_at(ts(),true).is_ok());
    }
    #[test]
    fn explicit_project_decision_marker_suppresses_gap() {
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Privacy GDPR research",ts());add(&mut s,"b","Decision: use encryption for this project.",ts());
        let p=s.create_project("Research",None).unwrap();s.project_add_item(&p.id,"a").unwrap();s.project_add_item(&p.id,"b").unwrap();
        let edition=s.daily_signal_at(ts(),true).unwrap();assert!(edition.entries.iter().all(|e|e.key!=format!("gap:project:{}",p.id)));
    }

}
