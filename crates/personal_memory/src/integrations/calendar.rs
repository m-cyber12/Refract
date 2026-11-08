use super::*;
use chrono::{DateTime, Duration, Utc};
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CalendarSelection { pub event_id: String, pub title: String }
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct CalendarExportInput { pub events: Vec<CalendarSelection>, pub include_evidence: bool, pub prepared_ts: Option<i64>, pub review_hash: String }
#[derive(Debug, Serialize)]
pub struct CalendarCandidate { pub id:String, pub source_id:String, pub block_idx:u32, pub local_title:String, pub date:String, pub evidence:String, pub source_current:bool }
#[derive(Debug, Serialize)]
pub struct CalendarCandidates { pub events:Vec<CalendarCandidate>, pub limited:bool }
#[derive(Debug, Serialize)]
pub struct CalendarExportPreview { pub ics:String, pub prepared_ts:i64, pub review_hash:String, pub statement:String }
const STATEMENT:&str="User-confirmed date mention from REFRACT, not a verified appointment or obligation. Date only: no time/timezone was established. No reminder, financial action or automatic cancellation is scheduled. Export preparation is not calendar delivery/import.";
fn escape(s:&str)->RefractResult<String>{if s.chars().any(|c|c.is_control()&&!['\r','\n','\t'].contains(&c)){return Err(invalid("Calendar text contains unsupported control characters"));}Ok(s.replace('\\',"\\\\").replace("\r\n","\n").replace('\r',"\n").replace('\n',"\\n").replace(';',"\\;").replace(',',"\\,"))}
fn fold(line:&str)->String{let mut out=String::new();let mut len=0;for c in line.chars(){if len+c.len_utf8()>75{out.push_str("\r\n ");len=1;}out.push(c);len+=c.len_utf8();}out.push_str("\r\n");out}
const SELECT:&str="SELECT e.id,e.item_id,e.block_idx,e.title,e.event_ts,e.evidence,(e.evidence!='' AND instr(b.text,e.evidence)>0 AND instr(e.evidence,strftime('%Y-%m-%d',e.event_ts,'unixepoch'))>0) FROM signal_events e JOIN items i ON i.id=e.item_id JOIN blocks b ON b.item_id=e.item_id AND b.idx=e.block_idx WHERE e.status='confirmed' AND i.sense_decision!='ignore' AND e.event_ts BETWEEN 0 AND 7258032000 AND e.event_ts%86400=0";
fn row(r:&rusqlite::Row<'_>)->rusqlite::Result<CalendarCandidate>{let ts:i64=r.get(4)?;Ok(CalendarCandidate{id:r.get(0)?,source_id:r.get(1)?,block_idx:r.get(2)?,local_title:r.get(3)?,date:DateTime::<Utc>::from_timestamp(ts,0).map(|d|d.format("%Y-%m-%d").to_string()).unwrap_or_default(),evidence:r.get(5)?,source_current:r.get(6)?})}
impl Store {
 pub fn integration_calendar_candidates(&self)->RefractResult<CalendarCandidates>{
  self.integration_require("calendar_export","confirmed_dates")?;
  let mut stmt=self.conn.prepare(&format!("{SELECT} ORDER BY e.event_ts DESC,e.id LIMIT 101")).map_err(err)?;
  let mut events=stmt.query_map([],row).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;let limited=events.len()>100;events.truncate(100);Ok(CalendarCandidates{events,limited})
 }
 pub fn integration_calendar_preview(&self,input:&CalendarExportInput)->RefractResult<CalendarExportPreview>{
  let policy=self.integration_require("calendar_export","confirmed_dates")?;
  if input.events.is_empty()||input.events.len()>20||input.events.iter().map(|e|&e.event_id).collect::<BTreeSet<_>>().len()!=input.events.len(){return Err(invalid("Explicitly select 1–20 distinct confirmed dates"));}
  let current=now()?;let ts=input.prepared_ts.unwrap_or(current);
  if ts<0||ts.abs_diff(current)>86400{return Err(invalid("Prepare a fresh calendar preview; preparation time must be within one day of the device clock"));}
  let dtstamp=DateTime::<Utc>::from_timestamp(ts,0).ok_or_else(||invalid("Invalid device time"))?.format("%Y%m%dT%H%M%SZ").to_string();
  let mut lines=vec!["BEGIN:VCALENDAR".into(),"VERSION:2.0".into(),"PRODID:-//REFRACT//Reviewed dates 1//EN".into(),"CALSCALE:GREGORIAN".into()];
  for selected in &input.events{
   if selected.title.trim().is_empty()||selected.title.chars().count()>120||selected.title.chars().any(char::is_control){return Err(invalid("Choose a short, single-line export title; private source titles are never copied by default"));}
   let e=self.conn.query_row(&format!("{SELECT} AND e.id=?1"),params![selected.event_id],row).optional().map_err(err)?.ok_or_else(||invalid("Selected date is missing, unconfirmed, dismissed or its source is ignored/unavailable"))?;
   if !e.source_current{return Err(invalid("Selected date evidence changed or disappeared; review the source/date again"));}
   let date=chrono::NaiveDate::parse_from_str(&e.date,"%Y-%m-%d").map_err(err)?;
   let end=date.checked_add_signed(Duration::days(1)).ok_or_else(||invalid("Date overflow"))?;
   let description=if input.include_evidence{format!("{STATEMENT}\nSelected source excerpt: {}\nPrivate local reference: item {}, block {} (requires the matching local library).",e.evidence,e.source_id,e.block_idx)}else{STATEMENT.into()};
   let uid=evidence_engine::sha256_hex(format!("refract-date-v1:{}",e.id).as_bytes());
   lines.extend(["BEGIN:VEVENT".into(),format!("UID:{uid}@refract.invalid"),format!("DTSTAMP:{dtstamp}"),format!("DTSTART;VALUE=DATE:{}",date.format("%Y%m%d")),format!("DTEND;VALUE=DATE:{}",end.format("%Y%m%d")),format!("SUMMARY:{}",escape(&selected.title)?),format!("DESCRIPTION:{}",escape(&description)?),"TRANSP:TRANSPARENT".into(),"END:VEVENT".into()]);
  }
  lines.push("END:VCALENDAR".into());let ics=lines.iter().map(|l|fold(l)).collect::<String>();
  let hash=evidence_engine::sha256_hex(json(&("calendar-export-v1",policy.revision,&input.events,input.include_evidence,ts,&ics))?.as_bytes());
  Ok(CalendarExportPreview{ics,prepared_ts:ts,review_hash:hash,statement:STATEMENT.into()})
 }
 pub fn integration_calendar_export(&self,input:&CalendarExportInput)->RefractResult<CalendarExportPreview>{
  if input.prepared_ts.is_none(){return Err(invalid("A reviewed preparation timestamp is required"));}let preview=self.integration_calendar_preview(input)?;
  if input.review_hash!=preview.review_hash{return Err(invalid("Calendar selection, source, title or local consent changed. Review again before saving"));}Ok(preview)
 }
}
