//! User-initiated web acquisition sessions and consented preview staging.
use std::{collections::HashMap, sync::{Arc, Mutex, OnceLock}, time::{SystemTime, UNIX_EPOCH}};
use personal_memory::Store;
use refract_core::{RefractError, RefractResult};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;
use web_acquisition::{Approval, FetchSession, Progress};

struct Entry { session: FetchSession, consent_ts: i64 }
type Sessions = Mutex<HashMap<Uuid, Arc<Mutex<Entry>>>>;
fn sessions() -> &'static Sessions { static SESSIONS: OnceLock<Sessions> = OnceLock::new(); SESSIONS.get_or_init(|| Mutex::new(HashMap::new())) }
fn failure(message: &str) -> RefractError { RefractError::invalid(message) }
fn decode<T: serde::de::DeserializeOwned>(v: Value) -> RefractResult<T> { serde_json::from_value(v).map_err(|_| failure("Invalid web request")) }
fn id(value: &str) -> RefractResult<Uuid> { let id=Uuid::parse_str(value).map_err(|_|failure("Invalid web session ID"))?; if id.to_string()!=value {return Err(failure("Invalid web session ID"));} Ok(id) }
fn pending(entry: &Entry, id: Uuid) -> RefractResult<Value> {
    let p = entry.session.pending().ok_or_else(||failure("No request awaits approval"))?;
    Ok(json!({"status":"approval", "id":id.to_string(), "ticket":p.ticket.to_string(), "address":p.address, "http":p.requires_http_confirmation, "destination_change":p.requires_destination_confirmation}))
}
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct Start { url:String, stage_approved:bool }
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct Id { id:String }
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct SavedPreview { id:String, requested_url:String, final_url:String, sha256:String, consent_ts:i64 }
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct Advance { id:String, ticket:String, request:bool, http:bool, destination_change:bool }

pub fn dispatch(store: &mut Store, action: &str, payload: Value) -> RefractResult<Value> {
    match action {
        "start" => {
            let q:Start=decode(payload)?;
            if !q.stage_approved { return Err(failure("Explicit preview-copy approval is required")); }
            let session=FetchSession::new(&q.url).map_err(|_|failure("Invalid or forbidden web address"))?;
            let consent_ts=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_|failure("Device clock unavailable"))?.as_secs() as i64;
            let entry=Entry { session, consent_ts }; let key=Uuid::new_v4(); let response=pending(&entry,key)?;
            let mut guard=sessions().lock().map_err(|_|failure("Web sessions unavailable"))?;
            if guard.len()>=4 { return Err(failure("Too many web sessions; close one first")); }
            guard.insert(key,Arc::new(Mutex::new(entry))); Ok(response)
        }
        "advance" | "retry" | "stage" | "close" => {
            let (key, advance) = if action=="advance" { let q:Advance=decode(payload)?; (id(&q.id)?,Some(q)) } else { let q:Id=decode(payload)?; (id(&q.id)?,None) };
            let item=sessions().lock().map_err(|_|failure("Web sessions unavailable"))?.get(&key).cloned().ok_or_else(||failure("Web session not found; start again"))?;
            let mut entry=item.try_lock().map_err(|_|failure("Web session is busy"))?;
            match action {
                "close" => {
                    entry.session.cancel();
                    sessions().lock().map_err(|_|failure("Web sessions unavailable"))?.remove(&key);
                    Ok(json!({"status":"closed"}))
                }
                "retry" => { entry.session.retry().map_err(|_|failure("Web session cannot be retried"))?; pending(&entry,key) }
                "advance" => {
                    let q=advance.unwrap(); let ticket=id(&q.ticket)?;
                    let outcome=entry.session.advance(ticket,Approval { request:q.request,http:q.http,destination_change:q.destination_change });
                    match outcome {
                        Ok(Progress::AwaitingApproval) => pending(&entry,key),
                        Ok(Progress::Complete) => stage(store, key, &mut entry),
                        Err(web_acquisition::SessionError::ApprovalRequired | web_acquisition::SessionError::StaleApproval) => Err(failure("Approval missing or stale; review the destination again")),
                        Err(_) => Ok(json!({"status":"failed", "id":key.to_string(), "message":"Fetch failed or was blocked. No preview was saved. You can explicitly retry or close this session."})),
                    }
                }
                "stage" => stage(store,key,&mut entry),
                _ => unreachable!(),
            }
        }
        "list" => Ok(json!({"previews":store.list_web_previews()?})),
        "get" => { let q:Id=decode(payload)?; serde_json::to_value(store.get_web_preview(&q.id)?).map_err(|_|failure("Preview unavailable")) },
        "delete_saved" => { let q:SavedPreview=decode(payload)?; let deleted=store.delete_saved_web_preview(&q.id,&q.requested_url,&q.final_url,&q.sha256,q.consent_ts)?; Ok(json!({"deleted":deleted})) },
        "delete" => { let q:Id=decode(payload)?; store.delete_web_preview(&q.id)?; Ok(json!({"deleted":true})) },
        _ => Err(failure("Unsupported web action")),
    }
}
fn stage(store: &mut Store, key: Uuid, entry: &mut Entry) -> RefractResult<Value> {
    let source=entry.session.result().ok_or_else(||failure("No fetched preview is ready to stage"))?;
    // Leave bytes in session on failure, so an explicit stage retry can recover.
    store.stage_web_preview(&key.to_string(),&source.requested_address,&source.final_address,&source.bytes,entry.consent_ts,true)?;
    entry.session.cancel();
    sessions().lock().map_err(|_|failure("Web sessions unavailable"))?.remove(&key);
    Ok(json!({"status":"staged","id":key.to_string()}))
}

#[cfg(test)] mod tests {
 use super::*;
 #[test] fn consent_sessions_and_staged_bytes_are_distinct_from_library_save() {
  let dir=std::env::temp_dir().join(format!("refract-web-{}",Uuid::new_v4())); std::fs::create_dir_all(&dir).unwrap(); let db=dir.join("db"); let mut store=Store::open(&db).unwrap();
  assert!(dispatch(&mut store,"start",json!({"url":"https://public.com/","stage_approved":false})).is_err());
  assert!(dispatch(&mut store,"start",json!({"url":"http://127.0.0.1/","stage_approved":true})).is_err());
  let p=dispatch(&mut store,"start",json!({"url":"http://public.com/","stage_approved":true})).unwrap();
  assert_eq!(p["http"],true);
  assert!(dispatch(&mut store,"advance",json!({"id":p["id"],"ticket":p["ticket"],"request":true,"http":false,"destination_change":false})).is_err());
  assert!(store.list_web_previews().unwrap().is_empty());
  dispatch(&mut store,"close",json!({"id":p["id"]})).unwrap();
  let id=Uuid::new_v4().to_string(); let html="\u{feff}<p>fixture</p>";
  store.stage_web_preview(&id,"https://public.com/a","https://public.com/b",html.as_bytes(),123,true).unwrap();
  let body=dispatch(&mut store,"get",json!({"id":id})).unwrap(); assert_eq!(body["html"],html);
  assert_eq!(dispatch(&mut store,"list",json!({})).unwrap()["previews"].as_array().unwrap().len(),1);
  assert_eq!(dispatch(&mut store,"delete_saved",json!({"id":id,"requested_url":"https://public.com/a","final_url":"https://public.com/b","sha256":content_compiler::sha256_hex(b"changed"),"consent_ts":123})).unwrap()["deleted"],false);
  assert_eq!(dispatch(&mut store,"delete_saved",json!({"id":id,"requested_url":"https://public.com/a","final_url":"https://public.com/b","sha256":body["sha256"],"consent_ts":123})).unwrap()["deleted"],true);
  assert!(store.list_web_previews().unwrap().is_empty()); drop(store); std::fs::remove_dir_all(dir).unwrap();
 }
}
