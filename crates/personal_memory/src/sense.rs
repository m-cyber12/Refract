//! Phase II master, Phase 2 — REFRACT SENSE: intelligent decision engine.
//!
//! Every incoming item passes through the pipeline
//! Detect → Classify → Evaluate → Deduplicate → Decide → Organize → Persist,
//! producing one of three transparent outcomes (spec §3.1):
//! AUTO SAVE, SMART SUGGEST, or IGNORE. Scoring is rule-based and every
//! decision carries a human-readable explanation (spec §3.2). Capture
//! policies live in `sense_rules` with editable presets (spec §3.3), and
//! every decision is logged in `capture_decisions` so history can be
//! reviewed and undone.

use crate::Store;
use refract_core::{Item, RefractError, RefractResult, SourceType};
use rusqlite::params;
use serde::Serialize;

fn now_ts() -> RefractResult<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| RefractError::storage(format!("clock: {e}")))?
        .as_secs() as i64)
}

/// The three pipeline outcomes (spec §3.1 A/B/C).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SenseDecision {
    AutoSave,
    SmartSuggest,
    Ignore,
}

impl SenseDecision {
    pub fn as_str(&self) -> &'static str {
        match self {
            SenseDecision::AutoSave => "auto_save",
            SenseDecision::SmartSuggest => "smart_suggest",
            SenseDecision::Ignore => "ignore",
        }
    }
    pub fn from_str(s: &str) -> RefractResult<Self> {
        match s {
            "auto_save" => Ok(SenseDecision::AutoSave),
            "smart_suggest" => Ok(SenseDecision::SmartSuggest),
            "ignore" => Ok(SenseDecision::Ignore),
            other => Err(RefractError::invalid(format!("unknown decision: {other}"))),
        }
    }
}

/// Rule-based content category (spec §3.2 classification dimension).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Category {
    Receipt,
    Subscription,
    Article,
    Document,
    Note,
    Temporary,
    Reference,
}

impl Category {
    pub fn as_str(&self) -> &'static str {
        match self {
            Category::Receipt => "receipt",
            Category::Subscription => "subscription",
            Category::Article => "article",
            Category::Document => "document",
            Category::Note => "note",
            Category::Temporary => "temporary",
            Category::Reference => "reference",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "receipt" => Category::Receipt,
            "subscription" => Category::Subscription,
            "article" => Category::Article,
            "document" => Category::Document,
            "note" => Category::Note,
            "temporary" => Category::Temporary,
            _ => Category::Reference,
        }
    }
}

/// Transparent rule-based value score (spec §3.2). The score is NOT an
/// objective measure of personal importance — the explanation says why.
#[derive(Debug, Clone, Serialize)]
pub struct ValueScore {
    pub score: f32,
    pub category: String,
    pub dimensions: Vec<(String, f32)>,
    pub explanation: String,
}

/// One persisted capture rule (spec §3.3).
#[derive(Debug, Clone, Serialize)]
pub struct SenseRule {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub pattern: String,
    pub enabled: bool,
    pub preset: String,
    pub created_ts: i64,
}

/// One logged pipeline decision (spec §3.1 review/undo).
#[derive(Debug, Clone, Serialize)]
pub struct CaptureDecisionRecord {
    pub id: String,
    pub item_id: Option<String>,
    pub decision: String,
    pub score: f32,
    pub category: String,
    pub explanation: String,
    pub rule_id: Option<String>,
    pub ts: i64,
    pub undone: bool,
}

/// Built-in presets (spec §3.3). Presets install rules; explicit user rules
/// (preset='custom') are never overwritten by applying a preset.
pub const PRESETS: &[&str] = &["conservative", "balanced", "research", "personal_archive"];

fn preset_rules(preset: &str) -> Vec<(&'static str, &'static str, &'static str)> {
    // (name, kind, pattern)
    match preset {
        "conservative" => vec![
            ("Receipts & invoices", "allow_category", "receipt"),
            ("Subscriptions", "allow_category", "subscription"),
            ("Reference docs", "confirm_category", "reference"),
            ("Everything else", "confirm_category", "*"),
        ],
        "balanced" => vec![
            ("Receipts & invoices", "allow_category", "receipt"),
            ("Subscriptions", "allow_category", "subscription"),
            ("Long-form reference", "allow_category", "reference"),
            ("Newsletter noise", "deny_source", "newsletter"),
            ("Verification codes", "deny_source", "*verification*"),
        ],
        "research" => vec![
            ("Articles", "allow_category", "article"),
            ("Reference docs", "allow_category", "reference"),
            ("Receipts & invoices", "confirm_category", "receipt"),
        ],
        "personal_archive" => vec![
            ("Archive everything", "allow_category", "*"),
        ],
        _ => vec![],
    }
}

/// Rule-based classifier over title + body text (spec §3.1 Classify step).
pub fn classify(source_type: SourceType, title: &str, body: &str) -> (Category, f32) {
    let hay = format!("{} {}", title.to_lowercase(), body.to_lowercase());
    let short = body.trim().len() < 200;
    if ["verification code", "your code is", "otp", "login attempt", "sign-in attempt"]
        .iter()
        .any(|k| hay.contains(k))
        && short
    {
        return (Category::Temporary, 0.9);
    }
    if ["receipt", "invoice", "order confirmation", "payment of", "total:", "receipt #"]
        .iter()
        .any(|k| hay.contains(k))
    {
        return (Category::Receipt, 0.85);
    }
    if ["subscription", "renewal", "renew", "plan:", "billed monthly", "billed yearly"]
        .iter()
        .any(|k| hay.contains(k))
    {
        return (Category::Subscription, 0.85);
    }
    if matches!(source_type, SourceType::Url | SourceType::Html)
        && body.len() > 2000
        && !hay.contains("login")
    {
        return (Category::Article, 0.6);
    }
    if matches!(source_type, SourceType::Pdf | SourceType::File) {
        return (Category::Document, 0.7);
    }
    if body.len() > 800 {
        return (Category::Reference, 0.6);
    }
    (Category::Note, 0.5)
}

/// Rule-based value scoring (spec §3.2). Dimensions are transparent and
/// each contributes to the total; classification confidence included.
pub fn score_value(category: &Category, classification_confidence: f32, body_len: usize, duplicate: bool) -> ValueScore {
    let mut dimensions: Vec<(String, f32)> = Vec::new();
    let mut total = 0.0f32;

    let reference_value = match category {
        Category::Receipt | Category::Subscription | Category::Reference => 0.9,
        Category::Document => 0.75,
        Category::Article => 0.55,
        Category::Note => 0.45,
        Category::Temporary => 0.05,
    };
    let density = (body_len as f32 / 4000.0).min(1.0);
    let uniqueness = if duplicate { 0.1 } else { 0.9 };

    dimensions.push(("reference_value".into(), reference_value));
    dimensions.push(("information_density".into(), density));
    dimensions.push(("uniqueness".into(), uniqueness));
    dimensions.push(("classification_confidence".into(), classification_confidence));
    total = reference_value * 0.4 + density * 0.2 + uniqueness * 0.2 + classification_confidence * 0.2;

    let explanation = format!(
        "Category '{}' (confidence {:.0}%): reference value {:.0}%, density {:.0}%, uniqueness {:.0}%.",
        category.as_str(),
        classification_confidence * 100.0,
        reference_value * 100.0,
        density * 100.0,
        uniqueness * 100.0,
    );
    ValueScore {
        score: (total * 100.0).round() / 100.0,
        category: category.as_str().to_string(),
        dimensions,
        explanation,
    }
}

fn rule_matches(rule: &SenseRule, source_url: Option<&str>, category: &Category) -> bool {
    if !rule.enabled {
        return false;
    }
    let p = rule.pattern.to_lowercase();
    match rule.kind.as_str() {
        "allow_source" | "deny_source" => {
            let url = source_url.unwrap_or("").to_lowercase();
            if p == "*" {
                return true;
            }
            if let Some(suffix) = p.strip_prefix('*') {
                return url.contains(suffix);
            }
            url.contains(&p)
        }
        "allow_category" | "confirm_category" => {
            p == "*" || p == category.as_str()
        }
        _ => false,
    }
}

impl Store {
    fn get_setting(&self, key: &str, default: &str) -> RefractResult<String> {
        self.conn
            .query_row(
                "SELECT value FROM sense_settings WHERE key=?1",
                params![key],
                |r| r.get::<_, String>(0),
            )
            .ok()
            .unwrap_or_else(|| default.to_string())
    }

    pub fn sense_setting(&self, key: &str, default: &str) -> RefractResult<String> {
        self.get_setting(key, default)
    }

    pub fn set_sense_setting(&self, key: &str, value: &str) -> RefractResult<()> {
        self.conn
            .execute(
                "INSERT INTO sense_settings (key, value) VALUES (?1, ?2)
                 ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                params![key, value],
            )
            .map_err(|e| RefractError::storage(format!("set sense setting: {e}")))?;
        Ok(())
    }

    /// Apply a built-in preset: replaces rules previously installed by any
    /// preset, never touches user ('custom') rules (spec §3.3).
    pub fn apply_sense_preset(&self, preset: &str) -> RefractResult<usize> {
        if !PRESETS.contains(&preset) {
            return Err(RefractError::invalid(format!(
                "unknown preset '{preset}' (expected one of: {})",
                PRESETS.join(", ")
            )));
        }
        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;
        tx.execute("DELETE FROM sense_rules WHERE preset != 'custom'", [])
            .map_err(|e| RefractError::storage(format!("clear preset rules: {e}")))?;
        let ts = now_ts()?;
        let mut n = 0;
        for (name, kind, pattern) in preset_rules(preset) {
            tx.execute(
                "INSERT INTO sense_rules (id, name, kind, pattern, enabled, preset, created_ts)
                 VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6)",
                params![uuid::Uuid::new_v4().to_string(), name, kind, pattern, preset, ts],
            )
            .map_err(|e| RefractError::storage(format!("insert preset rule: {e}")))?;
            n += 1;
        }
        tx.execute(
            "INSERT INTO sense_settings (key, value) VALUES ('active_preset', ?1)
             ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            params![preset],
        )
        .map_err(|e| RefractError::storage(format!("set preset: {e}")))?;
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;
        Ok(n)
    }

    pub fn list_sense_rules(&self) -> RefractResult<Vec<SenseRule>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, kind, pattern, enabled, preset, created_ts FROM sense_rules ORDER BY created_ts, id")
            .map_err(|e| RefractError::storage(format!("prepare rules: {e}")))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(SenseRule {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    kind: r.get(2)?,
                    pattern: r.get(3)?,
                    enabled: r.get::<_, i64>(4)? != 0,
                    preset: r.get(5)?,
                    created_ts: r.get(6)?,
                })
            })
            .map_err(|e| RefractError::storage(format!("query rules: {e}")))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| RefractError::storage(format!("collect rules: {e}")))
    }

    /// Create or update a user rule (preset='custom'). `id` empty = create.
    pub fn upsert_sense_rule(
        &self,
        id: &str,
        name: &str,
        kind: &str,
        pattern: &str,
        enabled: bool,
    ) -> RefractResult<SenseRule> {
        if !["allow_source", "deny_source", "allow_category", "confirm_category"].contains(&kind) {
            return Err(RefractError::invalid(format!("unknown rule kind: {kind}")));
        }
        let id = if id.is_empty() {
            uuid::Uuid::new_v4().to_string()
        } else {
            id.to_string()
        };
        let ts = now_ts()?;
        self.conn
            .execute(
                "INSERT INTO sense_rules (id, name, kind, pattern, enabled, preset, created_ts)
                 VALUES (?1, ?2, ?3, ?4, ?5, 'custom', ?6)
                 ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind,
                   pattern=excluded.pattern, enabled=excluded.enabled",
                params![id, name, kind, pattern, enabled as i64, ts],
            )
            .map_err(|e| RefractError::storage(format!("upsert rule: {e}")))?;
        Ok(SenseRule {
            id,
            name: name.to_string(),
            kind: kind.to_string(),
            pattern: pattern.to_string(),
            enabled,
            preset: "custom".into(),
            created_ts: ts,
        })
    }

    pub fn delete_sense_rule(&self, id: &str) -> RefractResult<()> {
        self.conn
            .execute("DELETE FROM sense_rules WHERE id=?1", params![id])
            .map_err(|e| RefractError::storage(format!("delete rule: {e}")))?;
        Ok(())
    }

    /// Run the decision pipeline for an item and persist the outcome
    /// (spec §3.1). Returns the logged decision record.
    pub fn evaluate_sense(&self, item: &Item, body_text: &str) -> RefractResult<CaptureDecisionRecord> {
        // Deduplicate: same content hash already stored?
        let dup: i64 = self
            .conn
            .query_row(
                "SELECT COUNT(*) FROM items WHERE content_hash=?1 AND id != ?2",
                params![item.content_hash, item.id],
                |r| r.get(0),
            )
            .map_err(|e| RefractError::storage(format!("dedup: {e}")))?;
        let duplicate = dup > 0;

        let (category, confidence) = classify(item.source_type, item.title.as_deref().unwrap_or(""), body_text);
        let mut score = score_value(&category, confidence, body_text.len(), duplicate);

        let rules = self.list_sense_rules()?;
        let mut decision = None;
        let mut hit_rule: Option<String> = None;
        // deny_source wins outright (IGNORE).
        for r in rules.iter().filter(|r| r.kind == "deny_source") {
            if rule_matches(r, item.source_url.as_deref(), &category) {
                decision = Some(SenseDecision::Ignore);
                hit_rule = Some(r.id.clone());
                break;
            }
        }
        // allow rules -> AUTO SAVE.
        if decision.is_none() {
            for r in rules.iter().filter(|r| r.kind == "allow_source" || r.kind == "allow_category") {
                if rule_matches(r, item.source_url.as_deref(), &category) {
                    decision = Some(SenseDecision::AutoSave);
                    hit_rule = Some(r.id.clone());
                    break;
                }
            }
        }
        // confirm rules -> SMART SUGGEST.
        if decision.is_none() {
            for r in rules.iter().filter(|r| r.kind == "confirm_category") {
                if rule_matches(r, item.source_url.as_deref(), &category) {
                    decision = Some(SenseDecision::SmartSuggest);
                    hit_rule = Some(r.id.clone());
                    break;
                }
            }
        }
        // Default policy by score: high -> auto save, low -> ignore, else suggest.
        let decision = decision.unwrap_or(if duplicate || score.score < 0.25 {
            SenseDecision::Ignore
        } else if score.score >= 0.6 {
            SenseDecision::AutoSave
        } else {
            SenseDecision::SmartSuggest
        });

        if duplicate && decision != SenseDecision::Ignore {
            score.explanation = format!("Duplicate of an existing item. {}", score.explanation);
        }
        if let Some(rid) = &hit_rule {
            let rname = rules.iter().find(|r| &r.id == rid).map(|r| r.name.clone()).unwrap_or_default();
            score.explanation = format!("Rule '{}' decided {}. {}", rname, decision.as_str(), score.explanation);
        }

        let rec = CaptureDecisionRecord {
            id: uuid::Uuid::new_v4().to_string(),
            item_id: Some(item.id.clone()),
            decision: decision.as_str().to_string(),
            score: score.score,
            category: category.as_str().to_string(),
            explanation: score.explanation.clone(),
            rule_id: hit_rule,
            ts: now_ts()?,
            undone: false,
        };
        self.conn
            .execute(
                "INSERT INTO capture_decisions (id, item_id, decision, score, category, explanation, rule_id, ts, undone)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0)",
                params![rec.id, rec.item_id, rec.decision, rec.score, rec.category, rec.explanation, rec.rule_id, rec.ts],
            )
            .map_err(|e| RefractError::storage(format!("log decision: {e}")))?;
        self.conn
            .execute(
                "UPDATE items SET sense_decision=?1, sense_score=?2 WHERE id=?3",
                params![rec.decision, rec.score, item.id],
            )
            .map_err(|e| RefractError::storage(format!("stamp item: {e}")))?;
        Ok(rec)
    }

    pub fn list_capture_decisions(&self, limit: u32, offset: u32) -> RefractResult<Vec<CaptureDecisionRecord>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, item_id, decision, score, category, explanation, rule_id, ts, undone
                 FROM capture_decisions ORDER BY ts DESC, id DESC LIMIT ?1 OFFSET ?2",
            )
            .map_err(|e| RefractError::storage(format!("prepare decisions: {e}")))?;
        let rows = stmt
            .query_map(params![limit as i64, offset as i64], |r| {
                Ok(CaptureDecisionRecord {
                    id: r.get(0)?,
                    item_id: r.get(1)?,
                    decision: r.get(2)?,
                    score: r.get::<_, f64>(3)? as f32,
                    category: r.get(4)?,
                    explanation: r.get(5)?,
                    rule_id: r.get(6)?,
                    ts: r.get(7)?,
                    undone: r.get::<_, i64>(8)? != 0,
                })
            })
            .map_err(|e| RefractError::storage(format!("query decisions: {e}")))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| RefractError::storage(format!("collect decisions: {e}")))
    }

    /// Review action on a logged decision (spec §3.1): approve = auto-save the
    /// item, dismiss = ignore it, undo = mark the decision undone (history kept).
    pub fn review_capture_decision(
        &self,
        decision_id: &str,
        action: &str,
    ) -> RefractResult<CaptureDecisionRecord> {
        let new_decision = match action {
            "approve" => Some(SenseDecision::AutoSave),
            "dismiss" => Some(SenseDecision::Ignore),
            "undo" => None,
            other => {
                return Err(RefractError::invalid(format!(
                    "unknown review action '{other}' (approve|dismiss|undo)"
                )))
            }
        };
        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;
        if let Some(d) = new_decision {
            tx.execute(
                "UPDATE capture_decisions SET decision=?1 WHERE id=?2",
                params![d.as_str(), decision_id],
            )
            .map_err(|e| RefractError::storage(format!("update decision: {e}")))?;
            tx.execute(
                "UPDATE items SET sense_decision=?1
                 WHERE id=(SELECT item_id FROM capture_decisions WHERE id=?2)",
                params![d.as_str(), decision_id],
            )
            .map_err(|e| RefractError::storage(format!("stamp item: {e}")))?;
        } else {
            tx.execute(
                "UPDATE capture_decisions SET undone=1 WHERE id=?1",
                params![decision_id],
            )
            .map_err(|e| RefractError::storage(format!("undo decision: {e}")))?;
        }
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;
        // Re-read the record.
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, item_id, decision, score, category, explanation, rule_id, ts, undone
                 FROM capture_decisions WHERE id=?1",
            )
            .map_err(|e| RefractError::storage(format!("prepare: {e}")))?;
        stmt.query_row(params![decision_id], |r| {
            Ok(CaptureDecisionRecord {
                id: r.get(0)?,
                item_id: r.get(1)?,
                decision: r.get(2)?,
                score: r.get::<_, f64>(3)? as f32,
                category: r.get(4)?,
                explanation: r.get(5)?,
                rule_id: r.get(6)?,
                ts: r.get(7)?,
                undone: r.get::<_, i64>(8)? != 0,
            })
        })
        .map_err(|e| RefractError::storage(format!("read decision: {e}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_receipt_and_temporary() {
        let (c, conf) = classify(SourceType::SharedText, "Order confirmation", "Your receipt #1234 total: $42.00");
        assert_eq!(c, Category::Receipt);
        assert!(conf > 0.8);
        let (c2, _) = classify(SourceType::SharedText, "", "Your verification code is 482910");
        assert_eq!(c2, Category::Temporary);
    }

    #[test]
    fn duplicate_scores_low_on_uniqueness() {
        let s = score_value(&Category::Article, 0.6, 3000, true);
        let uniq = s.dimensions.iter().find(|d| d.0 == "uniqueness").unwrap().1;
        assert!(uniq < 0.2);
    }
}
