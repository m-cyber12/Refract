//! Local hybrid Recall: FTS, versioned concept vectors, metadata, entities,
//! project context, relationships, and explicit capture-time filters.
//! Assistant output is extractive only. Scores are not probabilities of truth.
use crate::Store;
use refract_core::{Item, RefractError, RefractResult};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

const ENCODER: &str = "local-concepts-hash-v1";
const DIM: usize = 256;
const CORPUS_LIMIT: u32 = 5000;

#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct RecallRequest {
    pub query: String,
    pub mode: String,
    pub item_ids: Vec<String>,
    pub source_type: Option<String>,
    pub source_url: Option<String>,
    pub author: Option<String>,
    pub entity: Option<String>,
    pub project_id: Option<String>,
    pub captured_after: Option<i64>,
    pub captured_before: Option<i64>,
    pub context_item_id: Option<String>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RecallEvidence {
    pub item_id: String,
    pub title: String,
    pub source_url: Option<String>,
    pub block_idx: Option<u32>,
    pub quote: String,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RecallHit {
    pub item_id: String,
    pub title: String,
    pub source_type: String,
    pub captured_ts: i64,
    pub score: f64,
    pub reasons: Vec<String>,
    pub evidence: RecallEvidence,
    pub supporting_passages: Vec<RecallEvidence>,
}

#[derive(Debug, Serialize)]
pub struct RecallResponse {
    pub query: String,
    pub mode: String,
    pub answer: String,
    pub answer_kind: String,
    pub model_used: bool,
    pub encoder: String,
    pub hits: Vec<RecallHit>,
    pub decision_records: Vec<crate::knowledge::DecisionRecord>,
    pub connections: Vec<crate::smart_memory::Relationship>,
    pub timeline: Vec<crate::smart_memory::TimelineEntry>,
    pub limitations: Vec<String>,
    pub scanned_items: usize,
}

// Small explicit concept dictionary: deliberately auditable, not neural AI.
fn normalize(text: &str) -> String {
    text.to_lowercase()
        .replace("artificial intelligence", " intelligence ")
        .replace("machine learning", " intelligence ")
        .replace("local-first", " localfirst ")
        .replace("local first", " localfirst ")
        .replace("offline-first", " localfirst ")
        .replace("data protection", " privacy ")
        .replace("digital identity", " identity ")
}
fn terms(text: &str) -> BTreeSet<String> {
    normalize(text).split(|c: char| !c.is_alphanumeric()).filter_map(|s| {
        let s = match s {
            "ai" | "llm" | "models" => "intelligence",
            "cipher" | "encrypted" | "cryptography" | "encrypt" => "encryption",
            "renew" | "renewals" | "renewing" => "renewal",
            "subscriptions" => "subscription",
            "private" | "gdpr" => "privacy",
            "invoices" | "receipts" => "receipt",
            "documents" => "document",
            x => x,
        };
        let stop = ["find", "that", "the", "i", "my", "me", "a", "an", "about", "where", "was", "is", "are", "of", "and", "or", "to", "in", "on", "for", "with", "it", "saved", "save", "show", "what", "did", "have", "containing", "remember", "reading", "something", "please", "everything", "connected", "project", "article", "document", "pdf", "note", "from", "recent", "recently", "latest", "last", "week", "month"];
        if s.len() < 2 || stop.contains(&s) { None } else { Some(s.to_string()) }
    }).take(128).collect()
}
fn vector(text: &str) -> Vec<f64> {
    let mut v = vec![0.0_f64; DIM];
    for term in terms(text) {
        let hash = Sha256::digest(term.as_bytes());
        let slot = u16::from_le_bytes([hash[0], hash[1]]) as usize % DIM;
        v[slot] += if hash[2] & 1 == 0 { 1.0 } else { -1.0 };
    }
    let norm = v.iter().map(|x| x*x).sum::<f64>().sqrt();
    if norm > 0.0 { for x in &mut v { *x /= norm; } }
    v
}
fn overlap(q: &BTreeSet<String>, text: &str) -> f64 {
    if q.is_empty() { return 0.0; }
    let t = terms(text);
    q.intersection(&t).count() as f64 / q.len() as f64
}
fn raw_terms(text: &str) -> BTreeSet<String> {
    text.to_lowercase().split(|c: char| !c.is_alphanumeric())
        .filter(|s| s.len() > 1).map(str::to_string).collect()
}
fn passage(text: &str, query: &BTreeSet<String>) -> String {
    if text.chars().count() <= 600 { return text.to_string(); }
    // Return a contiguous original substring; never manufacture a quotation.
    let mut lower = String::new();
    let mut original_char = Vec::new();
    for (index, character) in text.chars().enumerate() {
        let folded = character.to_lowercase().collect::<String>();
        original_char.extend(std::iter::repeat_n(index, folded.len()));
        lower.push_str(&folded);
    }
    let mut needles = query.iter().map(String::as_str).collect::<Vec<_>>();
    for (term, aliases) in [
        ("intelligence", vec!["machine learning", "artificial intelligence", " ai ", "llm"]),
        ("privacy", vec!["gdpr", "data protection", "private"]),
        ("encryption", vec!["encrypted", "cryptography", "cipher"]),
        ("localfirst", vec!["local-first", "local first", "offline-first"]),
        ("renewal", vec!["renew", "renewals", "renewing"]),
    ] {
        if query.contains(term) { needles.extend(aliases); }
    }
    let position = needles.iter().filter_map(|t| lower.find(*t)).min().unwrap_or(0);
    let at = original_char.get(position).copied().unwrap_or(0).saturating_sub(100);
    text.chars().skip(at).take(600).collect()
}
fn storage(e: impl std::fmt::Display) -> RefractError { RefractError::storage(e.to_string()) }

impl Store {
    pub fn recall_index_item(&self, id: &str) -> RefractResult<()> {
        let item = self.get_item(id)?.ok_or_else(|| RefractError::invalid("item not found"))?;
        for block in &item.blocks {
            let hash = format!("{:x}", Sha256::digest(block.text.as_bytes()));
            let current: Option<(String, String)> = self.conn.query_row(
                "SELECT encoder, text_hash FROM recall_vectors WHERE item_id=?1 AND block_idx=?2",
                params![id, block.idx], |r| Ok((r.get(0)?, r.get(1)?)),
            ).optional().map_err(storage)?;
            if current.as_ref() == Some(&(ENCODER.to_string(), hash.clone())) { continue; }
            self.conn.execute(
                "INSERT INTO recall_vectors (item_id, block_idx, encoder, text_hash, vector_json) VALUES (?1,?2,?3,?4,?5)
                 ON CONFLICT(item_id,block_idx) DO UPDATE SET encoder=excluded.encoder,text_hash=excluded.text_hash,vector_json=excluded.vector_json",
                params![id, block.idx, ENCODER, hash, serde_json::to_string(&vector(&block.text)).map_err(storage)?],
            ).map_err(storage)?;
        }
        self.conn.execute("DELETE FROM recall_vectors WHERE item_id=?1 AND block_idx NOT IN (SELECT idx FROM blocks WHERE item_id=?1)", params![id]).map_err(storage)?;
        Ok(())
    }

    pub fn recall_rebuild_index(&self) -> RefractResult<usize> {
        let tx = self.conn.unchecked_transaction().map_err(storage)?;
        let ids = {
            let mut stmt = self.conn.prepare("SELECT id FROM items ORDER BY id").map_err(storage)?;
            let rows = stmt.query_map([], |r| r.get::<_, String>(0)).map_err(storage)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(storage)?
        };
        self.conn.execute("DELETE FROM recall_vectors", []).map_err(storage)?;
        for id in &ids { self.recall_index_item(id)?; }
        tx.commit().map_err(storage)?;
        Ok(ids.len())
    }

    pub fn recall(&self, request: &RecallRequest) -> RefractResult<RecallResponse> {
        if request.query.chars().count() > 2000 || request.item_ids.len() > 20 {
            return Err(RefractError::invalid("query exceeds 2000 characters or selection exceeds 20 items"));
        }
        if let (Some(a), Some(b)) = (request.captured_after, request.captured_before) {
            if a > b { return Err(RefractError::invalid("capture date range is reversed")); }
        }
        let mode = if request.mode.is_empty() { "find" } else { request.mode.as_str() };
        if !["find", "answer", "summarize", "compare", "connections", "timeline"].contains(&mode) {
            return Err(RefractError::invalid("unsupported assistant mode"));
        }
        if ["summarize", "compare"].contains(&mode) && request.item_ids.is_empty() {
            return Err(RefractError::invalid("select source documents first"));
        }
        if mode == "compare" && request.item_ids.iter().collect::<BTreeSet<_>>().len() < 2 {
            return Err(RefractError::invalid("comparison needs at least two distinct sources"));
        }
        let q = request.query.trim();
        let query_terms = terms(q);
        let qv = vector(q);
        let lower = q.to_lowercase();
        let inferred_type = if lower.split_whitespace().any(|w| w.trim_matches(|c:char| !c.is_alphanumeric()) == "pdf") { Some("pdf") } else { None };
        let source_type = request.source_type.as_deref().filter(|s| !s.is_empty()).or(inferred_type);
        if let Some(t) = source_type {
            if !["url", "shared_text", "html", "pdf", "markdown", "text", "file"].contains(&t) { return Err(RefractError::invalid("invalid source type")); }
        }
        let has_filters = source_type.is_some() || request.project_id.is_some() || request.source_url.is_some() || request.author.is_some() || request.entity.is_some() || request.captured_after.is_some() || request.captured_before.is_some();
        let mut limitations = vec![
            "Local extractive retrieval. Concept vectors use a small English synonym dictionary and feature hashing, not a neural embedding model.".into(),
            "Quotes are evidence of what a source says, not verification of its claims. No generated interpretation is presented as fact.".into(),
        ];
        // Explicit IDs avoid corpus truncation for user-selected sources.
        let corpus: Vec<Item> = if !request.item_ids.is_empty() {
            let mut v = Vec::new();
            for id in request.item_ids.iter().collect::<BTreeSet<_>>() {
                v.push(self.get_item(id)?.ok_or_else(|| RefractError::invalid(format!("selected source not found: {id}")))?);
            }
            v
        } else {
            let mut stmt = self.conn.prepare("SELECT id FROM items ORDER BY id LIMIT ?1").map_err(storage)?;
            let ids = stmt.query_map(params![CORPUS_LIMIT + 1], |r| r.get::<_, String>(0)).map_err(storage)?
                .collect::<Result<Vec<_>,_>>().map_err(storage)?;
            if ids.len() > CORPUS_LIMIT as usize { limitations.push("Only the first 5000 items by ID were scanned. Narrow to selected sources for items outside this window.".into()); }
            let mut v = Vec::new();
            for id in ids.into_iter().take(CORPUS_LIMIT as usize) {
                if let Some(item) = self.get_item(&id)? { v.push(item); }
            }
            v
        };
        let scanned = corpus.len();
        // Safe FTS MATCH expression: OR across normalized terms, quoted literals.
        let fts: BTreeSet<String> = if query_terms.is_empty() { BTreeSet::new() } else {
            let expr = query_terms.iter().map(|s| format!("\"{}\"", s.replace('"', ""))).collect::<Vec<_>>().join(" OR ");
            let mut stmt = self.conn.prepare("SELECT DISTINCT b.item_id FROM blocks_fts JOIN blocks b ON b.id=blocks_fts.rowid WHERE blocks_fts MATCH ?1").map_err(storage)?;
            let ids = stmt.query_map(params![expr], |r| r.get::<_,String>(0)).map_err(storage)?
                .collect::<Result<BTreeSet<_>,_>>().map_err(storage)?;
            ids
        };
        let context_links = if let Some(id) = &request.context_item_id { self.list_relationships(Some(id), 1000)? } else { Vec::new() };
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(storage)?.as_secs() as i64;
        let recent = ["recent", "recently", "latest"].iter().any(|w| lower.split_whitespace().any(|s| s == *w));
        let natural_after = if lower.contains("last week") { Some(now - 7*86400) } else if lower.contains("last month") { Some(now - 30*86400) } else { None };
        if natural_after.is_some() && request.captured_after.is_none() {
            limitations.push("Interpreted 'last week/month' as a rolling 7/30-day capture-time window, not publication time.".into());
        }
        limitations.push("Stored-connection traversal is capped at 1000 links; retrieval scans at most 5000 items and returns at most 50 hits.".into());
        let mut hits = Vec::new();
        let mut decision_source_ids = BTreeSet::new();
        for item in corpus {
            if request.context_item_id.as_deref() == Some(&item.id) { continue; }
            if source_type.is_some_and(|t| t != item.source_type.as_str()) { continue; }
            if request.source_url.as_ref().is_some_and(|url| item.source_url.as_ref() != Some(url)) { continue; }
            if request.author.as_ref().is_some_and(|a| item.author.as_ref().map(|s| s.to_lowercase()) != Some(a.to_lowercase())) { continue; }
            if request.captured_after.or(natural_after).is_some_and(|ts| item.import_ts < ts) || request.captured_before.is_some_and(|ts| item.import_ts > ts) { continue; }
            let mut reasons = Vec::new();
            let projects = self.item_project_names(&item.id, request.project_id.as_deref())?;
            if request.project_id.is_some() && projects.is_empty() { continue; }
            let entity_names = self.item_entity_names(&item.id)?;
            if request.entity.as_ref().is_some_and(|e| !entity_names.iter().any(|n| n.eq_ignore_ascii_case(e))) { continue; }
            decision_source_ids.insert(item.id.clone());
            let title = item.title.clone().unwrap_or_else(|| "Untitled source".into());
            let metadata = format!("{} {} {} {}", title, item.author.as_deref().unwrap_or(""), projects.join(" "), entity_names.join(" "));
            let meta_score = overlap(&query_terms, &metadata);
            let exact_url = item.source_url.as_deref().is_some_and(|u| !u.is_empty() && q.contains(u));
            let fts_match = fts.contains(&item.id);
            if fts_match { reasons.push("Full-text match in source blocks".into()); }
            if meta_score > 0.0 { reasons.push("Matching title, author, project or entity".into()); }
            if exact_url { reasons.push("Exact source URL present in query".into()); }
            let link = context_links.iter().filter(|r| r.source_item_id == item.id || r.target_item_id == item.id).max_by(|a,b| a.confidence.total_cmp(&b.confidence));
            let link_score = link.map(|r| r.confidence).unwrap_or(0.0);
            if let Some(r) = link { reasons.push(format!("Context relationship (suggestion): {}", r.basis)); }
            let pinned: i64 = self.conn.query_row("SELECT COUNT(*) FROM item_topics it JOIN topics t ON t.id=it.topic_id WHERE it.item_id=?1 AND t.pinned=1", params![item.id], |r| r.get(0)).map_err(storage)?;
            self.recall_index_item(&item.id)?;
            let mut best: Option<(f64, u32, String)> = None;
            for block in &item.blocks {
                let stored: String = self.conn.query_row("SELECT vector_json FROM recall_vectors WHERE item_id=?1 AND block_idx=?2", params![item.id,block.idx], |r| r.get(0)).map_err(storage)?;
                let v: Vec<f64> = serde_json::from_str(&stored).map_err(storage)?;
                if v.len() != DIM || v.iter().any(|x| !x.is_finite()) { return Err(RefractError::storage("invalid Recall vector; rebuild the derived index")); }
                // Require actual normalized concept overlap: hashing collisions alone never justify a hit.
                let concept = overlap(&query_terms, &block.text);
                let cosine = if concept > 0.0 { qv.iter().zip(v).map(|(a,b)| a*b).sum::<f64>().max(0.0) } else { 0.0 };
                let lexical_q = raw_terms(q).into_iter().filter(|s| query_terms.contains(s)).collect::<BTreeSet<_>>();
                let lexical = if lexical_q.is_empty() { 0.0 } else { lexical_q.intersection(&raw_terms(&block.text)).count() as f64 / lexical_q.len() as f64 };
                let relevance = concept * 0.55 + cosine * 0.25 + lexical * 0.20;
                if best.as_ref().is_none_or(|b| relevance > b.0) { best = Some((relevance, block.idx, block.text.clone())); }
            }
            let block_score = best.as_ref().map(|b| b.0).unwrap_or(0.0);
            let selection = !request.item_ids.is_empty();
            if !selection && !has_filters && block_score == 0.0 && meta_score == 0.0 && !exact_url && link_score == 0.0 { continue; }
            if !selection && !query_terms.is_empty() && block_score == 0.0 && meta_score == 0.0 && !exact_url && link_score == 0.0 { continue; }
            if block_score > 0.0 { reasons.push("Local concept-vector / passage match".into()); }
            if pinned > 0 { reasons.push("User-pinned topic (small ranking boost)".into()); }
            if selection { reasons.push("Explicitly selected source".into()); }
            if has_filters { reasons.push("Matches explicit metadata / capture-time filters".into()); }
            let recency = if recent { 0.03 / (1.0 + ((now - item.import_ts).max(0) as f64 / 86400.0)) } else { 0.0 };
            if recent { reasons.push("Recency boost requested by query".into()); }
            let quality = f64::from(item.extraction_confidence.clamp(0.0, 1.0));
            let score = block_score * (0.54 + 0.06 * quality) + meta_score * 0.20 + if fts_match { 0.08 } else { 0.0 } + if exact_url { 0.5 } else { 0.0 } + link_score * 0.12 + if pinned > 0 { 0.02 } else { 0.0 } + recency + if selection || has_filters { 0.01 } else { 0.0 };
            let (block_idx, quote, kind) = if let Some((relevance,idx,text)) = best {
                let kind = if relevance > 0.0 || selection { "direct_quote" } else { "context_excerpt" };
                (Some(idx), passage(&text, &query_terms), kind.into())
            } else { (None, title.clone(), "metadata_only".into()) };
            let mut supporting_passages = Vec::new();
            if ["summarize", "compare"].contains(&mode) {
                // An extractive summary takes one short, verbatim sentence from
                // up to three source blocks, with individual citations.
                for block in item.blocks.iter().filter(|b| !b.text.trim().is_empty()).take(3) {
                    let sentence = block.text.split_inclusive(['.', '!', '?', '\n']).find(|s| !s.trim().is_empty()).unwrap_or(&block.text);
                    supporting_passages.push(RecallEvidence { item_id: item.id.clone(), title: title.clone(), source_url: item.source_url.clone(), block_idx: Some(block.idx), quote: sentence.chars().take(600).collect(), kind: "direct_quote".into() });
                }
            }
            hits.push(RecallHit {
                item_id: item.id.clone(), title: title.clone(), source_type: item.source_type.as_str().into(), captured_ts: item.import_ts,
                score, reasons, supporting_passages, evidence: RecallEvidence { item_id: item.id, title, source_url: item.source_url, block_idx, quote, kind },
            });
        }
        hits.sort_by(|a,b| b.score.total_cmp(&a.score).then(a.item_id.cmp(&b.item_id)));
        hits.truncate(request.limit.unwrap_or(12).clamp(1,50) as usize);
        let ids: BTreeSet<_> = hits.iter().map(|h| h.item_id.as_str()).collect();
        let connections = if mode == "connections" {
            self.list_relationships(None, 1000)?.into_iter().filter(|r| ids.contains(r.source_item_id.as_str()) || ids.contains(r.target_item_id.as_str())).collect()
        } else { Vec::new() };
        let timeline = if mode == "timeline" {
            self.recall_timeline(&ids)?
        } else { Vec::new() };
        let quote_count = hits.iter().filter(|h| h.evidence.kind == "direct_quote").count();
        let mut decision_records=if !q.is_empty()&&["find","answer"].contains(&mode){self.decision_search(&crate::knowledge::DecisionQuery{query:q.into(),project_id:request.project_id.clone(),include_archived:false})?}else{Vec::new()};
        if source_type.is_some()||request.source_url.is_some()||request.author.is_some()||request.entity.is_some()||request.captured_after.is_some()||request.captured_before.is_some()||natural_after.is_some()||!request.item_ids.is_empty(){
            decision_records.retain(|d|d.source_ids.iter().any(|id|decision_source_ids.contains(id)));
            limitations.push("With source filters, decisions must reference at least one matching source in the bounded scan. Capture-date filters refer to source capture time, not the decision date.".into());
        }
        let answer_kind=if decision_records.is_empty(){"extractive_evidence"}else if hits.is_empty(){"user_recorded_decision"}else{"source_excerpts_and_user_records"};
        let answer = if !decision_records.is_empty() {
            format!("Found {} explicitly recorded user decision(s). Their selected options, reasoning and supporting references are shown separately from source quotations. These are user records, not inferred beliefs or independent verification.",decision_records.len())
        } else if hits.is_empty() {
            "I could not find sufficient evidence in the scanned library. Try different terms or explicit source, project, entity or capture-date filters.".into()
        } else if mode == "compare" {
            "Source excerpts are shown separately for comparison. These passages do not establish agreement, contradiction, or completeness; no unsupported synthesis was generated.".into()
        } else if mode == "summarize" {
            "Extractive summary: short, verbatim passages from up to three blocks per selected document, with individual source citations. This is not a complete or abstractive summary.".into()
        } else if mode == "answer" {
            format!("Found {quote_count} source passage(s) relevant to this query. Review the quotations below; I cannot infer an answer beyond what these passages support.")
        } else if mode == "connections" {
            "Connections below are stored suggestions or user assertions. Their basis and score do not establish factual relationships.".into()
        } else if mode == "timeline" {
            "Source-backed timestamps for retrieved items. Capture dates, content-date candidates and explicit user dates remain separate.".into()
        } else { format!("Found {} matching source(s). Ranking balances passages, metadata, source extraction quality, pinned topics and contextual connections, not recency alone.", hits.len()) };
        if quote_count == 0 && !hits.is_empty() { limitations.push("No passage matching the query was found. Metadata matches or source excerpts may provide context, but do not support a factual answer to the question.".into()); }
        if mode == "compare" && hits.len() < 2 { limitations.push("Fewer than two selected sources survived the filters; comparison evidence is incomplete.".into()); }
        Ok(RecallResponse { query: q.into(), mode: mode.into(), answer, answer_kind: answer_kind.into(), model_used: false, encoder: ENCODER.into(), hits, decision_records, connections, timeline, limitations, scanned_items: scanned })
    }

    fn item_project_names(&self, id: &str, project: Option<&str>) -> RefractResult<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT p.name FROM projects p JOIN project_items pi ON pi.project_id=p.id WHERE pi.item_id=?1 AND (?2 IS NULL OR p.id=?2)").map_err(storage)?;
        let rows = stmt.query_map(params![id,project], |r| r.get(0)).map_err(storage)?;
        rows.collect::<Result<Vec<_>,_>>().map_err(storage)
    }
    fn item_entity_names(&self, id: &str) -> RefractResult<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT e.name FROM entities e JOIN item_entities ie ON ie.entity_id=e.id WHERE ie.item_id=?1").map_err(storage)?;
        let rows = stmt.query_map(params![id], |r| r.get(0)).map_err(storage)?;
        rows.collect::<Result<Vec<_>,_>>().map_err(storage)
    }
    fn recall_timeline(&self, ids: &BTreeSet<&str>) -> RefractResult<Vec<crate::smart_memory::TimelineEntry>> {
        let mut out = Vec::new();
        for id in ids {
            let mut stmt = self.conn.prepare("SELECT COALESCE(i.title,i.id),t.kind,t.ts,t.note FROM item_times t JOIN items i ON i.id=t.item_id WHERE t.item_id=?1").map_err(storage)?;
            let rows = stmt.query_map(params![id], |r| Ok(crate::smart_memory::TimelineEntry { item_id: id.to_string(), title: r.get(0)?, time_kind: r.get(1)?, ts: r.get(2)?, note: r.get(3)? })).map_err(storage)?;
            out.extend(rows.collect::<Result<Vec<_>,_>>().map_err(storage)?);
        }
        out.sort_by_key(|e| e.ts);
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use refract_core::{Block, BlockKind, ImportStatus, SourceType};
    fn add(store: &mut Store, id: &str, text: &str, ts: i64) {
        store.insert_item(&Item {
            id: id.into(), source_url: Some(format!("https://example.org/{id}")), source_type: SourceType::Text,
            import_ts: ts, content_hash: id.into(), title: Some(format!("Source {id}")), author: Some("Alice".into()),
            language: Some("en".into()), extraction_confidence: 0.9, status: ImportStatus::Ready,
            blocks: vec![Block { idx: 0, kind: BlockKind::Paragraph, text: text.into() }],
        }, text.as_bytes(), id).unwrap();
    }
    fn request(q: &str) -> RecallRequest { RecallRequest { query: q.into(), ..Default::default() } }
    #[test]
    fn approximate_language_and_source_quotes() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "old", "GDPR governs data protection in machine learning.", 100);
        add(&mut s, "new", "A recent recipe for soup.", 200);
        let r = s.recall(&request("Find that article I saved about AI privacy.")).unwrap();
        assert_eq!(r.hits[0].item_id, "old");
        assert_eq!(r.hits[0].evidence.quote, "GDPR governs data protection in machine learning.");
        assert_eq!(r.hits[0].evidence.block_idx, Some(0));
        assert!(!r.model_used);
        assert!(r.hits[0].reasons.iter().any(|s| s.contains("concept-vector")));
    }
    #[test]
    fn metadata_entity_and_capture_filters() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "An encrypted document dated 2026-03-01.", 100);
        add(&mut s, "b", "Cryptography protects files.", 200);
        let mut q = request("encryption");
        q.captured_before = Some(150);
        q.author = Some("Alice".into());
        q.entity = Some("2026-03-01".into());
        assert_eq!(s.recall(&q).unwrap().hits[0].item_id, "a");
        q.captured_after = Some(160);
        assert!(s.recall(&q).is_err());
        assert!(s.recall(&request("where was the PDF about encryption")).unwrap().hits.is_empty());
    }
    #[test]
    fn exact_sources_and_project_context() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "Unrelated text", 100);
        let p = s.create_project("REFRACT", None).unwrap();
        s.project_add_item(&p.id, "a").unwrap();
        assert_eq!(s.recall(&request("Show me everything connected to my REFRACT project")).unwrap().hits[0].item_id, "a");
        assert_eq!(s.recall(&request("https://example.org/a")).unwrap().hits[0].item_id, "a");
        let mut q = request(""); q.project_id = Some(p.id);
        assert_eq!(s.recall(&q).unwrap().hits.len(), 1);
    }
    #[test]
    fn unsupported_queries_cannot_manufacture_evidence() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "A recipe for soup.", 100);
        let mut q = request("quantum teleportation"); q.mode = "answer".into();
        let r = s.recall(&q).unwrap();
        assert!(r.hits.is_empty());
        assert!(r.answer.contains("could not find sufficient evidence"));
        assert!(s.recall(&request("\" OR * ; DROP TABLE items -- 中文🙂")).is_ok());
        assert!(s.get_item("a").unwrap().is_some());
    }
    #[test]
    fn selected_source_modes_and_no_modification() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "Privacy matters.", 100);
        add(&mut s, "b", "Encryption matters.", 200);
        let before = s.get_item("a").unwrap();
        let mut q = request(""); q.item_ids = vec!["a".into(), "b".into()]; q.mode = "compare".into();
        let r = s.recall(&q).unwrap();
        assert_eq!(r.hits.len(), 2);
        assert!(r.answer.contains("do not establish agreement"));
        assert_eq!(before, s.get_item("a").unwrap());
        q.mode = "summarize".into(); assert_eq!(s.recall(&q).unwrap().hits.len(), 2);
        q.item_ids = vec!["missing".into()]; assert!(s.recall(&q).is_err());
    }
    #[test]
    fn timeline_is_source_backed_and_time_kinds_separate() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "A privacy event on 2026-03-01", 100);
        s.set_item_time("a", "deadline", 200, Some("user supplied")).unwrap();
        let mut q = request("privacy"); q.mode = "timeline".into();
        let r = s.recall(&q).unwrap();
        for kind in ["capture", "event", "deadline"] { assert!(r.timeline.iter().any(|e| e.time_kind == kind)); }
        assert!(r.timeline.iter().all(|e| e.item_id == "a"));
    }
    #[test]
    fn context_traversal_respects_dismissal() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "Privacy GDPR.", 100);
        add(&mut s, "b", "Privacy data protection.", 200);
        let mut q = request(""); q.context_item_id = Some("a".into()); q.mode = "connections".into();
        let r = s.recall(&q).unwrap();
        assert_eq!(r.hits.len(), 1); assert_eq!(r.hits[0].item_id, "b");
        for link in r.connections { s.dismiss_relationship(&link.id).unwrap(); }
        assert!(s.recall(&q).unwrap().hits.is_empty());
    }
    #[test]
    fn vectors_rebuild_and_invalid_requests() {
        let mut s = Store::open_in_memory().unwrap();
        add(&mut s, "a", "Encryption", 100);
        s.conn.execute("UPDATE recall_vectors SET vector_json='[]'", []).unwrap();
        assert!(s.recall(&request("encryption")).is_err());
        assert_eq!(s.recall_rebuild_index().unwrap(), 1);
        assert_eq!(s.recall(&request("encryption")).unwrap().hits.len(), 1);
        let mut q = request("encryption"); q.mode = "invent".into(); assert!(s.recall(&q).is_err());
        q.mode = "compare".into(); q.item_ids = vec!["a".into(), "a".into()]; assert!(s.recall(&q).is_err());
    }
    #[test]
    fn long_unicode_passages_are_verbatim_substrings() {
        let text = format!("{} Encryption is supported. {}", "中文🙂 ".repeat(400), "İİİ ".repeat(400));
        let quote = passage(&text, &terms("encryption"));
        assert!(text.contains(&quote));
        assert!(quote.chars().count() <= 600);
        assert!(quote.contains("Encryption"));
        let text = format!("{} GDPR protects information.", "İ中文 ".repeat(400));
        let quote = passage(&text, &terms("privacy"));
        assert!(text.contains(&quote));
        assert!(quote.contains("GDPR"));
    }
    #[test]
    fn v5_upgrade_and_legacy_lazy_indexing() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        for migration in [crate::MIGRATION_0001, crate::MIGRATION_0002, crate::MIGRATION_0003, crate::MIGRATION_0004, crate::MIGRATION_0005] { conn.execute_batch(migration).unwrap(); }
        conn.execute("INSERT INTO items (id,source_type,import_ts,content_hash,title) VALUES ('legacy','text',100,'hash','SQLite guide')", []).unwrap();
        conn.execute("INSERT INTO blocks (item_id,idx,kind,text) VALUES ('legacy',0,'paragraph','SQLite stores local data.')", []).unwrap();
        let s = Store { conn, blob_dir: std::env::temp_dir().join(uuid::Uuid::new_v4().to_string()) };
        s.migrate().unwrap(); s.migrate().unwrap();
        let result = s.recall(&request("What did I save about SQLite?")).unwrap();
        assert_eq!(result.hits[0].item_id, "legacy");
        assert_eq!(result.hits[0].evidence.quote, "SQLite stores local data.");
    }

}
