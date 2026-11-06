//! Platform bridge: the versioned C ABI consumed by Flutter via `dart:ffi`.
//!
//! Rules (from the architecture docs):
//! - Never panic across the boundary; every call returns a JSON envelope
//!   `{"ok": true, "payload": ...}` or `{"ok": false, "error": {...}}`.
//! - All returned strings are owned by Rust and must be freed with
//!   `refract_free_string`.
//! - `refract_open` returns an opaque handle; `refract_close` releases it.

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
        let out = runtime().summarize(&item.blocks, max_sentences.max(1))?;
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
        let out = runtime().suggest_tags(&item.blocks, max_tags.max(1))?;
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
}
