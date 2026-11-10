//! Platform bridge: the versioned C ABI consumed by Flutter via `dart:ffi`.
//!
//! Rules (from the architecture docs):
//! - Never panic across the boundary; every call returns a JSON envelope
//!   `{"ok": true, "payload": ...}` or `{"ok": false, "error": {...}}`.
//! - All returned strings are owned by Rust and must be freed with
//!   `refract_free_string`.
//! - `refract_open` returns an opaque handle; `refract_close` releases it.

mod web_bridge;

use ai_runtime::{AiOutput, AiRuntime};
use content_compiler::{compile, ContentInput};
use personal_memory::Store;
use refract_core::{
    ABI_VERSION, Annotation, Collection, EvidenceClaim, EvidenceRecord, FfiResponse, Item,
    RefractError, RefractResult, SourceType, Subscription, SubscriptionStatus, Tag,
};
use serde::Serialize;
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::Mutex;

struct BridgeState {
    store: Store,
}

static LAST_ERROR: Mutex<Option<CString>> = Mutex::new(None);

fn set_last_error(msg: &str) {
    if let Ok(mut guard) = LAST_ERROR.lock() {
        *guard = CString::new(msg).ok();
    }
}

fn to_json<T: Serialize>(r: RefractResult<T>) -> CString {
    let resp: FfiResponse<T> = match r {
        Ok(payload) => FfiResponse { ok: true, payload: Some(payload), error: None },
        Err(e) => {
            set_last_error(&e.to_string());
            FfiResponse { ok: false, payload: None, error: Some(e) }
        }
    };
    CString::new(serde_json::to_string(&resp).unwrap_or_else(|_| {
        r#"{"ok":false,"error":{"Internal":"serialization failure"}}"#.to_string()
    }))
    .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"c-string"}"#).unwrap())
}

fn c_str<'a>(ptr: *const c_char, what: &str) -> RefractResult<&'a str> {
    if ptr.is_null() {
        return Err(RefractError::invalid(format!("null pointer: {what}")));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|_| RefractError::invalid(format!("invalid utf-8: {what}")))
}

unsafe fn state<'a>(handle: *mut c_void) -> RefractResult<&'a mut BridgeState> {
    if handle.is_null() {
        return Err(RefractError::invalid("null handle"));
    }
    Ok(unsafe { &mut *(handle as *mut BridgeState) })
}

fn do_import(
    store: &mut Store,
    source_type: SourceType,
    raw: &[u8],
    source_url: Option<String>,
) -> RefractResult<Item> {
    let limit = if source_type == SourceType::Pdf { 10 * 1024 * 1024 } else { 2 * 1024 * 1024 };
    if raw.len() > limit { return Err(RefractError::invalid("Capture input exceeds its size limit")); }
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| RefractError::internal(e.to_string()))?
        .as_secs() as i64;
    let input = ContentInput { source_type, source_url, raw: raw.to_vec() };
    let compiled = compile(&input, ts)?;
    store.insert_item(&compiled.item, &compiled.original_bytes, &compiled.original_hash)?;
    Ok(compiled.item)
}

/// ABI version; Flutter checks this at startup.
#[no_mangle]
pub extern "C" fn refract_abi_version() -> u32 {
    ABI_VERSION
}

/// Open the local store. Returns an opaque handle or null on failure
/// (inspect `refract_last_error`).
#[no_mangle]
pub unsafe extern "C" fn refract_open(db_path: *const c_char) -> *mut c_void {
    let result = (|| -> RefractResult<Box<BridgeState>> {
        let path = c_str(db_path, "db_path")?;
        let store = Store::open(path)?;
        Ok(Box::new(BridgeState { store }))
    })();
    match result {
        Ok(b) => {
            set_last_error("");
            Box::into_raw(b) as *mut c_void
        }
        Err(e) => {
            set_last_error(&e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// Close a handle returned by `refract_open`.
#[no_mangle]
pub unsafe extern "C" fn refract_close(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle as *mut BridgeState)) };
    }
}

/// Last error message (valid until the next call). Never null.
#[no_mangle]
pub unsafe extern "C" fn refract_last_error() -> *const c_char {
    static EMPTY: &[u8] = b"\0";
    match LAST_ERROR.lock() {
        Ok(guard) => match guard.as_ref() {
            Some(s) => s.as_ptr(),
            None => EMPTY.as_ptr() as *const c_char,
        },
        Err(_) => EMPTY.as_ptr() as *const c_char,
    }
}

/// Free a string returned by any refract_* call.
#[no_mangle]
pub unsafe extern "C" fn refract_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

fn import_text(handle: *mut c_void, text: *const c_char, source_url: *const c_char) -> RefractResult<Item> {
    let state = unsafe { state(handle)? };
    let text = c_str(text, "text")?;
    let url = if source_url.is_null() {
        None
    } else {
        Some(c_str(source_url, "source_url")?.to_string())
    };
    do_import(&mut state.store, SourceType::SharedText, text.as_bytes(), url)
}

/// Import plain/shared text. Returns JSON envelope; caller frees the string.
#[no_mangle]
pub unsafe extern "C" fn refract_import_text(
    handle: *mut c_void,
    text: *const c_char,
    source_url: *const c_char,
) -> *mut c_char {
    to_json(import_text(handle, text, source_url)).into_raw()
}

/// Import an HTML document (also used for fetched URLs in later phases).
#[no_mangle]
pub unsafe extern "C" fn refract_import_html(
    handle: *mut c_void,
    html: *const c_char,
    source_url: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Item> {
        let state = unsafe { state(handle)? };
        let html = c_str(html, "html")?;
        let url = if source_url.is_null() {
            None
        } else {
            Some(c_str(source_url, "source_url")?.to_string())
        };
        do_import(&mut state.store, SourceType::Html, html.as_bytes(), url)
    })();
    to_json(result).into_raw()
}

/// Import a PDF document from raw bytes.
#[no_mangle]
pub unsafe extern "C" fn refract_import_pdf(
    handle: *mut c_void,
    bytes: *const u8,
    len: usize,
    source_url: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Item> {
        let state = unsafe { state(handle)? };
        if bytes.is_null() {
            return Err(RefractError::invalid("null pdf bytes"));
        }
        if len > 10 * 1024 * 1024 { return Err(RefractError::invalid("PDF exceeds 10 MiB")); }
        let raw = unsafe { std::slice::from_raw_parts(bytes, len) };
        let url = if source_url.is_null() {
            None
        } else {
            Some(c_str(source_url, "source_url")?.to_string())
        };
        do_import(&mut state.store, SourceType::Pdf, raw, url)
    })();
    to_json(result).into_raw()
}

/// List library items, newest first. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_items(
    handle: *mut c_void,
    limit: u32,
    offset: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        state.store.list_items(limit.max(1), offset)
    })();
    to_json(result).into_raw()
}

/// Get one item with blocks by id. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_get_item(handle: *mut c_void, id: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Option<Item>> {
        let state = unsafe { state(handle)? };
        state.store.get_item(c_str(id, "id")?)
    })();
    to_json(result).into_raw()
}

/// Full-text search. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_search(handle: *mut c_void, query: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        state.store.search(c_str(query, "query")?)
    })();
    to_json(result).into_raw()
}

/// Tag an item (creates the tag if needed). JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_tag_item(
    handle: *mut c_void,
    item_id: *const c_char,
    tag_name: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Tag> {
        let state = unsafe { state(handle)? };
        state
            .store
            .tag_item(c_str(item_id, "item_id")?, c_str(tag_name, "tag_name")?)
    })();
    to_json(result).into_raw()
}

/// List all tags. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_tags(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Tag>> {
        let state = unsafe { state(handle)? };
        state.store.list_tags()
    })();
    to_json(result).into_raw()
}

/// List tags attached to one item. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_item_tags(handle: *mut c_void, item_id: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Tag>> {
        let state = unsafe { state(handle)? };
        state.store.list_tags_for_item(c_str(item_id, "item_id")?)
    })();
    to_json(result).into_raw()
}

/// Create a collection. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_create_collection(handle: *mut c_void, name: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Collection> {
        let state = unsafe { state(handle)? };
        state.store.create_collection(c_str(name, "name")?)
    })();
    to_json(result).into_raw()
}

/// List collections. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_collections(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Collection>> {
        let state = unsafe { state(handle)? };
        state.store.list_collections()
    })();
    to_json(result).into_raw()
}

/// Add an item to a collection. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_add_to_collection(
    handle: *mut c_void,
    item_id: *const c_char,
    collection_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<bool> {
        let state = unsafe { state(handle)? };
        state
            .store
            .add_item_to_collection(c_str(item_id, "item_id")?, c_str(collection_id, "collection_id")?)
            .map(|_| true)
    })();
    to_json(result).into_raw()
}

/// Add an annotation (quote + optional note) to an item. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_add_annotation(
    handle: *mut c_void,
    item_id: *const c_char,
    quote: *const c_char,
    note: *const c_char,
    block_idx: i64,
) -> *mut c_char {
    let result = (|| -> RefractResult<Annotation> {
        let state = unsafe { state(handle)? };
        let note = if note.is_null() {
            None
        } else {
            Some(c_str(note, "note")?)
        };
        let block_idx = if block_idx < 0 { None } else { Some(block_idx as u32) };
        state.store.add_annotation(
            c_str(item_id, "item_id")?,
            c_str(quote, "quote")?,
            note,
            block_idx,
        )
    })();
    to_json(result).into_raw()
}

/// List annotations for an item. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_annotations(handle: *mut c_void, item_id: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Annotation>> {
        let state = unsafe { state(handle)? };
        state.store.list_annotations(c_str(item_id, "item_id")?)
    })();
    to_json(result).into_raw()
}

/// Export the entire library as a JSON string (user sovereignty). JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_export(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let state = unsafe { state(handle)? };
        state.store.export_all()
    })();
    to_json(result).into_raw()
}

/// Daily Edition: items from the last `days` days. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_daily_edition(handle: *mut c_void, days: u32) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        state.store.daily_edition(days)
    })();
    to_json(result).into_raw()
}

// ---------- Phase 3: Consumer X-Ray & Proof Vault ----------

/// Add a subscription. `json` is a partial Subscription object; missing fields
/// default to unverified/unknown. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_add_subscription(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Subscription> {
        let state = unsafe { state(handle)? };
        let raw = c_str(json, "json")?;
        let mut sub: Subscription = serde_json::from_str(raw)
            .map_err(|e| RefractError::invalid(format!("subscription json: {e}")))?;
        if sub.id.is_empty() {
            sub.id = uuid::Uuid::new_v4().to_string();
        }
        if sub.created_ts == 0 {
            sub.created_ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_err(|e| RefractError::internal(e.to_string()))?
                .as_secs() as i64;
        }
        if sub.status.as_str() == "unverified" && sub.price.is_some() {
            sub.status = SubscriptionStatus::Imported;
        }
        state.store.add_subscription(&sub)?;
        Ok(sub)
    })();
    to_json(result).into_raw()
}

/// List all subscription records. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_subscriptions(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Subscription>> {
        let state = unsafe { state(handle)? };
        state.store.list_subscriptions()
    })();
    to_json(result).into_raw()
}

/// Upcoming renewal/trial events within `days`. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_upcoming_events(handle: *mut c_void, days: u32) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Subscription>> {
        let state = unsafe { state(handle)? };
        state.store.upcoming_events(days)
    })();
    to_json(result).into_raw()
}

/// Store an evidence record from raw bytes; optionally extract claims from text.
#[no_mangle]
pub unsafe extern "C" fn refract_add_evidence(
    handle: *mut c_void,
    kind: *const c_char,
    note: *const c_char,
    bytes: *const u8,
    len: usize,
    text_for_claims: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<EvidenceRecord> {
        let state = unsafe { state(handle)? };
        if bytes.is_null() {
            return Err(RefractError::invalid("null evidence bytes"));
        }
        if len > 10 * 1024 * 1024 { return Err(RefractError::invalid("PDF exceeds 10 MiB")); }
        let raw = unsafe { std::slice::from_raw_parts(bytes, len) };
        let note = if note.is_null() { None } else { Some(c_str(note, "note")?) };
        let text = if text_for_claims.is_null() {
            None
        } else {
            Some(c_str(text_for_claims, "text_for_claims")?)
        };
        state.store.add_evidence(c_str(kind, "kind")?, note, raw, text)
    })();
    to_json(result).into_raw()
}

/// List evidence records. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_evidence(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<EvidenceRecord>> {
        let state = unsafe { state(handle)? };
        state.store.list_evidence()
    })();
    to_json(result).into_raw()
}

/// List claims extracted from one evidence record. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_claims(handle: *mut c_void, record_id: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<EvidenceClaim>> {
        let state = unsafe { state(handle)? };
        state.store.list_claims(c_str(record_id, "record_id")?)
    })();
    to_json(result).into_raw()
}

/// Re-verify an evidence record's hash. Payload: true/false/null (not found).
#[no_mangle]
pub unsafe extern "C" fn refract_verify_evidence(handle: *mut c_void, id: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<Option<bool>> {
        let state = unsafe { state(handle)? };
        state.store.verify_evidence(c_str(id, "id")?)
    })();
    to_json(result).into_raw()
}

// ---------- Phase 4: Local Intelligence ----------

/// Serializable AI output crossing the FFI boundary (always labeled).
#[derive(serde::Serialize)]
struct AiOutputJson {
    kind: &'static str, // "extractive" | "interpretation"
    text: String,
    source_blocks: Vec<u32>,
    model_used: bool,
}

fn ai_to_json(o: AiOutput) -> AiOutputJson {
    AiOutputJson {
        kind: match o.kind {
            ai_runtime::OutputKind::Extractive => "extractive",
            ai_runtime::OutputKind::Interpretation => "interpretation",
        },
        text: o.text,
        source_blocks: o.source_blocks,
        model_used: o.model_used,
    }
}

fn runtime() -> &'static AiRuntime {
    static RT: std::sync::OnceLock<AiRuntime> = std::sync::OnceLock::new();
    RT.get_or_init(AiRuntime::new)
}

/// Summarize an item. Output is labeled extractive/interpretation (spec §3.5).
#[no_mangle]
pub unsafe extern "C" fn refract_summarize(
    handle: *mut c_void,
    item_id: *const c_char,
    max_sentences: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<AiOutputJson> {
        let state = unsafe { state(handle)? };
        let item = state
            .store
            .get_item(c_str(item_id, "item_id")?)?
            .ok_or_else(|| RefractError::invalid("item not found"))?;
        let out = runtime().summarize(&item.blocks, max_sentences.max(1) as usize)?;
        Ok(ai_to_json(out))
    })();
    to_json(result).into_raw()
}

/// Suggest tags for an item (deterministic keyword engine for now).
#[no_mangle]
pub unsafe extern "C" fn refract_suggest_tags(
    handle: *mut c_void,
    item_id: *const c_char,
    max_tags: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<AiOutputJson> {
        let state = unsafe { state(handle)? };
        let item = state
            .store
            .get_item(c_str(item_id, "item_id")?)?
            .ok_or_else(|| RefractError::invalid("item not found"))?;
        let out = runtime().suggest_tags(&item.blocks, max_tags.max(1) as usize)?;
        Ok(ai_to_json(out))
    })();
    to_json(result).into_raw()
}

/// Related content via shared full-text terms. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_related(
    handle: *mut c_void,
    item_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        state.store.related_items(c_str(item_id, "item_id")?, limit.max(1))
    })();
    to_json(result).into_raw()
}

// ---------- Phase 5: Multiplayer Margins ----------

/// Create a shared workspace. JSON envelope with the workspace id.
#[no_mangle]
pub unsafe extern "C" fn refract_create_workspace(handle: *mut c_void, name: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let state = unsafe { state(handle)? };
        state.store.create_workspace(c_str(name, "name")?)
    })();
    to_json(result).into_raw()
}

/// List workspaces as [id, name] pairs. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_list_workspaces(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<(String, String)>> {
        let state = unsafe { state(handle)? };
        state.store.list_workspaces()
    })();
    to_json(result).into_raw()
}

/// Share an annotation into a workspace: upserted into the CRDT doc and the
/// resulting state queued in the sync outbox. Only the annotation payload is
/// shared — never the source document (spec §C5).
#[no_mangle]
pub unsafe extern "C" fn refract_share_annotation(
    handle: *mut c_void,
    workspace_id: *const c_char,
    annotation_id: *const c_char,
    payload_json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<bool> {
        let state = unsafe { state(handle)? };
        state.store.upsert_shared_annotation(
            c_str(workspace_id, "workspace_id")?,
            c_str(annotation_id, "annotation_id")?,
            c_str(payload_json, "payload_json")?,
        )?;
        Ok(true)
    })();
    to_json(result).into_raw()
}

/// Number of unsynced outbox entries (opportunistic sync status).
#[no_mangle]
pub unsafe extern "C" fn refract_sync_pending(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<usize> {
        let state = unsafe { state(handle)? };
        state.store.pending_sync(1000)
    })();
    to_json(result).into_raw()
}

// ---------- Phase II master, Phase 2: REFRACT SENSE ----------

use personal_memory::sense::CaptureDecisionRecord;

/// Re-run the SENSE decision pipeline for an item. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_evaluate(
    handle: *mut c_void,
    item_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<CaptureDecisionRecord> {
        let state = unsafe { state(handle)? };
        let id = c_str(item_id, "item_id")?;
        let item = state
            .store
            .get_item(id)?
            .ok_or_else(|| RefractError::invalid(format!("item not found: {id}")))?;
        let body: String = item
            .blocks
            .iter()
            .map(|b| b.text.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        state.store.evaluate_sense(&item, &body)
    })();
    to_json(result).into_raw()
}

/// Capture history / Smart Inbox review list. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_decisions(
    handle: *mut c_void,
    limit: u32,
    offset: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<CaptureDecisionRecord>> {
        let state = unsafe { state(handle)? };
        state.store.list_capture_decisions(limit, offset)
    })();
    to_json(result).into_raw()
}

/// Review a decision: action is approve | dismiss | undo. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_review(
    handle: *mut c_void,
    decision_id: *const c_char,
    action: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<CaptureDecisionRecord> {
        let state = unsafe { state(handle)? };
        state
            .store
            .review_capture_decision(c_str(decision_id, "decision_id")?, c_str(action, "action")?)
    })();
    to_json(result).into_raw()
}

/// List capture policy rules. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_rules(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<personal_memory::sense::SenseRule>> {
        let state = unsafe { state(handle)? };
        state.store.list_sense_rules()
    })();
    to_json(result).into_raw()
}

/// Create/update a user rule. `json` = {id?, name, kind, pattern, enabled}.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_rule_upsert(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<personal_memory::sense::SenseRule> {
        let state = unsafe { state(handle)? };
        #[derive(serde::Deserialize)]
        struct RuleIn {
            #[serde(default)]
            id: String,
            name: String,
            kind: String,
            pattern: String,
            #[serde(default = "default_true")]
            enabled: bool,
        }
        fn default_true() -> bool {
            true
        }
        let input: RuleIn = serde_json::from_str(c_str(json, "json")?)
            .map_err(|e| RefractError::invalid(format!("rule json: {e}")))?;
        state
            .store
            .upsert_sense_rule(&input.id, &input.name, &input.kind, &input.pattern, input.enabled)
    })();
    to_json(result).into_raw()
}

/// Delete a capture rule by id. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_rule_delete(
    handle: *mut c_void,
    rule_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let state = unsafe { state(handle)? };
        state.store.delete_sense_rule(c_str(rule_id, "rule_id")?)?;
        Ok("deleted".into())
    })();
    to_json(result).into_raw()
}

/// Apply a built-in preset (conservative|balanced|research|personal_archive).
/// Returns the number of rules installed. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_preset_set(
    handle: *mut c_void,
    preset: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<usize> {
        let state = unsafe { state(handle)? };
        state.store.apply_sense_preset(c_str(preset, "preset")?)
    })();
    to_json(result).into_raw()
}

/// Read a SENSE setting (e.g. active_preset). JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_setting_get(
    handle: *mut c_void,
    key: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let state = unsafe { state(handle)? };
        Ok(state.store.sense_setting(c_str(key, "key")?, "")?)
    })();
    to_json(result).into_raw()
}

/// Set a SENSE setting. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_sense_setting_set(
    handle: *mut c_void,
    key: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let state = unsafe { state(handle)? };
        state
            .store
            .set_sense_setting(c_str(key, "key")?, c_str(value, "value")?)
            .map(|_| "ok".to_string())
    })();
    to_json(result).into_raw()
}

// ---------- Phase II master, Phase 3: SMART MEMORY ----------

use personal_memory::smart_memory::{
    Entity, OrganizeReport, Project, Relationship, TimelineEntry, Topic, TopicEvolution,
};

/// Automatic organization for one item (topics, entities, temporal context,
/// relationship suggestions). JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_memory_organize_item(
    handle: *mut c_void,
    item_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<OrganizeReport> {
        let state = unsafe { state(handle)? };
        let id = c_str(item_id, "item_id")?;
        state.store.organize_item(id)
    })();
    to_json(result).into_raw()
}

/// Organize every item that has no topics yet. JSON envelope.
#[no_mangle]
pub unsafe extern "C" fn refract_memory_organize_library(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<OrganizeReport>> {
        let state = unsafe { state(handle)? };
        state.store.organize_library()
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topics_list(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Topic>> {
        let state = unsafe { state(handle)? };
        state.store.list_topics()
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topic_rename(
    handle: *mut c_void,
    topic_id: *const c_char,
    new_name: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Topic> {
        let state = unsafe { state(handle)? };
        let id = c_str(topic_id, "topic_id")?;
        let name = c_str(new_name, "new_name")?;
        state.store.rename_topic(id, name)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topic_merge(
    handle: *mut c_void,
    from_id: *const c_char,
    to_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Topic> {
        let state = unsafe { state(handle)? };
        let from = c_str(from_id, "from_id")?;
        let to = c_str(to_id, "to_id")?;
        state.store.merge_topics(from, to)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topic_reject(
    handle: *mut c_void,
    topic_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let id = c_str(topic_id, "topic_id")?;
        state.store.reject_topic(id)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topic_pin(
    handle: *mut c_void,
    topic_id: *const c_char,
    pinned: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let id = c_str(topic_id, "topic_id")?;
        state.store.set_topic_pinned(id, pinned != 0)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_topic_items(
    handle: *mut c_void,
    topic_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        let id = c_str(topic_id, "topic_id")?;
        state.store.items_for_topic(id, limit)
    })();
    to_json(result).into_raw()
}

/// Knowledge Evolution: descriptive stages of how a topic developed.
#[no_mangle]
pub unsafe extern "C" fn refract_topic_evolution(
    handle: *mut c_void,
    topic_id: *const c_char,
    stages: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<TopicEvolution> {
        let state = unsafe { state(handle)? };
        let id = c_str(topic_id, "topic_id")?;
        state.store.topic_evolution(id, stages)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_entities_list(handle: *mut c_void, limit: u32) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Entity>> {
        let state = unsafe { state(handle)? };
        state.store.list_entities(limit)
    })();
    to_json(result).into_raw()
}

/// Relationship suggestions. Pass an empty item_id for the whole library.
#[no_mangle]
pub unsafe extern "C" fn refract_relationships_list(
    handle: *mut c_void,
    item_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Relationship>> {
        let state = unsafe { state(handle)? };
        let id = c_str(item_id, "item_id")?;
        let filter = if id.is_empty() { None } else { Some(id) };
        state.store.list_relationships(filter, limit)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_relationship_dismiss(
    handle: *mut c_void,
    rel_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let id = c_str(rel_id, "rel_id")?;
        state.store.dismiss_relationship(id)
    })();
    to_json(result).into_raw()
}

/// User-added relationship. JSON input:
/// {source_item_id, target_item_id, kind, basis}
#[no_mangle]
pub unsafe extern "C" fn refract_relationship_add(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Relationship> {
        let state = unsafe { state(handle)? };
        #[derive(serde::Deserialize)]
        struct RelIn {
            source_item_id: String,
            target_item_id: String,
            kind: String,
            #[serde(default)]
            basis: String,
        }
        let input: RelIn = serde_json::from_str(c_str(json, "json")?)
            .map_err(|e| RefractError::invalid(format!("relationship json: {e}")))?;
        let basis = if input.basis.is_empty() {
            "added by user".to_string()
        } else {
            input.basis
        };
        state.store.add_relationship(
            &input.source_item_id,
            &input.target_item_id,
            &input.kind,
            &basis,
        )
    })();
    to_json(result).into_raw()
}

/// Memory Timeline: chronological entries with explicit time kinds.
#[no_mangle]
pub unsafe extern "C" fn refract_memory_timeline(handle: *mut c_void, limit: u32) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<TimelineEntry>> {
        let state = unsafe { state(handle)? };
        state.store.memory_timeline(limit)
    })();
    to_json(result).into_raw()
}

/// Record an explicit timestamp. JSON input:
/// {item_id, kind, ts, note?} — kind is publication|modification|event|deadline.
#[no_mangle]
pub unsafe extern "C" fn refract_item_time_set(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        #[derive(serde::Deserialize)]
        struct TimeIn {
            item_id: String,
            kind: String,
            ts: i64,
            note: Option<String>,
        }
        let input: TimeIn = serde_json::from_str(c_str(json, "json")?)
            .map_err(|e| RefractError::invalid(format!("time json: {e}")))?;
        state.store.set_item_time(
            &input.item_id,
            &input.kind,
            input.ts,
            input.note.as_deref(),
        )
    })();
    to_json(result).into_raw()
}

// ----- Project Spaces -----

#[no_mangle]
pub unsafe extern "C" fn refract_projects_list(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Project>> {
        let state = unsafe { state(handle)? };
        state.store.list_projects()
    })();
    to_json(result).into_raw()
}

/// JSON input: {name, description?}
#[no_mangle]
pub unsafe extern "C" fn refract_project_create(
    handle: *mut c_void,
    json: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Project> {
        let state = unsafe { state(handle)? };
        #[derive(serde::Deserialize)]
        struct ProjIn {
            name: String,
            description: Option<String>,
        }
        let input: ProjIn = serde_json::from_str(c_str(json, "json")?)
            .map_err(|e| RefractError::invalid(format!("project json: {e}")))?;
        state.store.create_project(&input.name, input.description.as_deref())
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_project_delete(
    handle: *mut c_void,
    project_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let id = c_str(project_id, "project_id")?;
        state.store.delete_project(id)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_project_add_item(
    handle: *mut c_void,
    project_id: *const c_char,
    item_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let pid = c_str(project_id, "project_id")?;
        let iid = c_str(item_id, "item_id")?;
        state.store.project_add_item(pid, iid)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_project_remove_item(
    handle: *mut c_void,
    project_id: *const c_char,
    item_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<()> {
        let state = unsafe { state(handle)? };
        let pid = c_str(project_id, "project_id")?;
        let iid = c_str(item_id, "item_id")?;
        state.store.project_remove_item(pid, iid)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_project_items(
    handle: *mut c_void,
    project_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<Item>> {
        let state = unsafe { state(handle)? };
        let pid = c_str(project_id, "project_id")?;
        state.store.project_items(pid, limit)
    })();
    to_json(result).into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn refract_project_timeline(
    handle: *mut c_void,
    project_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> RefractResult<Vec<TimelineEntry>> {
        let state = unsafe { state(handle)? };
        let pid = c_str(project_id, "project_id")?;
        state.store.project_timeline(pid, limit)
    })();
    to_json(result).into_raw()
}

// ---------- Phase 6: Provenance & cross-device state ----------

/// Root of the evidence Merkle log (hex string), or null when empty.
#[no_mangle]
pub unsafe extern "C" fn refract_evidence_merkle_root(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<Option<String>> {
        let state = unsafe { state(handle)? };
        state.store.evidence_merkle_root()
    })();
    to_json(result).into_raw()
}

/// Merkle inclusion proof for one evidence record (JSON, with statement of
/// what the proof does and does not establish, spec §B5).
#[no_mangle]
pub unsafe extern "C" fn refract_evidence_merkle_proof(
    handle: *mut c_void,
    record_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Option<crypto_provenance::MerkleProof>> {
        let state = unsafe { state(handle)? };
        state.store.evidence_merkle_proof(c_str(record_id, "record_id")?)
    })();
    to_json(result).into_raw()
}

/// Verify a record's inclusion proof against the current log root.
#[no_mangle]
pub unsafe extern "C" fn refract_verify_evidence_proof(
    handle: *mut c_void,
    record_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<Option<bool>> {
        let state = unsafe { state(handle)? };
        let id = c_str(record_id, "record_id")?;
        let Some(proof) = state.store.evidence_merkle_proof(id)? else {
            return Ok(None);
        };
        let Some(root) = state.store.evidence_merkle_root()? else {
            return Ok(None);
        };
        Ok(Some(crypto_provenance::verify_proof(&proof, &root)))
    })();
    to_json(result).into_raw()
}

/// Export a workspace's CRDT state as a hex string (cross-device transfer).
#[no_mangle]
pub unsafe extern "C" fn refract_export_workspace_state(
    handle: *mut c_void,
    workspace_id: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<String> {
        let _state = unsafe { state(handle)? };
        let _=c_str(workspace_id,"workspace_id")?;
        Err(RefractError::invalid("Legacy anonymous export is disabled; use recipient-encrypted Margins exchange"))
    })();
    to_json(result).into_raw()
}

/// Import CRDT state (hex) from another device into a workspace.
#[no_mangle]
pub unsafe extern "C" fn refract_import_workspace_state(
    handle: *mut c_void,
    workspace_id: *const c_char,
    hex_state: *const c_char,
) -> *mut c_char {
    let result = (|| -> RefractResult<bool> {
        let _state = unsafe { state(handle)? };
        let _=c_str(workspace_id,"workspace_id")?;let _=c_str(hex_state,"hex_state")?;
        Err(RefractError::invalid("Legacy anonymous import is disabled; use authenticated Margins exchange"))
    })();
    to_json(result).into_raw()
}

// ----- Phase II master, Phase 4: REFRACT RECALL -----
#[no_mangle]
pub unsafe extern "C" fn refract_recall_query(handle: *mut c_void, json: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<personal_memory::recall::RecallResponse> {
        let state = unsafe { state(handle)? };
        let request = serde_json::from_str(c_str(json, "request")?)
            .map_err(|e| RefractError::invalid(format!("Recall request: {e}")))?;
        state.store.recall(&request)
    })();
    to_json(result).into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn refract_recall_rebuild(handle: *mut c_void) -> *mut c_char {
    let result = (|| -> RefractResult<usize> {
        let state = unsafe { state(handle)? };
        state.store.recall_rebuild_index()
    })();
    to_json(result).into_raw()
}

// ----- Phase II master, Phase 5: DAILY SIGNAL / CONTEXT -----
#[no_mangle]
pub unsafe extern "C" fn refract_signal(handle: *mut c_void, json: *const c_char) -> *mut c_char {
    let result = (|| -> RefractResult<serde_json::Value> {
        let store = &unsafe { state(handle)? }.store;
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request { action: String, #[serde(default)] payload: serde_json::Value }
        let request: Request = serde_json::from_str(c_str(json,"signal request")?).map_err(|e| RefractError::invalid(format!("Signal request: {e}")))?;
        fn decode<T: serde::de::DeserializeOwned>(v: serde_json::Value) -> RefractResult<T> { serde_json::from_value(v).map_err(|e|RefractError::invalid(e.to_string())) }
        fn value<T: serde::Serialize>(v:T) -> RefractResult<serde_json::Value> { serde_json::to_value(v).map_err(|e|RefractError::internal(e.to_string())) }
        match request.action.as_str() {
            "config" => value(store.signal_config()?),
            "configure" => {store.signal_set_config(&decode(request.payload)?)?;value(store.signal_config()?)},
            "edition" | "refresh" => value(store.daily_signal(request.action=="refresh")?),
            "context" => value(store.signal_context(&decode(request.payload)?)?),
            "reading" => {store.signal_reading_update(&decode(request.payload)?)?;value(true)},
            "clear_reading" => {store.signal_clear_reading()?;value(true)},
            "reset_dismissals" => {store.signal_reset_dismissals()?;value(true)},
            "dismiss" => {let key:String=decode(request.payload)?;store.signal_dismiss(&key)?;value(true)},
            "review_event" => {
                #[derive(serde::Deserialize)] #[serde(deny_unknown_fields)] struct Review { id:String,status:String }
                let input:Review=decode(request.payload)?;store.signal_review_event(&input.id,&input.status)?;value(true)
            },
            _ => Err(RefractError::invalid("unsupported Signal action")),
        }
    })();
    to_json(result).into_raw()
}

// ----- Phase II master, Phase 6: CONSUMER X-RAY EXPANSION -----
#[no_mangle]
pub unsafe extern "C" fn refract_consumer(handle:*mut c_void,json:*const c_char)->*mut c_char {
    let result=(||->RefractResult<serde_json::Value>{
        let store=&unsafe{state(handle)?}.store;
        #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Request{action:String,#[serde(default)]payload:serde_json::Value}
        let request:Request=serde_json::from_str(c_str(json,"consumer request")?).map_err(|e|RefractError::invalid(e.to_string()))?;
        fn decode<T:serde::de::DeserializeOwned>(v:serde_json::Value)->RefractResult<T>{serde_json::from_value(v).map_err(|e|RefractError::invalid(e.to_string()))}
        fn value<T:serde::Serialize>(v:T)->RefractResult<serde_json::Value>{serde_json::to_value(v).map_err(|e|RefractError::internal(e.to_string()))}
        match request.action.as_str(){
            "documents"=>value(store.consumer_documents()?),
            "scan_library"=>value(store.consumer_analyze_library()?),
            "scan"=>{let id:String=decode(request.payload)?;value(store.consumer_analyze(&id)?)},
            "document"=>{let id:String=decode(request.payload)?;value(store.consumer_document(&id)?)},
            "search"=>value(store.consumer_search(&decode(request.payload)?)?),
            "compare"=>{let ids:Vec<String>=decode(request.payload)?;value(store.consumer_compare(&ids)?)},
            "review"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Review{id:String,status:String}let input:Review=decode(request.payload)?;store.consumer_review(&input.id,&input.status)?;value(true)},
            "history"=>{let id:String=decode(request.payload)?;value(store.consumer_review_history(&id)?)},
            "check_original"=>{let id:String=decode(request.payload)?;value(store.consumer_check_original(&id)?)},
            "track_subscription"=>{let id:String=decode(request.payload)?;value(store.consumer_track_subscription(&id)?)},
            _=>Err(RefractError::invalid("unsupported consumer action")),
        }
    })();to_json(result).into_raw()
}

// ----- Phase II master, Phase 7: ADVANCED KNOWLEDGE -----
#[no_mangle]
pub unsafe extern "C" fn refract_knowledge(handle:*mut c_void,json:*const c_char)->*mut c_char{
 let result=(||->RefractResult<serde_json::Value>{
  let store=&unsafe{state(handle)?}.store;
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Request{action:String,#[serde(default)]payload:serde_json::Value}
  let request:Request=serde_json::from_str(c_str(json,"knowledge request")?).map_err(|e|RefractError::invalid(e.to_string()))?;
  fn decode<T:serde::de::DeserializeOwned>(v:serde_json::Value)->RefractResult<T>{serde_json::from_value(v).map_err(|e|RefractError::invalid(e.to_string()))}
  fn value<T:serde::Serialize>(v:T)->RefractResult<serde_json::Value>{serde_json::to_value(v).map_err(|e|RefractError::internal(e.to_string()))}
  match request.action.as_str(){
   "decisions"=>value(store.decision_search(&decode(request.payload)?)?),
   "decision"=>{let id:String=decode(request.payload)?;value(store.decision_get(&id)?)},
   "save_decision"=>value(store.decision_save(&decode(request.payload)?)?),
   "decision_history"=>{let id:String=decode(request.payload)?;value(store.decision_history(&id)?)},
   "archive_decision"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{id:String,archived:bool}let input:Input=decode(request.payload)?;store.decision_archive(&input.id,input.archived)?;value(true)},
   "graph"=>value(store.knowledge_graph(&decode(request.payload)?)?),
   "path"=>value(store.knowledge_path(&decode(request.payload)?)?),
   "dismiss_link"=>{let id:String=decode(request.payload)?;store.dismiss_relationship(&id)?;value(true)},
   "compressions"=>value(store.compression_list()?),
   "compress"=>value(store.compression_create(&decode(request.payload)?)?),
   "compression"=>{let id:String=decode(request.payload)?;value(store.compression_get(&id)?)},
   "regenerate_compression"=>{let id:String=decode(request.payload)?;value(store.compression_regenerate(&id)?)},
   "discard_compression"=>{let id:String=decode(request.payload)?;store.compression_discard(&id)?;value(true)},
   "source"=>{let id:String=decode(request.payload)?;value(store.source_intelligence(&id)?)},
   "source_snapshot"=>{let id:String=decode(request.payload)?;store.knowledge_record_snapshot(&id)?;value(true)},
   "source_diff"=>value(store.source_diff(&decode(request.payload)?)?),
   _=>Err(RefractError::invalid("unsupported knowledge action")),
  }
 })();to_json(result).into_raw()
}

// ----- Phase II master Phase 8: selected, authenticated offline collaboration -----
#[no_mangle]
pub unsafe extern "C" fn refract_margins(handle:*mut c_void,request:*const c_char)->*mut c_char{
 let result=(||->RefractResult<serde_json::Value>{
  let store=&unsafe{state(handle)?}.store;
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Request{action:String,#[serde(default)]payload:serde_json::Value}
  let text=c_str(request,"Margins request")?;if text.len()>1_700_000{return Err(RefractError::invalid("Margins request too large"));}
  let q:Request=serde_json::from_str(text).map_err(|e|RefractError::invalid(e.to_string()))?;
  fn decode<T:serde::de::DeserializeOwned>(v:serde_json::Value)->RefractResult<T>{serde_json::from_value(v).map_err(|e|RefractError::invalid(e.to_string()))}
  fn value<T:serde::Serialize>(v:T)->RefractResult<serde_json::Value>{serde_json::to_value(v).map_err(|e|RefractError::internal(e.to_string()))}
  match q.action.as_str(){
   "contact"=>value(store.margin_contact()?),
   "verify_contact"=>{let c:personal_memory::margins::DeviceContact=decode(q.payload)?;c.validate()?;value(c)},
   "set_name"=>{let name:String=decode(q.payload)?;value(store.margin_set_name(&name)?)},
   "workspaces"=>value(store.margin_list()?),
   "create"=>{let name:String=decode(q.payload)?;value(store.margin_create(&name)?)},
   "workspace"=>{let id:String=decode(q.payload)?;value(store.margin_view(&id)?)},
   "history"=>{let id:String=decode(q.payload)?;value(store.margin_history(&id)?)},
   "transfers"=>{let id:String=decode(q.payload)?;value(store.margin_transfers(&id)?)},
   "peers"=>{let id:String=decode(q.payload)?;value(store.margin_peers(&id)?)},
   "enable"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{id:String,enabled:bool}let i:Input=decode(q.payload)?;store.margin_enable(&i.id,i.enabled)?;value(true)},
   "member"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{id:String,contact:personal_memory::margins::DeviceContact,role:String}let i:Input=decode(q.payload)?;value(store.margin_member(&i.id,&i.contact,&i.role)?)},
   "preview"=>{let input:personal_memory::margins::NewEntry=decode(q.payload)?;let r=store.margin_preview(&input)?;let hash=personal_memory::Store::margin_preview_hash(&input.workspace_id,&r)?;value(serde_json::json!({"revision":r,"review_hash":hash}))},
   "publish"=>value(store.margin_publish(&decode(q.payload)?)?),
   "edit"=>value(store.margin_edit(&decode(q.payload)?)?),
   "bind"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{id:String,document_id:String,item_id:String}let i:Input=decode(q.payload)?;value(store.margin_bind(&i.id,&i.document_id,&i.item_id)?)},
   "inspect"=>{let packet:String=decode(q.payload)?;value(store.margin_inspect(&packet)?)},
   "import"=>value(store.margin_import_packet(&decode(q.payload)?)?),
   "export"=>value(store.margin_export_packet(&decode(q.payload)?)?),
   "receipt"|"retry"=>{#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{id:String,hash:String}let i:Input=decode(q.payload)?;value(if q.action=="receipt"{store.margin_receipt(&i.id,&i.hash)?}else{store.margin_retry(&i.id,&i.hash)?})},
   _=>Err(RefractError::invalid("Unsupported Margins action")),
  }
 })();to_json(result).into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn ffi_roundtrip() {
        assert_eq!(refract_abi_version(), 1);
        let dir = std::env::temp_dir().join(format!("refract-ffi-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = CString::new(dir.join("test.db").to_str().unwrap()).unwrap();
        let h = unsafe { refract_open(db.as_ptr()) };
        assert!(!h.is_null());

        let text = CString::new("A note about prisms and light.").unwrap();
        let r = unsafe { refract_import_text(h, text.as_ptr(), std::ptr::null()) };
        let s = unsafe { CStr::from_ptr(r) }.to_str().unwrap().to_string();
        unsafe { refract_free_string(r) };
        assert!(s.contains("\"ok\":true"), "got: {s}");

        let q = CString::new("prisms").unwrap();
        let r = unsafe { refract_search(h, q.as_ptr()) };
        let s = unsafe { CStr::from_ptr(r) }.to_str().unwrap().to_string();
        unsafe { refract_free_string(r) };
        assert!(s.contains("\"ok\":true") && s.contains("A note about prisms"), "got: {s}");

        let r = unsafe { refract_list_items(h, 10, 0) };
        let s = unsafe { CStr::from_ptr(r) }.to_str().unwrap().to_string();
        unsafe { refract_free_string(r) };
        assert!(s.contains("prisms") || s.contains("A note"), "got: {s}");

        unsafe { refract_close(h) };
        std::fs::remove_dir_all(&dir).ok();
    }
    /// Exercise the new ABI with actual SQLite and native-owned JSON strings.
    #[test]
    fn smart_memory_ffi_roundtrip() {
        fn payload(ptr: *mut c_char) -> serde_json::Value {
            assert!(!ptr.is_null());
            let decoded: serde_json::Value = serde_json::from_str(unsafe { CStr::from_ptr(ptr) }.to_str().unwrap()).unwrap();
            unsafe { refract_free_string(ptr) };
            assert_eq!(decoded["ok"], true, "{decoded}");
            decoded["payload"].clone()
        }
        fn c(s: &str) -> CString { CString::new(s).unwrap() }
        let dir = std::env::temp_dir().join(format!("refract-memory-ffi-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = c(dir.join("test.db").to_str().unwrap());
        let handle = unsafe { refract_open(db.as_ptr()) };
        assert!(!handle.is_null());
        unsafe {
            let a = payload(refract_import_text(handle, c("Privacy GDPR and machine learning on 2026-03-01.").as_ptr(), std::ptr::null()));
            let b = payload(refract_import_text(handle, c("Privacy GDPR and encryption at Example Ltd.").as_ptr(), std::ptr::null()));
            let aid = c(a["id"].as_str().unwrap());
            let bid = c(b["id"].as_str().unwrap());
            let topics = payload(refract_topics_list(handle));
            assert!(topics.as_array().unwrap().len() >= 2);
            let privacy = topics.as_array().unwrap().iter().find(|t| t["name"] == "privacy").unwrap();
            let tid = c(privacy["id"].as_str().unwrap());
            assert_eq!(payload(refract_topic_items(handle, tid.as_ptr(), 50)).as_array().unwrap().len(), 2);
            payload(refract_topic_pin(handle, tid.as_ptr(), 1));
            assert_eq!(payload(refract_topic_rename(handle, tid.as_ptr(), c("data privacy").as_ptr()))["origin"], "user");
            assert_eq!(payload(refract_topic_evolution(handle, tid.as_ptr(), 4))["topic"]["name"], "data privacy");
            assert!(!payload(refract_entities_list(handle, 50)).as_array().unwrap().is_empty());
            let relationships = payload(refract_relationships_list(handle, c("").as_ptr(), 50));
            assert!(!relationships.as_array().unwrap().is_empty());
            payload(refract_relationship_dismiss(handle, c(relationships[0]["id"].as_str().unwrap()).as_ptr()));
            payload(refract_memory_organize_item(handle, aid.as_ptr()));
            payload(refract_memory_organize_library(handle));
            let time = serde_json::json!({"item_id": a["id"], "kind": "deadline", "ts": 1772323200, "note": "specified by user"});
            payload(refract_item_time_set(handle, c(&time.to_string()).as_ptr()));
            let timeline = payload(refract_memory_timeline(handle, 50));
            assert!(timeline.as_array().unwrap().iter().any(|e| e["time_kind"] == "deadline"));
            let rel = serde_json::json!({"source_item_id": a["id"], "target_item_id": b["id"], "kind": "supporting_reference", "basis": "user assertion"});
            assert_eq!(payload(refract_relationship_add(handle, c(&rel.to_string()).as_ptr()))["basis"], "user assertion");
            let project = payload(refract_project_create(handle, c(r#"{"name":"Research","description":"References"}"#).as_ptr()));
            let pid = c(project["id"].as_str().unwrap());
            payload(refract_project_add_item(handle, pid.as_ptr(), aid.as_ptr()));
            payload(refract_project_add_item(handle, pid.as_ptr(), bid.as_ptr()));
            assert_eq!(payload(refract_project_items(handle, pid.as_ptr(), 50)).as_array().unwrap().len(), 2);
            assert!(!payload(refract_project_timeline(handle, pid.as_ptr(), 50)).as_array().unwrap().is_empty());
            assert_eq!(payload(refract_projects_list(handle))[0]["item_count"], 2);
            payload(refract_project_remove_item(handle, pid.as_ptr(), bid.as_ptr()));
            payload(refract_project_delete(handle, pid.as_ptr()));
            let ai = topics.as_array().unwrap().iter().find(|t| t["name"] == "artificial intelligence").unwrap();
            payload(refract_topic_merge(handle, c(ai["id"].as_str().unwrap()).as_ptr(), tid.as_ptr()));
            let security = topics.as_array().unwrap().iter().find(|t| t["name"] == "security").unwrap();
            payload(refract_topic_reject(handle, c(security["id"].as_str().unwrap()).as_ptr()));
            refract_close(handle);
            let response = refract_topics_list(std::ptr::null_mut());
            let invalid: serde_json::Value = serde_json::from_str(CStr::from_ptr(response).to_str().unwrap()).unwrap();
            refract_free_string(response);
            assert_eq!(invalid["ok"], false);
        }
    }

    #[test]
    fn recall_ffi_evidence_and_error_envelopes() {
        fn read(ptr: *mut c_char) -> serde_json::Value {
            let v = serde_json::from_str(unsafe { CStr::from_ptr(ptr) }.to_str().unwrap()).unwrap();
            unsafe { refract_free_string(ptr) }; v
        }
        let dir = std::env::temp_dir().join(format!("refract-recall-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = CString::new(dir.join("test.db").to_str().unwrap()).unwrap();
        unsafe {
            let h = refract_open(path.as_ptr()); assert!(!h.is_null());
            let text = CString::new("GDPR protects data in machine learning.").unwrap();
            let imported = read(refract_import_text(h, text.as_ptr(), std::ptr::null()));
            assert_eq!(imported["ok"], true);
            let query = CString::new(r#"{"query":"Find that article about AI privacy","mode":"answer"}"#).unwrap();
            let result = read(refract_recall_query(h, query.as_ptr()));
            assert_eq!(result["ok"], true, "{result}");
            assert_eq!(result["payload"]["hits"][0]["item_id"], imported["payload"]["id"]);
            assert_eq!(result["payload"]["model_used"], false);
            assert!(result["payload"]["hits"][0]["evidence"]["block_idx"].is_number());
            let bad = CString::new(r#"{"mode":"invent"}"#).unwrap();
            assert_eq!(read(refract_recall_query(h, bad.as_ptr()))["ok"], false);
            assert_eq!(read(refract_recall_query(h, std::ptr::null()))["ok"], false);
            assert_eq!(read(refract_recall_rebuild(h))["payload"], 1);
            refract_close(h);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn signal_ffi_roundtrip_and_controls() {
        fn read(ptr:*mut c_char)->serde_json::Value {let value=serde_json::from_str(unsafe{CStr::from_ptr(ptr)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(ptr)};value}
        unsafe fn request(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value {
            let input=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();
            let v=read(unsafe{refract_signal(h,input.as_ptr())});assert_eq!(v["ok"],true,"{v}");v["payload"].clone()
        }
        let dir=std::env::temp_dir().join(format!("refract-signal-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();
        let path=CString::new(dir.join("test.db").to_str().unwrap()).unwrap();
        unsafe {
            let h=refract_open(path.as_ptr());assert!(!h.is_null());
            let text=CString::new("Privacy GDPR. Meeting scheduled 2099-01-01. Local information reference.").unwrap();
            let imported=read(refract_import_text(h,text.as_ptr(),std::ptr::null()));assert_eq!(imported["ok"],true);
            let id=imported["payload"]["id"].clone();
            let config=request(h,"config",serde_json::Value::Null);assert_eq!(config["frequency"],"daily");
            request(h,"edition",serde_json::Value::Null);request(h,"refresh",serde_json::Value::Null);
            request(h,"reading",serde_json::json!({"item_id":id,"block_idx":0,"status":"started"}));
            let context=request(h,"context",serde_json::json!({"item_id":id}));
            let eid=context["events"][0]["id"].clone();assert!(eid.is_string(),"{context}");
            assert_eq!(context["events"][0]["status"],"unconfirmed");
            request(h,"review_event",serde_json::json!({"id":eid,"status":"confirmed"}));
            request(h,"dismiss",serde_json::json!("test-key"));request(h,"reset_dismissals",serde_json::Value::Null);request(h,"clear_reading",serde_json::Value::Null);
            let mut disabled=config;disabled["enabled"]=false.into();disabled["context_enabled"]=false.into();request(h,"configure",disabled);
            assert_eq!(request(h,"edition",serde_json::Value::Null)["enabled"],false);
            assert_eq!(request(h,"context",serde_json::json!({"item_id":id}))["enabled"],false);
            let bad=CString::new(r#"{"action":"invent"}"#).unwrap();assert_eq!(read(refract_signal(h,bad.as_ptr()))["ok"],false);
            assert_eq!(read(refract_signal(std::ptr::null_mut(),bad.as_ptr()))["ok"],false);
            refract_close(h);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn consumer_ffi_candidates_review_comparison_and_provenance(){
        fn read(ptr:*mut c_char)->serde_json::Value{let v=serde_json::from_str(unsafe{CStr::from_ptr(ptr)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(ptr)};v}
        unsafe fn call(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value{let input=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();let response=read(unsafe{refract_consumer(h,input.as_ptr())});assert_eq!(response["ok"],true,"{response}");response["payload"].clone()}
        let dir=std::env::temp_dir().join(format!("refract-consumer-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("test.db").to_str().unwrap()).unwrap();
        unsafe{
            let h=refract_open(path.as_ptr());assert!(!h.is_null());let mut ids=Vec::new();
            for text in ["Service: StreamCo\nPrice: EUR 9.99 monthly subscription.\nRenews on 2027-01-01.","Service: StreamCo\nPrice: EUR 10.99 monthly subscription.\nRenews on 2027-02-01."]{
                let text=CString::new(text.replace("\n","
")).unwrap();let v=read(refract_import_text(h,text.as_ptr(),std::ptr::null()));assert_eq!(v["ok"],true);ids.push(v["payload"]["id"].clone());
            }
            let doc=call(h,"document",ids[0].clone());assert!(doc["claims"].as_array().unwrap().len()>=3);let cid=doc["claims"][0]["id"].clone();assert_eq!(doc["claims"][0]["status"],"unconfirmed");
            call(h,"review",serde_json::json!({"id":cid,"status":"user_confirmed"}));assert_eq!(call(h,"history",cid).as_array().unwrap().len(),1);
            call(h,"scan",ids[0].clone());call(h,"scan_library",serde_json::Value::Null);assert!(!call(h,"documents",serde_json::Value::Null).as_array().unwrap().is_empty());
            assert!(!call(h,"search",serde_json::json!({"query":"renewal"})).as_array().unwrap().is_empty());
            assert!(!call(h,"compare",serde_json::json!(ids)).get("fields").unwrap().as_array().unwrap().is_empty());
            assert_eq!(call(h,"check_original",ids[0].clone())["status"],"unchanged_relative_to_recorded_hash");
            for c in doc["claims"].as_array().unwrap(){call(h,"review",serde_json::json!({"id":c["id"],"status":"user_confirmed"}));}
            assert_eq!(call(h,"track_subscription",ids[0].clone())["status"],"imported");
            let bad=CString::new(r#"{"action":"invent"}"#).unwrap();assert_eq!(read(refract_consumer(h,bad.as_ptr()))["ok"],false);assert_eq!(read(refract_consumer(std::ptr::null_mut(),bad.as_ptr()))["ok"],false);refract_close(h);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn knowledge_ffi_end_to_end_and_invalid_requests(){
        fn read(ptr:*mut c_char)->serde_json::Value{assert!(!ptr.is_null());let v=serde_json::from_str(unsafe{CStr::from_ptr(ptr)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(ptr)};v}
        unsafe fn request(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value{let json=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();let v=read(unsafe{refract_knowledge(h,json.as_ptr())});assert_eq!(v["ok"],true,"{v}");v["payload"].clone()}
        let dir=std::env::temp_dir().join(format!("refract-knowledge-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("test.db").to_str().unwrap()).unwrap();
        unsafe{
            let h=refract_open(path.as_ptr());assert!(!h.is_null());let url=CString::new("https://example.org/saved").unwrap();let mut ids=Vec::new();
            for text in ["Privacy GDPR reference. Why local storage?","Privacy GDPR revised source."]{let text=CString::new(text).unwrap();let v=read(refract_import_text(h,text.as_ptr(),url.as_ptr()));assert_eq!(v["ok"],true);ids.push(v["payload"]["id"].clone());}
            let input=serde_json::json!({"title":"Use SQLite","context":"Local-first","options":["SQLite","Remote DB"],"selected_option":"SQLite","reasoning":"Offline access","decision_ts":1700000000,"expected_outcome":"No external account","source_ids":[ids[0]]});
            let saved=request(h,"save_decision",input.clone());let did=saved["id"].clone();assert_eq!(request(h,"decision",did.clone())["kind"],"user_recorded_decision");assert_eq!(request(h,"decisions",serde_json::json!({"query":"SQLite"}))[0]["id"],did);
            let mut edit=input;edit["id"]=did.clone();edit["reasoning"]="Transactional offline storage".into();request(h,"save_decision",edit);assert_eq!(request(h,"decision_history",did.clone()).as_array().unwrap().len(),2);
            request(h,"archive_decision",serde_json::json!({"id":did,"archived":true}));assert!(request(h,"decisions",serde_json::json!({})).as_array().unwrap().is_empty());request(h,"archive_decision",serde_json::json!({"id":did,"archived":false}));
            assert!(!request(h,"graph",serde_json::json!({"kind":"document","id":ids[0]}))["nodes"].as_array().unwrap().is_empty());
            let path=request(h,"path",serde_json::json!({"from_id":ids[0],"to_id":ids[1],"max_depth":1}));assert_eq!(path["found"],true);request(h,"dismiss_link",path["steps"][0]["relationship_id"].clone());
            let compression=request(h,"compress",serde_json::json!({"scope_kind":"selected","item_ids":ids}));let cid=compression["id"].clone();assert_eq!(request(h,"compression",cid.clone())["excerpts"].as_array().unwrap().len(),2);assert_eq!(request(h,"compressions",serde_json::Value::Null).as_array().unwrap().len(),1);request(h,"regenerate_compression",cid.clone());
            request(h,"source_snapshot",ids[0].clone());assert!(!request(h,"source",ids[0].clone())["history"].as_array().unwrap().is_empty());assert!(!request(h,"source_diff",serde_json::json!({"before_id":ids[0],"after_id":ids[1]}))["removed"].as_array().unwrap().is_empty());request(h,"discard_compression",cid);assert!(request(h,"compressions",serde_json::Value::Null).as_array().unwrap().is_empty());
            for bad in [r#"{"action":"invent"}"#,r#"{"action":"graph","payload":{"invent":true}}"#,r#"{"action":"save_decision","payload":{"title":"Guess"}}"#,"not JSON"]{let json=CString::new(bad).unwrap();assert_eq!(read(refract_knowledge(h,json.as_ptr()))["ok"],false);assert_eq!(read(refract_knowledge(std::ptr::null_mut(),json.as_ptr()))["ok"],false);}
            refract_close(h);
        }
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn margins_ffi_selected_exchange_permissions_and_receipts(){
        fn read(ptr:*mut c_char)->serde_json::Value{assert!(!ptr.is_null());let v=serde_json::from_str(unsafe{CStr::from_ptr(ptr)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(ptr)};v}
        unsafe fn call(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value{let q=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();let v=read(unsafe{refract_margins(h,q.as_ptr())});assert_eq!(v["ok"],true,"{v}");v["payload"].clone()}
        let dir=std::env::temp_dir().join(format!("refract-margin-ffi-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let pa=CString::new(dir.join("a.db").to_str().unwrap()).unwrap();let pb=CString::new(dir.join("b.db").to_str().unwrap()).unwrap();
        unsafe{let a=refract_open(pa.as_ptr());let b=refract_open(pb.as_ptr());assert!(!a.is_null()&&!b.is_null());let contact=call(b,"contact",serde_json::Value::Null);call(a,"verify_contact",contact.clone());let w=call(a,"create",serde_json::json!("Team"));let id=w["id"].clone();let owner=w["owner"].clone();assert_eq!(w["exchange_enabled"],false);
        call(a,"member",serde_json::json!({"id":id,"contact":contact,"role":"viewer"}));let mut draft=serde_json::json!({"workspace_id":id,"kind":"note","title":"Shared note","body":"Selected text only"});let preview=call(a,"preview",draft.clone());draft["review_hash"]=preview["review_hash"].clone();call(a,"publish",draft.clone());call(a,"enable",serde_json::json!({"id":id,"enabled":true}));let packet=call(a,"export",serde_json::json!({"workspace_id":id,"recipient":contact["data"]["signing_key"],"kind":"invite"}));assert!(!packet.as_str().unwrap().contains("Selected text only"));call(b,"inspect",packet.clone());let imported=call(b,"import",serde_json::json!({"packet":packet,"expected_owner":owner}));let joined=call(b,"workspace",id.clone());assert_eq!(joined["role"],"viewer");assert_eq!(joined["entries"][0]["versions"][0]["body"],"Selected text only");assert_eq!(joined["exchange_enabled"],false);call(b,"enable",serde_json::json!({"id":id,"enabled":true}));let receipt=call(b,"receipt",serde_json::json!({"id":id,"hash":imported["packet_hash"]}));call(a,"import",serde_json::json!({"packet":receipt,"expected_owner":owner}));assert!(!call(a,"transfers",id.clone()).as_array().unwrap().is_empty());assert!(!call(a,"history",id.clone())["revisions"].as_array().unwrap().is_empty());
        let forbidden=CString::new(serde_json::json!({"action":"publish","payload":draft}).to_string()).unwrap();assert_eq!(read(refract_margins(b,forbidden.as_ptr()))["ok"],false);for bad in [r#"{"action":"invent"}"#,r#"{"action":"create","extra":true}"#,"invalid JSON"]{let q=CString::new(bad).unwrap();assert_eq!(read(refract_margins(a,q.as_ptr()))["ok"],false);assert_eq!(read(refract_margins(std::ptr::null_mut(),q.as_ptr()))["ok"],false);}let legacy=CString::new("oddé").unwrap();assert_eq!(read(refract_import_workspace_state(a,legacy.as_ptr(),legacy.as_ptr()))["ok"],false);refract_close(a);refract_close(b);}
        std::fs::remove_dir_all(dir).unwrap();
    }

}

/// Optional local integration adapters. No provider credentials or network access.
#[no_mangle]
pub unsafe extern "C" fn refract_integrations(handle:*mut c_void, request:*const c_char)->*mut c_char {
 let result=(||->RefractResult<serde_json::Value>{
  let store=&mut unsafe{state(handle)?}.store;
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Request{action:String,#[serde(default)]payload:serde_json::Value}
  let text=c_str(request,"Integration request")?;if text.len()>1_700_000{return Err(RefractError::invalid("Integration request too large"));}
  let q:Request=serde_json::from_str(text).map_err(|_|RefractError::invalid("Invalid integration request"))?;
  fn decode<T:serde::de::DeserializeOwned>(v:serde_json::Value)->RefractResult<T>{serde_json::from_value(v).map_err(|e|RefractError::invalid(e.to_string()))}
  fn value<T:serde::Serialize>(v:T)->RefractResult<serde_json::Value>{serde_json::to_value(v).map_err(|e|RefractError::internal(e.to_string()))}
  match q.action.as_str(){
   "catalog"=>value(store.integration_catalog()?),
   "policy"=>value(store.integration_set_policy(&decode(q.payload)?)?),
   "email_copies"=>value(store.integration_email_copies()?),
   "email_delete"=>{let id:String=decode(q.payload)?;value(store.integration_email_delete(&id)?)},
   "email_preview"=>value(store.integration_email_preview(&decode(q.payload)?)?),
   "email_import"=>value(store.integration_email_import(&decode(q.payload)?)?),
   "calendar_candidates"=>value(store.integration_calendar_candidates()?),
   "calendar_preview"=>value(store.integration_calendar_preview(&decode(q.payload)?)?),
   "calendar_export"=>value(store.integration_calendar_export(&decode(q.payload)?)?),
   "verify_local_proof"=>{
    #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Input{proof:crypto_provenance::MerkleProof,expected_root:String,expected_evidence_sha256:String,expected_leaf_count:usize}
    let i:Input=decode(q.payload)?;
    value(serde_json::json!({"consistent":crypto_provenance::verify_bound_proof(&i.proof,&i.expected_root,&i.expected_evidence_sha256,i.expected_leaf_count),"statement":"Consistency with independently supplied values only; not identity, trusted time, append-only history or legal authenticity."}))
   },
   _=>Err(RefractError::invalid("Unsupported integration action; no account/OS connection was established")),
  }
 })();to_json(result).into_raw()
}

#[cfg(test)]
mod integration_abi_tests {
 use super::*;
 fn call(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value{let q=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();let p=unsafe{refract_integrations(h,q.as_ptr())};let result:serde_json::Value=serde_json::from_str(unsafe{CStr::from_ptr(p)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(p)};result}
 #[test]fn optional_adapters_are_denied_by_default_and_reviewed_copy_uses_owned_abi(){let dir=std::env::temp_dir().join(format!("refract-integrations-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("test.db").to_string_lossy().as_bytes()).unwrap();let h=unsafe{refract_open(path.as_ptr())};assert!(!h.is_null());let catalog=call(h,"catalog",serde_json::Value::Null);assert_eq!(catalog["ok"],true);assert!(catalog["payload"].as_array().unwrap().iter().all(|c|c["policy"]["enabled"]==false));assert_eq!(call(h,"policy",serde_json::json!({"connector_id":"gmail","enabled":true,"categories":["receipt"]}))["ok"],false);let mut input=serde_json::json!({"raw":"From: private@example.test\r\nContent-Type: text/plain\r\n\r\nSelected email body.","category":"receipt"});assert_eq!(call(h,"email_preview",input.clone())["ok"],false);assert_eq!(call(h,"policy",serde_json::json!({"connector_id":"selected_email","enabled":true,"categories":["receipt"]}))["ok"],true);assert_eq!(call(h,"email_preview",serde_json::json!({"raw":input["raw"]}))["ok"],false);let preview=call(h,"email_preview",input.clone());assert_eq!(preview["ok"],true);assert!(!preview["payload"]["copy_text"].as_str().unwrap().contains("private@example.test"));assert_eq!(call(h,"email_import",input.clone())["ok"],false);input["review_hash"]=preview["payload"]["review_hash"].clone();let imported=call(h,"email_import",input);assert_eq!(imported["ok"],true);assert_eq!(imported["payload"]["source_type"],"email_copy");assert_eq!(call(h,"email_delete",imported["payload"]["id"].clone())["ok"],true);assert_eq!(call(h,"connect_provider",serde_json::Value::Null)["ok"],false);assert_eq!(call(std::ptr::null_mut(),"catalog",serde_json::Value::Null)["ok"],false);unsafe{refract_close(h)};std::fs::remove_dir_all(dir).unwrap();}
}

/// Explicitly approved web session, staging, listing and deletion. This call
/// may block on DNS/network and must never execute on the UI thread.
#[no_mangle]
pub unsafe extern "C" fn refract_web(handle:*mut c_void, request:*const c_char)->*mut c_char {
 let result=(||->RefractResult<serde_json::Value>{
  #[derive(serde::Deserialize)] #[serde(deny_unknown_fields)] struct Request { action:String, payload:serde_json::Value }
  let text=c_str(request,"Web request")?;
  if text.len()>32*1024 { return Err(RefractError::invalid("Web request too large")); }
  let q:Request=serde_json::from_str(text).map_err(|_|RefractError::invalid("Invalid web request"))?;
  let store=&mut unsafe{state(handle)?}.store;
  web_bridge::dispatch(store,&q.action,q.payload)
 })();
 to_json(result).into_raw()
}

/// Explicit local capture. JSON request with action preview/commit. Caller owns
/// and must free the returned envelope. A handle must not be used concurrently;
/// Flutter's worker opens a separate connection for each operation.
#[no_mangle]
pub unsafe extern "C" fn refract_capture(handle:*mut c_void, request:*const c_char)->*mut c_char {
 let result=(||->RefractResult<serde_json::Value>{
  let store=&mut unsafe{state(handle)?}.store;
  #[derive(serde::Deserialize)] #[serde(deny_unknown_fields)]
  struct Request { action:String, payload:serde_json::Value }
  let text=c_str(request,"Capture request")?;
  // Covers worst-case escaped 2 MiB text and a base64-encoded 10 MiB PDF.
  if text.len()>16*1024*1024 { return Err(RefractError::invalid("Capture request too large")); }
  let q:Request=serde_json::from_str(text).map_err(|_|RefractError::invalid("Invalid capture request or unsupported format"))?;
  fn decode<T:serde::de::DeserializeOwned>(v:serde_json::Value)->RefractResult<T>{serde_json::from_value(v).map_err(|_|RefractError::invalid("Invalid capture payload or unsupported format"))}
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Enqueue{id:String,draft:personal_memory::capture::CaptureDraft,persist_approved:bool}
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Id{id:String}
  #[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Page{limit:u32,offset:u32}

  match q.action.as_str() {
   "preview"=>serde_json::to_value(store.capture_preview(&decode(q.payload)?)?).map_err(|e|RefractError::internal(e.to_string())),
   "commit"=>serde_json::to_value(store.capture_commit(&decode(q.payload)?)?).map_err(|e|RefractError::internal(e.to_string())),
   "enqueue"=>{let i:Enqueue=decode(q.payload)?;if !i.persist_approved{return Err(RefractError::invalid("Explicit durable-staging approval is required"));}serde_json::to_value(store.capture_enqueue(&i.id,&i.draft)?).map_err(|e|RefractError::internal(e.to_string()))},
   "jobs"=>{let p:Page=decode(q.payload)?;Ok(serde_json::json!({"jobs":store.capture_jobs(p.limit,p.offset)?}))},
   "job"=>{let i:Id=decode(q.payload)?;serde_json::to_value(store.capture_job(&i.id)?).map_err(|e|RefractError::internal(e.to_string()))},
   "run"=>{let i:Id=decode(q.payload)?;serde_json::to_value(store.capture_run(&i.id)?).map_err(|e|RefractError::internal(e.to_string()))},
   "cancel"=>{let i:Id=decode(q.payload)?;serde_json::to_value(store.capture_cancel(&i.id)?).map_err(|e|RefractError::internal(e.to_string()))},
   _=>Err(RefractError::invalid("Unsupported capture action; no network fetch or background job was started")),
  }
 })();
 to_json(result).into_raw()
}

#[cfg(test)] mod capture_bridge_tests {
 use super::*;
 fn read(p:*mut c_char)->serde_json::Value { let v=serde_json::from_str(unsafe{CStr::from_ptr(p)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(p)};v }
 unsafe fn call(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value {let q=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();read(unsafe{refract_capture(h,q.as_ptr())})}
 #[test] fn capture_json_abi_reviews_before_save_and_rejects_unsupported_requests() {
  let dir=std::env::temp_dir().join(format!("refract-capture-ffi-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("a.db").to_str().unwrap()).unwrap();
  unsafe { let h=refract_open(path.as_ptr());assert!(!h.is_null());
   let mut draft=serde_json::json!({"format":"markdown","text":"# Reviewed Markdown\n\n1 < 2 > 0"});assert_eq!(call(h,"commit",draft.clone())["ok"],false);
   let preview=call(h,"preview",draft.clone());assert_eq!(preview["ok"],true,"{preview}");assert!(read(refract_list_items(h,100,0))["payload"].as_array().unwrap().is_empty());
   draft["review_hash"]=preview["payload"]["review_hash"].clone();let saved=call(h,"commit",draft.clone());assert_eq!(saved["ok"],true,"{saved}");assert_eq!(saved["payload"]["item"]["source_type"],"markdown");assert_eq!(call(h,"commit",draft.clone())["ok"],false);
   for (action,payload) in [("fetch",draft.clone()),("preview",serde_json::json!({"format":"docx","text":"bad"})),("preview",serde_json::json!({"format":"text","text":"bad","account_token":"forbidden"}))] {assert_eq!(call(h,action,payload)["ok"],false);}
   let q=CString::new("not json").unwrap();assert_eq!(read(refract_capture(h,q.as_ptr()))["ok"],false);assert_eq!(read(refract_capture(std::ptr::null_mut(),q.as_ptr()))["ok"],false);assert_eq!(read(refract_capture(h,std::ptr::null()))["ok"],false);refract_close(h);
  }std::fs::remove_dir_all(dir).unwrap();
 }
 #[test] fn legacy_binary_pdf_abi_roundtrips_original_and_checks_length_before_slice() {
  let dir=std::env::temp_dir().join(format!("refract-pdf-ffi-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("a.db").to_str().unwrap()).unwrap();let bytes=include_bytes!("../../../shared/fixtures/capture/compressed-text.pdf");
  unsafe {let h=refract_open(path.as_ptr());assert!(!h.is_null());assert_eq!(read(refract_import_pdf(h,bytes.as_ptr(),usize::MAX,std::ptr::null()))["ok"],false);
   let result=read(refract_import_pdf(h,bytes.as_ptr(),bytes.len(),std::ptr::null()));assert_eq!(result["ok"],true,"{result}");let id=result["payload"]["id"].as_str().unwrap();assert_eq!(std::fs::read(dir.join("a.blobs").join(format!("{id}.original"))).unwrap(),bytes);assert!(result["payload"]["blocks"].as_array().unwrap().iter().any(|b|b["text"].as_str().unwrap().contains("Binary PDF capture regression")));refract_close(h);
  }std::fs::remove_dir_all(dir).unwrap();
 }
}

#[cfg(test)] mod capture_job_bridge_tests {
 use super::*;
 unsafe fn call(h:*mut c_void,action:&str,payload:serde_json::Value)->serde_json::Value {
  let q=CString::new(serde_json::json!({"action":action,"payload":payload}).to_string()).unwrap();let p=unsafe{refract_capture(h,q.as_ptr())};let value=serde_json::from_str(unsafe{CStr::from_ptr(p)}.to_str().unwrap()).unwrap();unsafe{refract_free_string(p)};value
 }
 #[test] fn durable_abi_requires_approval_and_reuses_the_completed_job() {
  let dir=std::env::temp_dir().join(format!("refract-jobs-ffi-{}",uuid::Uuid::new_v4()));std::fs::create_dir_all(&dir).unwrap();let path=CString::new(dir.join("a.db").to_str().unwrap()).unwrap();
  unsafe {let h=refract_open(path.as_ptr());assert!(!h.is_null());let mut draft=serde_json::json!({"format":"text","text":"Approved queue source"});let preview=call(h,"preview",draft.clone());draft["review_hash"]=preview["payload"]["review_hash"].clone();let id="native-approved-job-123456";
   assert_eq!(call(h,"enqueue",serde_json::json!({"id":id,"draft":draft,"persist_approved":false}))["ok"],false);
   assert_eq!(call(h,"enqueue",serde_json::json!({"id":id,"draft":draft}))["ok"],false);
   assert_eq!(call(h,"jobs",serde_json::json!({"limit":100,"offset":0}))["payload"]["jobs"].as_array().unwrap().len(),0);
   assert_eq!(call(h,"enqueue",serde_json::json!({"id":id,"draft":draft,"persist_approved":true}))["payload"]["status"],"queued");
   let first=call(h,"run",serde_json::json!({"id":id}));assert_eq!(first["payload"]["status"],"completed","{first}");let second=call(h,"run",serde_json::json!({"id":id}));assert_eq!(first["payload"]["result_item_id"],second["payload"]["result_item_id"]);assert_eq!(call(h,"cancel",serde_json::json!({"id":id}))["ok"],false);refract_close(h);
  }std::fs::remove_dir_all(dir).unwrap();
 }
}
