//! Phase II master, Phase 3 — SMART MEMORY.
//!
//! Automatic organization (spec §5.2): topic identification and entity
//! extraction over captured items, always preferring existing topics and
//! avoiding meaningless tag sprawl. Semantic connections (spec §5.3): a
//! relationship engine where every link carries a human-readable basis and a
//! confidence level; weak similarity is only ever a *suggestion* and users
//! can inspect and remove connections. Memory Timeline (spec §5.4):
//! chronological view that strictly distinguishes capture / publication /
//! modification / event / deadline timestamps. Knowledge Evolution
//! (spec §5.5): per-topic development described from the information alone —
//! never inferring beliefs, positions, or identity. Project Spaces
//! (spec §13 of the phase list): named spaces grouping items with their own
//! timeline.
//!
//! Everything is rule-based and local. No telemetry, no cloud, no model
//! inference about the user.

use crate::Store;
use refract_core::{Item, RefractError, RefractResult};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;

fn now_ts() -> RefractResult<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| RefractError::storage(format!("clock: {e}")))?
        .as_secs() as i64)
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
pub struct Topic {
    pub id: String,
    pub name: String,
    pub origin: String,
    pub created_ts: i64,
    pub pinned: bool,
    pub item_count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Entity {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub created_ts: i64,
    pub item_count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Relationship {
    pub id: String,
    pub source_item_id: String,
    pub target_item_id: String,
    pub kind: String,
    pub basis: String,
    pub confidence: f64,
    pub dismissed: bool,
    pub created_ts: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct TimelineEntry {
    pub item_id: String,
    pub title: String,
    /// One of: capture | publication | modification | event | deadline.
    /// These are never conflated (spec §5.4).
    pub time_kind: String,
    pub ts: i64,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct EvolutionStage {
    pub from_ts: i64,
    pub to_ts: i64,
    pub item_count: i64,
    /// Plain description of the information collected in this window.
    pub description: String,
    pub item_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TopicEvolution {
    pub topic: Topic,
    pub stages: Vec<EvolutionStage>,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub created_ts: i64,
    pub item_count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrganizeReport {
    pub item_id: String,
    pub topics: Vec<String>,
    pub entities: Vec<String>,
    pub relationships_suggested: usize,
}

// ---------------------------------------------------------------------------
// Rule-based extraction helpers
// ---------------------------------------------------------------------------

/// Simple keyword → topic map. Deliberately small: prefer existing topics,
/// avoid hundreds of meaningless tags (spec §5.2).
fn topic_keywords() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        ("artificial intelligence", &["artificial intelligence", "machine learning", "neural network", "generative ai", "llm", "local inference", "deep learning"]),
        ("privacy", &["privacy", "surveillance", "gdpr", "data protection", "tracking"]),
        ("security", &["security", "encryption", "vulnerability", "zero trust", "tls"]),
        ("local-first software", &["local-first", "local first", "offline-first", "crdt", "sync"]),
        ("finance", &["invoice", "receipt", "payment", "tax", "budget", "expense"]),
        ("productivity", &["workflow", "task", "todo", "calendar", "meeting notes"]),
        ("hardware", &["cpu", "gpu", "raspberry pi", "microcontroller", "firmware"]),
        ("web development", &["javascript", "typescript", "html", "css", "react", "flutter", "rust wasm"]),
    ]
}

fn extract_topics(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut hits: Vec<(usize, String)> = Vec::new();
    for (topic, keywords) in topic_keywords() {
        let count = keywords.iter().filter(|k| lower.contains(**k)).count();
        if count > 0 {
            hits.push((count, topic.to_string()));
        }
    }
    hits.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    hits.into_iter().take(3).map(|(_, t)| t).collect()
}

fn extract_entities(text: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    // Emails
    for tok in text.split(|c: char| !c.is_ascii_graphic() && c != '.' && c != '@') {
        if tok.contains('@') && tok.contains('.') {
            let t = tok.trim_matches(|c: char| !c.is_ascii_graphic());
            if t.len() > 5 && !out.iter().any(|(n, _)| n == t) {
                out.push((t.to_string(), "email".to_string()));
            }
        }
    }
    // Inspect ASCII windows without slicing arbitrary UTF-8 boundaries.
    for window in text.as_bytes().windows(10) {
        if window.iter().enumerate().all(|(i, c)| {
            if i == 4 || i == 7 { *c == b'-' } else { c.is_ascii_digit() }
        }) {
            let d = std::str::from_utf8(window).unwrap();
            if parse_date(d).is_some() && !out.iter().any(|(n, _)| n == d) {
                out.push((d.to_string(), "date".to_string()));
            }
        }
    }
    // Capitalized bigrams → candidate organizations/places (heuristic).
    // Only surface candidates; confidence stays modest and links are
    // suggestions the user can remove (spec §5.3).
    let words: Vec<&str> = text.split_whitespace().collect();
    for w in words.windows(2) {
        let a = w[0].trim_matches(|c: char| !c.is_alphanumeric());
        let b = w[1].trim_matches(|c: char| !c.is_alphanumeric());
        if a.len() >= 3
            && b.len() >= 3
            && a.chars().next().map_or(false, |c| c.is_uppercase())
            && b.chars().next().map_or(false, |c| c.is_uppercase())
            && !a.chars().all(|c| c.is_uppercase())
        {
            let name = format!("{a} {b}");
            let kind = if ["inc", "ltd", "gmbh", "llc", "corp", "ag", "srl"]
                .iter()
                .any(|suf| b.to_lowercase() == *suf)
            {
                "organization"
            } else {
                "other"
            };
            if !out.iter().any(|(n, _)| n.eq_ignore_ascii_case(&name)) {
                out.push((name, kind.to_string()));
            }
            if out.iter().filter(|(_, k)| k == "other").count() >= 5 {
                break;
            }
        }
    }
    out.truncate(12);
    out
}

/// Parse "YYYY-MM-DD" to unix ts (UTC midnight). Minimal, no chrono dep.
fn parse_date(s: &str) -> Option<i64> {
    let mut p = s.split('-');
    let y: i64 = p.next()?.parse().ok()?;
    let m: i64 = p.next()?.parse().ok()?;
    let d: i64 = p.next()?.parse().ok()?;
    if !(1970..=2200).contains(&y) || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    if p.next().is_some() { return None; }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let max_day = match m { 2 => if leap { 29 } else { 28 }, 4 | 6 | 9 | 11 => 30, _ => 31 };
    if d > max_day { return None; }
    // Days from civil algorithm (Howard Hinnant).
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = if y2 >= 0 { y2 } else { y2 - 399 } / 400;
    let yoe = y2 - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some((era * 146097 + doe - 719468) * 86400)
}

// ---------------------------------------------------------------------------
// Store API
// ---------------------------------------------------------------------------

impl Store {
    fn body_of_item(&self, item_id: &str) -> RefractResult<String> {
        let mut stmt = self
            .conn
            .prepare("SELECT text FROM blocks WHERE item_id=?1 ORDER BY idx")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![item_id], |r| r.get::<_, String>(0))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut body = String::new();
        for r in rows {
            body.push_str(&r.map_err(|e| RefractError::storage(e.to_string()))?);
            body.push('\n');
        }
        Ok(body)
    }

    /// Automatic organization for one item (spec §5.2): identify main +
    /// secondary topics, extract entities, record temporal context, and
    /// suggest relationships. Always prefers existing topics/entities.
    pub fn organize_item(&mut self, item_id: &str) -> RefractResult<OrganizeReport> {
        let title: Option<String> = self
            .conn
            .query_row("SELECT title FROM items WHERE id=?1", params![item_id], |r| {
                r.get(0)
            })
            .map_err(|_| RefractError::invalid(format!("item not found: {item_id}")))?;
        let import_ts: i64 = self
            .conn
            .query_row("SELECT import_ts FROM items WHERE id=?1", params![item_id], |r| {
                r.get(0)
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let body = self.body_of_item(item_id)?;
        let text = format!("{}\n{}", title.clone().unwrap_or_default(), body);

        let topics = extract_topics(&text);
        let entities = extract_entities(&text);
        let now = now_ts()?;

        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;

        let mut topic_names = Vec::new();
        for (idx, name) in topics.iter().enumerate() {
            // Preserve explicit rename/merge/reject choices on re-organization.
            let rule: Option<Option<String>> = tx.query_row(
                "SELECT topic_id FROM topic_rules WHERE keyword_topic=?1", params![name], |r| r.get(0)
            ).optional().map_err(|e| RefractError::storage(e.to_string()))?;
            if let Some(mapped) = rule {
                if let Some(id) = mapped {
                    tx.execute("INSERT OR IGNORE INTO item_topics (item_id, topic_id, is_primary) VALUES (?1,?2,?3)", params![item_id, id, idx == 0])
                        .map_err(|e| RefractError::storage(e.to_string()))?;
                    let canonical: String = tx.query_row("SELECT name FROM topics WHERE id=?1", params![id], |r| r.get(0))
                        .map_err(|e| RefractError::storage(e.to_string()))?;
                    topic_names.push(canonical);
                }
                continue;
            }
            let id: String = tx
                .query_row(
                    "INSERT INTO topics (id, name, origin, created_ts)
                     VALUES (?1, ?2, 'automatic', ?3)
                     ON CONFLICT(name) DO UPDATE SET name=excluded.name
                     RETURNING id",
                    params![uuid::Uuid::new_v4().to_string(), name, now],
                    |r| r.get(0),
                )
                .map_err(|e| RefractError::storage(format!("topic upsert: {e}")))?;
            tx.execute(
                "INSERT OR IGNORE INTO item_topics (item_id, topic_id, is_primary) VALUES (?1, ?2, ?3)",
                params![item_id, id, idx == 0],
            )
            .map_err(|e| RefractError::storage(format!("item_topics: {e}")))?;
            topic_names.push(name.clone());
        }

        let mut entity_names = Vec::new();
        for (name, kind) in &entities {
            let id: String = tx
                .query_row(
                    "INSERT INTO entities (id, name, kind, created_ts)
                     VALUES (?1, ?2, ?3, ?4)
                     ON CONFLICT(name, kind) DO UPDATE SET name=excluded.name
                     RETURNING id",
                    params![uuid::Uuid::new_v4().to_string(), name, kind, now],
                    |r| r.get(0),
                )
                .map_err(|e| RefractError::storage(format!("entity upsert: {e}")))?;
            tx.execute(
                "INSERT OR IGNORE INTO item_entities (item_id, entity_id) VALUES (?1, ?2)",
                params![item_id, id],
            )
            .map_err(|e| RefractError::storage(format!("item_entities: {e}")))?;
            entity_names.push(format!("{kind}: {name}"));
        }

        // Temporal context (spec §5.4): capture time always recorded;
        // ISO dates found in text become 'event' candidates — labeled as
        // extracted, never conflated with capture or publication dates.
        tx.execute(
            "INSERT OR IGNORE INTO item_times (item_id, kind, ts) VALUES (?1, 'capture', ?2)",
            params![item_id, import_ts],
        )
        .map_err(|e| RefractError::storage(format!("capture time: {e}")))?;
        for (name, kind) in &entities {
            if kind == "date" {
                if let Some(ts) = parse_date(name) {
                    tx.execute(
                        "INSERT OR IGNORE INTO item_times (item_id, kind, ts, note)
                         VALUES (?1, 'event', ?2, 'date extracted from content')",
                        params![item_id, ts],
                    )
                    .map_err(|e| RefractError::storage(format!("event time: {e}")))?;
                }
            }
        }
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;

        let suggested = self.suggest_relationships(item_id)?;
        Ok(OrganizeReport {
            item_id: item_id.to_string(),
            topics: topic_names,
            entities: entity_names,
            relationships_suggested: suggested,
        })
    }

    /// Organize every item that has no topics yet. Returns per-item reports.
    pub fn organize_library(&mut self) -> RefractResult<Vec<OrganizeReport>> {
        let ids: Vec<String> = {
            let mut stmt = self
                .conn
                .prepare(
                    "SELECT i.id FROM items i
                     LEFT JOIN item_topics it ON it.item_id = i.id
                     WHERE it.item_id IS NULL
                     ORDER BY i.import_ts",
                )
                .map_err(|e| RefractError::storage(e.to_string()))?;
            let rows = stmt
                .query_map([], |r| r.get::<_, String>(0))
                .map_err(|e| RefractError::storage(e.to_string()))?;
            let mut v = Vec::new();
            for r in rows {
                v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
            }
            v
        };
        let mut out = Vec::new();
        for id in ids {
            out.push(self.organize_item(&id)?);
        }
        Ok(out)
    }

    /// Relationship suggestions (spec §5.3). Evidence-based only:
    /// shared topic, shared organization entity, or shared concept entities.
    /// Each carries a basis string and a modest confidence; the user decides.
    fn suggest_relationships(&self, item_id: &str) -> RefractResult<usize> {
        let now = now_ts()?;
        // Candidates: other items sharing a topic or entity.
        let mut stmt = self
            .conn
            .prepare(
                "SELECT o.item_id,
                        (SELECT COUNT(*) FROM item_topics a
                          JOIN item_topics b USING (topic_id)
                          WHERE a.item_id=?1 AND b.item_id=o.item_id) AS shared_topics,
                        (SELECT t.name FROM item_topics a
                          JOIN item_topics b USING (topic_id)
                          JOIN topics t ON t.id=a.topic_id
                          WHERE a.item_id=?1 AND b.item_id=o.item_id LIMIT 1) AS topic_name,
                        (SELECT COUNT(*) FROM item_entities a
                          JOIN item_entities b USING (entity_id)
                          JOIN entities e ON e.id=a.entity_id
                          WHERE a.item_id=?1 AND b.item_id=o.item_id AND e.kind='organization') AS shared_orgs,
                        (SELECT e.name FROM item_entities a
                          JOIN item_entities b USING (entity_id)
                          JOIN entities e ON e.id=a.entity_id
                          WHERE a.item_id=?1 AND b.item_id=o.item_id AND e.kind='organization' LIMIT 1) AS org_name,
                        (SELECT COUNT(*) FROM item_entities a
                          JOIN item_entities b USING (entity_id)
                          JOIN entities e ON e.id=a.entity_id
                          WHERE a.item_id=?1 AND b.item_id=o.item_id AND e.kind NOT IN ('organization','date','email')) AS shared_concepts
                 FROM (SELECT DISTINCT item_id FROM item_topics WHERE topic_id IN
                         (SELECT topic_id FROM item_topics WHERE item_id=?1)
                       UNION
                       SELECT DISTINCT item_id FROM item_entities WHERE entity_id IN
                         (SELECT entity_id FROM item_entities WHERE item_id=?1)) o
                 WHERE o.item_id != ?1",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        struct Cand {
            other: String,
            shared_topics: i64,
            topic_name: Option<String>,
            shared_orgs: i64,
            org_name: Option<String>,
            shared_concepts: i64,
        }
        let rows = stmt
            .query_map(
                params![item_id],
                |r| {
                    Ok(Cand {
                        other: r.get(0)?,
                        shared_topics: r.get(1)?,
                        topic_name: r.get(2)?,
                        shared_orgs: r.get(3)?,
                        org_name: r.get(4)?,
                        shared_concepts: r.get(5)?,
                    })
                },
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut cands = Vec::new();
        for r in rows {
            cands.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        drop(stmt);

        let mut suggested = 0usize;
        for c in cands.into_iter().take(25) {
            let mut links: Vec<(&str, String, f64)> = Vec::new();
            if c.shared_topics > 0 {
                links.push((
                    "same_topic",
                    format!("shares topic \"{}\"", c.topic_name.clone().unwrap_or_default()),
                    0.5 + (0.1 * c.shared_topics.min(3) as f64),
                ));
            }
            if c.shared_orgs > 0 {
                links.push((
                    "same_organization",
                    format!("mentions organization \"{}\"", c.org_name.clone().unwrap_or_default()),
                    0.6,
                ));
            }
            if c.shared_concepts >= 2 {
                links.push((
                    "shared_concept",
                    format!("{} shared concept entities", c.shared_concepts),
                    0.35 + (0.05 * c.shared_concepts.min(6) as f64),
                ));
            }
            for (kind, basis, conf) in links {
                let inserted = self
                    .conn
                    .execute(
                        "INSERT OR IGNORE INTO relationships
                           (id, source_item_id, target_item_id, kind, basis, confidence, created_ts)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                        params![
                            uuid::Uuid::new_v4().to_string(),
                            if item_id < c.other.as_str() { item_id } else { c.other.as_str() },
                            if item_id < c.other.as_str() { c.other.as_str() } else { item_id },
                            kind,
                            basis,
                            conf.min(0.95),
                            now
                        ],
                    )
                    .map_err(|e| RefractError::storage(format!("relationship: {e}")))?;
                suggested += inserted;
            }
        }
        Ok(suggested)
    }

    // ----- Topics (spec §5.2: rename / merge / reject / customize) -----

    pub fn list_topics(&self) -> RefractResult<Vec<Topic>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT t.id, t.name, t.origin, t.created_ts, t.pinned,
                        (SELECT COUNT(*) FROM item_topics it WHERE it.topic_id=t.id)
                 FROM topics t ORDER BY t.pinned DESC, 6 DESC, t.name",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Topic {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    origin: r.get(2)?,
                    created_ts: r.get(3)?,
                    pinned: r.get::<_, i64>(4)? != 0,
                    item_count: r.get(5)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    pub fn rename_topic(&self, topic_id: &str, new_name: &str) -> RefractResult<Topic> {
        let new_name = new_name.trim();
        if new_name.is_empty() {
            return Err(RefractError::invalid("empty topic name"));
        }
        let tx = self.conn.unchecked_transaction().map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("INSERT OR REPLACE INTO topic_rules (keyword_topic, topic_id) SELECT name, id FROM topics WHERE id=?1", params![topic_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let n = tx
            .execute(
                "UPDATE topics SET name=?1, origin='user' WHERE id=?2",
                params![new_name, topic_id],
            )
            .map_err(|e| RefractError::storage(format!("rename topic: {e}")))?;
        if n == 0 {
            return Err(RefractError::invalid(format!("topic not found: {topic_id}")));
        }
        tx.commit().map_err(|e| RefractError::storage(e.to_string()))?;
        self.list_topics()?
            .into_iter()
            .find(|t| t.id == topic_id)
            .ok_or_else(|| RefractError::internal("topic vanished"))
    }

    /// Merge `from_id` into `to_id`: items move over, the source topic is
    /// deleted. Returns the surviving topic.
    pub fn merge_topics(&mut self, from_id: &str, to_id: &str) -> RefractResult<Topic> {
        if from_id == to_id {
            return Err(RefractError::invalid("cannot merge a topic into itself"));
        }
        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;
        let existing: i64 = tx.query_row("SELECT COUNT(*) FROM topics WHERE id IN (?1,?2)", params![from_id, to_id], |r| r.get(0))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        if existing != 2 { return Err(RefractError::invalid("topic not found")); }
        tx.execute("INSERT OR REPLACE INTO topic_rules (keyword_topic, topic_id) SELECT name, ?1 FROM topics WHERE id=?2", params![to_id, from_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("UPDATE topic_rules SET topic_id=?1 WHERE topic_id=?2", params![to_id, from_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("UPDATE topics SET origin='user' WHERE id=?1", params![to_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute(
            "INSERT OR IGNORE INTO item_topics (item_id, topic_id, is_primary)
             SELECT item_id, ?1, 0 FROM item_topics WHERE topic_id=?2",
            params![to_id, from_id],
        )
        .map_err(|e| RefractError::storage(format!("move items: {e}")))?;
        tx.execute("DELETE FROM topics WHERE id=?1", params![from_id])
            .map_err(|e| RefractError::storage(format!("delete topic: {e}")))?;
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;
        self.list_topics()?
            .into_iter()
            .find(|t| t.id == to_id)
            .ok_or_else(|| RefractError::invalid(format!("topic not found: {to_id}")))
    }

    /// Reject an automatic topic: removes it and its links. User-created
    /// (origin='user') topics are protected from accidental rejection.
    pub fn reject_topic(&mut self, topic_id: &str) -> RefractResult<()> {
        let origin: String = self
            .conn
            .query_row("SELECT origin FROM topics WHERE id=?1", params![topic_id], |r| {
                r.get(0)
            })
            .map_err(|_| RefractError::invalid(format!("topic not found: {topic_id}")))?;
        if origin == "user" {
            return Err(RefractError::invalid(
                "user topics cannot be rejected; delete them explicitly",
            ));
        }
        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;
        tx.execute("INSERT OR REPLACE INTO topic_rules (keyword_topic, topic_id) SELECT name, NULL FROM topics WHERE id=?1", params![topic_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("UPDATE topic_rules SET topic_id=NULL WHERE topic_id=?1", params![topic_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("DELETE FROM item_topics WHERE topic_id=?1", params![topic_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute("DELETE FROM topics WHERE id=?1", params![topic_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;
        Ok(())
    }

    pub fn set_topic_pinned(&self, topic_id: &str, pinned: bool) -> RefractResult<()> {
        let n = self
            .conn
            .execute(
                "UPDATE topics SET pinned=?1 WHERE id=?2",
                params![pinned as i64, topic_id],
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        if n == 0 {
            return Err(RefractError::invalid(format!("topic not found: {topic_id}")));
        }
        Ok(())
    }

    pub fn items_for_topic(&self, topic_id: &str, limit: u32) -> RefractResult<Vec<Item>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT i.id, i.source_url, i.source_type, i.import_ts, i.content_hash,
                        i.title, i.author, i.language, i.extraction_confidence, i.status
                 FROM items i JOIN item_topics it ON it.item_id=i.id
                 WHERE it.topic_id=?1 ORDER BY i.import_ts DESC LIMIT ?2",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![topic_id, limit], |r| self.row_to_item(r))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    pub fn list_entities(&self, limit: u32) -> RefractResult<Vec<Entity>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT e.id, e.name, e.kind, e.created_ts,
                        (SELECT COUNT(*) FROM item_entities ie WHERE ie.entity_id=e.id)
                 FROM entities e ORDER BY 5 DESC LIMIT ?1",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![limit], |r| {
                Ok(Entity {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    kind: r.get(2)?,
                    created_ts: r.get(3)?,
                    item_count: r.get(4)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    // ----- Relationships (spec §5.3) -----

    pub fn list_relationships(&self, item_id: Option<&str>, limit: u32) -> RefractResult<Vec<Relationship>> {
        let (sql, use_param) = match item_id {
            Some(_) => (
                "SELECT id, source_item_id, target_item_id, kind, basis, confidence, dismissed, created_ts
                 FROM relationships
                 WHERE (source_item_id=?1 OR target_item_id=?1) AND dismissed=0
                 ORDER BY confidence DESC LIMIT ?2",
                true,
            ),
            None => (
                "SELECT id, source_item_id, target_item_id, kind, basis, confidence, dismissed, created_ts
                 FROM relationships WHERE dismissed=0
                 ORDER BY confidence DESC LIMIT ?1",
                false,
            ),
        };
        let map = |r: &rusqlite::Row| -> rusqlite::Result<Relationship> {
            Ok(Relationship {
                id: r.get(0)?,
                source_item_id: r.get(1)?,
                target_item_id: r.get(2)?,
                kind: r.get(3)?,
                basis: r.get(4)?,
                confidence: r.get(5)?,
                dismissed: r.get::<_, i64>(6)? != 0,
                created_ts: r.get(7)?,
            })
        };
        let mut v = Vec::new();
        if use_param {
            let mut stmt = self.conn.prepare(sql).map_err(|e| RefractError::storage(e.to_string()))?;
            let rows = stmt
                .query_map(params![item_id.unwrap(), limit], map)
                .map_err(|e| RefractError::storage(e.to_string()))?;
            for r in rows {
                v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
            }
        } else {
            let mut stmt = self.conn.prepare(sql).map_err(|e| RefractError::storage(e.to_string()))?;
            let rows = stmt
                .query_map(params![limit], map)
                .map_err(|e| RefractError::storage(e.to_string()))?;
            for r in rows {
                v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
            }
        }
        Ok(v)
    }

    /// Remove a connection: the row is kept but marked dismissed so the
    /// suggestion is never resurfaced silently.
    pub fn dismiss_relationship(&self, rel_id: &str) -> RefractResult<()> {
        let n = self
            .conn
            .execute("UPDATE relationships SET dismissed=1 WHERE id=?1", params![rel_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        if n == 0 {
            return Err(RefractError::invalid(format!("relationship not found: {rel_id}")));
        }
        Ok(())
    }

    pub fn add_relationship(
        &self,
        source_item_id: &str,
        target_item_id: &str,
        kind: &str,
        basis: &str,
    ) -> RefractResult<Relationship> {
        if source_item_id == target_item_id {
            return Err(RefractError::invalid("cannot link an item to itself"));
        }
        let now = now_ts()?;
        let id = uuid::Uuid::new_v4().to_string();
        self.conn
            .execute(
                "INSERT OR REPLACE INTO relationships
                   (id, source_item_id, target_item_id, kind, basis, confidence, dismissed, created_ts)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1.0, 0, ?6)",
                params![id, source_item_id, target_item_id, kind, basis, now],
            )
            .map_err(|e| RefractError::storage(format!("add relationship: {e}")))?;
        Ok(Relationship {
            id,
            source_item_id: source_item_id.to_string(),
            target_item_id: target_item_id.to_string(),
            kind: kind.to_string(),
            basis: basis.to_string(),
            confidence: 1.0,
            dismissed: false,
            created_ts: now,
        })
    }

    // ----- Memory Timeline (spec §5.4) -----

    pub fn memory_timeline(&self, limit: u32) -> RefractResult<Vec<TimelineEntry>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT t.item_id, COALESCE(i.title, t.item_id), t.kind, t.ts, t.note
                 FROM item_times t JOIN items i ON i.id=t.item_id
                 ORDER BY t.ts DESC LIMIT ?1",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![limit], |r| {
                Ok(TimelineEntry {
                    item_id: r.get(0)?,
                    title: r.get(1)?,
                    time_kind: r.get(2)?,
                    ts: r.get(3)?,
                    note: r.get(4)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    /// Record an explicit timestamp for an item (publication, modification,
    /// event, deadline). Capture time is system-managed.
    pub fn set_item_time(&self, item_id: &str, kind: &str, ts: i64, note: Option<&str>) -> RefractResult<()> {
        if kind == "capture" {
            return Err(RefractError::invalid("capture time is system-managed"));
        }
        if !["publication", "modification", "event", "deadline"].contains(&kind) {
            return Err(RefractError::invalid(format!("unknown time kind: {kind}")));
        }
        self.conn
            .execute(
                "INSERT INTO item_times (item_id, kind, ts, note) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(item_id, kind, ts) DO UPDATE SET note=excluded.note",
                params![item_id, kind, ts, note],
            )
            .map_err(|e| RefractError::storage(format!("set item time: {e}")))?;
        Ok(())
    }

    // ----- Knowledge Evolution (spec §5.5) -----

    /// Describe how information around one topic developed over time.
    /// Purely descriptive: stages summarize *what was collected*, never the
    /// user's beliefs or identity.
    pub fn topic_evolution(&self, topic_id: &str, stages_count: u32) -> RefractResult<TopicEvolution> {
        let topic = self
            .list_topics()?
            .into_iter()
            .find(|t| t.id == topic_id)
            .ok_or_else(|| RefractError::invalid(format!("topic not found: {topic_id}")))?;
        let mut stmt = self
            .conn
            .prepare(
                "SELECT i.id, i.import_ts FROM items i
                 JOIN item_topics it ON it.item_id=i.id
                 WHERE it.topic_id=?1 ORDER BY i.import_ts",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![topic_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut items: Vec<(String, i64)> = Vec::new();
        for r in rows {
            items.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        drop(stmt);

        let n = stages_count.clamp(1, 8) as usize;
        let mut stages = Vec::new();
        if !items.is_empty() {
            let chunk = (items.len() + n - 1) / n;
            for part in items.chunks(chunk) {
                let from = part.first().map(|p| p.1).unwrap_or(0);
                let to = part.last().map(|p| p.1).unwrap_or(0);
                stages.push(EvolutionStage {
                    from_ts: from,
                    to_ts: to,
                    item_count: part.len() as i64,
                    description: format!(
                        "{} item(s) about \"{}\" captured in this period",
                        part.len(),
                        topic.name
                    ),
                    item_ids: part.iter().map(|p| p.0.clone()).collect(),
                });
            }
        }
        let summary = if items.is_empty() {
            format!("No information collected for \"{}\" yet.", topic.name)
        } else if stages.len() == 1 {
            format!(
                "All {} item(s) about \"{}\" were captured in a single period.",
                items.len(),
                topic.name
            )
        } else {
            let first = stages.first().unwrap();
            let last = stages.last().unwrap();
            format!(
                "\"{}\" developed across {} periods: earliest collection of {} item(s), most recent of {} item(s). \
                 This describes the available information only.",
                topic.name,
                stages.len(),
                first.item_count,
                last.item_count
            )
        };
        Ok(TopicEvolution { topic, stages, summary })
    }

    // ----- Project Spaces (spec §13) -----

    pub fn create_project(&self, name: &str, description: Option<&str>) -> RefractResult<Project> {
        let name = name.trim();
        if name.is_empty() {
            return Err(RefractError::invalid("empty project name"));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let now = now_ts()?;
        self.conn
            .execute(
                "INSERT INTO projects (id, name, description, created_ts) VALUES (?1, ?2, ?3, ?4)",
                params![id, name, description, now],
            )
            .map_err(|e| RefractError::storage(format!("create project: {e}")))?;
        Ok(Project {
            id,
            name: name.to_string(),
            description: description.map(|d| d.to_string()),
            created_ts: now,
            item_count: 0,
        })
    }

    pub fn list_projects(&self) -> RefractResult<Vec<Project>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT p.id, p.name, p.description, p.created_ts,
                        (SELECT COUNT(*) FROM project_items pi WHERE pi.project_id=p.id)
                 FROM projects p ORDER BY p.created_ts DESC",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Project {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    description: r.get(2)?,
                    created_ts: r.get(3)?,
                    item_count: r.get(4)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    pub fn delete_project(&self, project_id: &str) -> RefractResult<()> {
        let n = self
            .conn
            .execute("DELETE FROM projects WHERE id=?1", params![project_id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        if n == 0 {
            return Err(RefractError::invalid(format!("project not found: {project_id}")));
        }
        Ok(())
    }

    pub fn project_add_item(&self, project_id: &str, item_id: &str) -> RefractResult<()> {
        let now = now_ts()?;
        self.conn
            .execute(
                "INSERT OR IGNORE INTO project_items (project_id, item_id, added_ts) VALUES (?1, ?2, ?3)",
                params![project_id, item_id, now],
            )
            .map_err(|e| RefractError::storage(format!("project add item: {e}")))?;
        // Cross-link the items as same_project with explicit basis.
        let mut stmt = self
            .conn
            .prepare("SELECT item_id FROM project_items WHERE project_id=?1 AND item_id != ?2")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let pname: String = self
            .conn
            .query_row("SELECT name FROM projects WHERE id=?1", params![project_id], |r| {
                r.get(0)
            })
            .map_err(|_| RefractError::invalid(format!("project not found: {project_id}")))?;
        let others: Vec<String> = stmt
            .query_map(params![project_id, item_id], |r| r.get(0))
            .map_err(|e| RefractError::storage(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();
        drop(stmt);
        for other in others {
            self.conn
                .execute(
                    "INSERT OR IGNORE INTO relationships
                       (id, source_item_id, target_item_id, kind, basis, confidence, created_ts)
                     VALUES (?1, ?2, ?3, 'same_project', ?4, 1.0, ?5)",
                    params![
                        uuid::Uuid::new_v4().to_string(),
                        item_id,
                        other,
                        format!("both added to project \"{pname}\""),
                        now
                    ],
                )
                .map_err(|e| RefractError::storage(e.to_string()))?;
        }
        Ok(())
    }

    pub fn project_remove_item(&self, project_id: &str, item_id: &str) -> RefractResult<()> {
        self.conn
            .execute(
                "DELETE FROM project_items WHERE project_id=?1 AND item_id=?2",
                params![project_id, item_id],
            )
            .map_err(|e| RefractError::storage(format!("project remove item: {e}")))?;
        Ok(())
    }

    pub fn project_items(&self, project_id: &str, limit: u32) -> RefractResult<Vec<Item>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT i.id, i.source_url, i.source_type, i.import_ts, i.content_hash,
                        i.title, i.author, i.language, i.extraction_confidence, i.status
                 FROM items i JOIN project_items pi ON pi.item_id=i.id
                 WHERE pi.project_id=?1 ORDER BY pi.added_ts DESC LIMIT ?2",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![project_id, limit], |r| self.row_to_item(r))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }

    /// Timeline for a project space: capture times of its items plus the
    /// moment each item joined the project.
    pub fn project_timeline(&self, project_id: &str, limit: u32) -> RefractResult<Vec<TimelineEntry>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT pi.item_id, COALESCE(i.title, pi.item_id), 'event', pi.added_ts, 'added to project'
                 FROM project_items pi JOIN items i ON i.id=pi.item_id
                 WHERE pi.project_id=?1
                 UNION ALL
                 SELECT t.item_id, COALESCE(i.title, t.item_id), t.kind, t.ts, t.note
                 FROM item_times t
                 JOIN items i ON i.id=t.item_id
                 JOIN project_items pi ON pi.item_id=t.item_id AND pi.project_id=?1
                 ORDER BY 4 DESC LIMIT ?2",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![project_id, limit], |r| {
                Ok(TimelineEntry {
                    item_id: r.get(0)?,
                    title: r.get(1)?,
                    time_kind: r.get(2)?,
                    ts: r.get(3)?,
                    note: r.get(4)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut v = Vec::new();
        for r in rows {
            v.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(v)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use refract_core::SourceType;

    fn tmp_store() -> Store {
        Store::open_in_memory().unwrap()
    }

    fn make_item(id: &str, title: &str, text: &str) -> Item {
        use refract_core::{Block, BlockKind, ImportStatus};
        Item {
            id: id.to_string(),
            source_url: None,
            source_type: SourceType::Text,
            import_ts: 1_700_000_000,
            content_hash: format!("hash-{id}"),
            title: Some(title.to_string()),
            author: None,
            language: Some("en".to_string()),
            extraction_confidence: 0.9,
            status: ImportStatus::Ready,
            blocks: vec![Block {
                idx: 0,
                kind: BlockKind::Paragraph,
                text: text.to_string(),
            }],
        }
    }

    #[test]
    fn organize_assigns_topics_and_entities() {
        let mut store = tmp_store();
        let item = make_item("i1", "AI privacy article", "Machine learning and privacy: GDPR applies to neural network training. Contact privacy@acme.org or Alice Smith at the Data Board.");
        store.insert_item(&item, b"body", "hash-i1").unwrap();
        let report = store.organize_item("i1").unwrap();
        assert!(report.topics.contains(&"artificial intelligence".to_string()));
        assert!(report.topics.contains(&"privacy".to_string()));
        assert!(!report.entities.is_empty());
    }

    #[test]
    fn existing_topics_are_reused() {
        let mut store = tmp_store();
        let a = make_item("a", "First AI note", "Machine learning basics.");
        let b = make_item("b", "Second AI note", "More machine learning material.");
        store.insert_item(&a, b"a", "hash-a").unwrap();
        store.insert_item(&b, b"b", "hash-b").unwrap();
        store.organize_item("a").unwrap();
        store.organize_item("b").unwrap();
        let topics = store.list_topics().unwrap();
        assert_eq!(topics.iter().filter(|t| t.name == "artificial intelligence").count(), 1);
    }

    #[test]
    fn relationships_carry_basis_and_confidence() {
        let mut store = tmp_store();
        let a = make_item("a", "AI privacy", "Machine learning and privacy and GDPR.");
        let b = make_item("b", "AI security", "Machine learning security encryption.");
        store.insert_item(&a, b"a", "hash-a").unwrap();
        store.insert_item(&b, b"b", "hash-b").unwrap();
        store.organize_item("a").unwrap();
        store.organize_item("b").unwrap();
        let rels = store.list_relationships(None, 50).unwrap();
        assert!(!rels.is_empty());
        for r in &rels {
            assert!(!r.basis.is_empty());
            assert!(r.confidence > 0.0 && r.confidence <= 1.0);
        }
        store.dismiss_relationship(&rels[0].id).unwrap();
        let after = store.list_relationships(None, 50).unwrap();
        assert_eq!(after.len(), rels.len() - 1);
    }

    #[test]
    fn topic_merge_and_rename() {
        let mut store = tmp_store();
        let a = make_item("a", "AI note", "Machine learning.");
        let b = make_item("b", "Privacy note", "Privacy GDPR.");
        store.insert_item(&a, b"a", "hash-a").unwrap();
        store.insert_item(&b, b"b", "hash-b").unwrap();
        store.organize_item("a").unwrap();
        store.organize_item("b").unwrap();
        let topics = store.list_topics().unwrap();
        let ai = topics.iter().find(|t| t.name == "artificial intelligence").unwrap();
        let priv_ = topics.iter().find(|t| t.name == "privacy").unwrap();
        store.rename_topic(&priv_.id, "data privacy").unwrap();
        let merged = store.merge_topics(&priv_.id, &ai.id).unwrap();
        assert_eq!(merged.item_count, 2);
        assert!(store.list_topics().unwrap().iter().all(|t| t.id != priv_.id));
    }

    #[test]
    fn timeline_distinguishes_time_kinds() {
        let mut store = tmp_store();
        let a = make_item("a", "Doc with date", "Meeting scheduled for 2026-03-01 with details.");
        store.insert_item(&a, b"a", "hash-a").unwrap();
        store.organize_item("a").unwrap();
        store.set_item_time("a", "deadline", 1_772_000_000, Some("extracted")).unwrap();
        assert!(store.set_item_time("a", "capture", 1, None).is_err());
        let tl = store.memory_timeline(50).unwrap();
        let kinds: Vec<&str> = tl.iter().map(|e| e.time_kind.as_str()).collect();
        assert!(kinds.contains(&"capture"));
        assert!(kinds.contains(&"event"));
        assert!(kinds.contains(&"deadline"));
    }

    #[test]
    fn evolution_is_descriptive() {
        let mut store = tmp_store();
        for i in 0..5 {
            let item = make_item(&format!("x{i}"), "AI", "Machine learning topic.");
            store.insert_item(&item, b"x", &format!("hash-x{i}")).unwrap();
            store.organize_item(&item.id).unwrap();
        }
        let ai = store.list_topics().unwrap().into_iter().find(|t| t.name == "artificial intelligence").unwrap();
        let evo = store.topic_evolution(&ai.id, 3).unwrap();
        assert_eq!(evo.stages.len(), 3);
        assert!(evo.summary.contains("describes the available information"));
    }

    #[test]
    fn project_spaces_group_items() {
        let mut store = tmp_store();
        let a = make_item("a", "A", "alpha");
        let b = make_item("b", "B", "beta");
        store.insert_item(&a, b"a", "hash-a").unwrap();
        store.insert_item(&b, b"b", "hash-b").unwrap();
        let p = store.create_project("Thesis", Some("references")).unwrap();
        store.project_add_item(&p.id, "a").unwrap();
        store.project_add_item(&p.id, "b").unwrap();
        let items = store.project_items(&p.id, 10).unwrap();
        assert_eq!(items.len(), 2);
        let tl = store.project_timeline(&p.id, 10).unwrap();
        assert!(tl.iter().any(|e| e.note.as_deref() == Some("added to project")));
        let rels = store.list_relationships(Some("a"), 10).unwrap();
        assert!(rels.iter().any(|r| r.kind == "same_project"));
        store.project_remove_item(&p.id, "b").unwrap();
        assert_eq!(store.project_items(&p.id, 10).unwrap().len(), 1);
        store.delete_project(&p.id).unwrap();
        assert!(store.list_projects().unwrap().is_empty());
    }
}
