//! Phase 3 — Consumer X-Ray & Proof Vault storage (System B).
//!
//! Subscriptions are user-entered or imported; status distinguishes
//! confirmed/imported/suspected/unverified (spec §B1). Evidence records are
//! append-only with SHA-256 integrity (spec §B4).

use crate::Store;
use evidence_engine::{extract_claims, sha256_hex, verify_blob};
use refract_core::{
    EvidenceClaim, EvidenceRecord, RefractError, RefractResult, Subscription,
    SubscriptionStatus,
};
use rusqlite::params;

fn now_ts() -> RefractResult<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| RefractError::internal(e.to_string()))?
        .as_secs() as i64)
}

fn parse_sub_status(s: &str) -> SubscriptionStatus {
    match s {
        "confirmed" => SubscriptionStatus::Confirmed,
        "imported" => SubscriptionStatus::Imported,
        "suspected" => SubscriptionStatus::Suspected,
        _ => SubscriptionStatus::Unverified,
    }
}

impl Store {
    /// Add a subscription record.
    pub fn add_subscription(&mut self, sub: &Subscription) -> RefractResult<()> {
        self.conn
            .execute(
                "INSERT INTO subscriptions (id, service, plan, price, currency, frequency,
                                            renewal_date, trial_end, status, confidence,
                                            source_doc_id, created_ts)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",
                params![
                    sub.id, sub.service, sub.plan, sub.price, sub.currency, sub.frequency,
                    sub.renewal_date, sub.trial_end, sub.status.as_str(), sub.confidence,
                    sub.source_doc_id, sub.created_ts,
                ],
            )
            .map_err(|e| RefractError::storage(format!("add subscription: {e}")))?;
        Ok(())
    }

    fn row_to_subscription(r: &rusqlite::Row) -> rusqlite::Result<Subscription> {
        let status: String = r.get("status")?;
        Ok(Subscription {
            id: r.get("id")?,
            service: r.get("service")?,
            plan: r.get("plan")?,
            price: r.get("price")?,
            currency: r.get("currency")?,
            frequency: r.get("frequency")?,
            renewal_date: r.get("renewal_date")?,
            trial_end: r.get("trial_end")?,
            status: parse_sub_status(&status),
            confidence: r.get::<_, f64>("confidence")? as f32,
            source_doc_id: r.get("source_doc_id")?,
            created_ts: r.get("created_ts")?,
        })
    }

    pub fn list_subscriptions(&self) -> RefractResult<Vec<Subscription>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, service, plan, price, currency, frequency, renewal_date, trial_end,
                        status, confidence, source_doc_id, created_ts
                 FROM subscriptions ORDER BY COALESCE(renewal_date, trial_end, created_ts)",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| Self::row_to_subscription(r))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Upcoming renewal/trial events in the next `within_days` days.
    pub fn upcoming_events(&self, within_days: u32) -> RefractResult<Vec<Subscription>> {
        let now = now_ts()?;
        let horizon = now + within_days as i64 * 86_400;
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, service, plan, price, currency, frequency, renewal_date, trial_end,
                        status, confidence, source_doc_id, created_ts
                 FROM subscriptions
                 WHERE (renewal_date BETWEEN ?1 AND ?2) OR (trial_end BETWEEN ?1 AND ?2)
                 ORDER BY COALESCE(renewal_date, trial_end)",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![now, horizon], |r| Self::row_to_subscription(r))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Store an evidence record (append-only) from raw bytes + extracted text claims.
    pub fn add_evidence(
        &mut self,
        kind: &str,
        note: Option<&str>,
        bytes: &[u8],
        text_for_claims: Option<&str>,
    ) -> RefractResult<EvidenceRecord> {
        std::fs::create_dir_all(&self.blob_dir)
            .map_err(|e| RefractError::storage(format!("blob dir: {e}")))?;
        let id = uuid::Uuid::new_v4().to_string();
        let hash = sha256_hex(bytes);
        let path = self.blob_dir.join(format!("{id}.evidence"));
        std::fs::write(&path, bytes).map_err(|e| RefractError::storage(format!("write evidence: {e}")))?;
        let rec = EvidenceRecord {
            id: id.clone(),
            kind: kind.to_string(),
            note: note.map(|n| n.to_string()),
            blob_path: path.to_string_lossy().to_string(),
            sha256: hash,
            imported_ts: now_ts()?,
        };
        let tx = self.conn.transaction().map_err(|e| RefractError::storage(e.to_string()))?;
        tx.execute(
            "INSERT INTO evidence_records (id, kind, note, blob_path, sha256, imported_ts)
             VALUES (?1,?2,?3,?4,?5,?6)",
            params![rec.id, rec.kind, rec.note, rec.blob_path, rec.sha256, rec.imported_ts],
        )
        .map_err(|e| RefractError::storage(format!("insert evidence: {e}")))?;
        if let Some(text) = text_for_claims {
            for claim in extract_claims(&rec.id, text) {
                tx.execute(
                    "INSERT INTO evidence_claims (id, record_id, claim_type, text, offset, confidence)
                     VALUES (?1,?2,?3,?4,?5,?6)",
                    params![claim.id, claim.record_id, claim.claim_type, claim.text, claim.offset, claim.confidence],
                )
                .map_err(|e| RefractError::storage(format!("insert claim: {e}")))?;
            }
        }
        tx.commit().map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(rec)
    }

    pub fn list_evidence(&self) -> RefractResult<Vec<EvidenceRecord>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, kind, note, blob_path, sha256, imported_ts FROM evidence_records ORDER BY imported_ts DESC")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(EvidenceRecord {
                    id: r.get(0)?,
                    kind: r.get(1)?,
                    note: r.get(2)?,
                    blob_path: r.get(3)?,
                    sha256: r.get(4)?,
                    imported_ts: r.get(5)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    pub fn list_claims(&self, record_id: &str) -> RefractResult<Vec<EvidenceClaim>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, record_id, claim_type, text, offset, confidence
                 FROM evidence_claims WHERE record_id = ?1 ORDER BY offset",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![record_id], |r| {
                Ok(EvidenceClaim {
                    id: r.get(0)?,
                    record_id: r.get(1)?,
                    claim_type: r.get(2)?,
                    text: r.get(3)?,
                    offset: r.get(4)?,
                    confidence: r.get::<_, f64>(5)? as f32,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Re-hash the stored blob and compare with the recorded hash (spec §B4).
    pub fn verify_evidence(&self, id: &str) -> RefractResult<Option<bool>> {
        let mut stmt = self
            .conn
            .prepare("SELECT blob_path, sha256 FROM evidence_records WHERE id = ?1")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut rows = stmt
            .query_map(params![id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let Some(row) = rows.next() else { return Ok(None) };
        let (path, hash) = row.map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(Some(verify_blob(&path, &hash)?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample_sub(id: &str) -> Subscription {
        Subscription {
            id: id.into(),
            service: "StreamCo".into(),
            plan: Some("Pro".into()),
            price: Some(9.99),
            currency: Some("USD".into()),
            frequency: Some("monthly".into()),
            renewal_date: Some(now_ts().unwrap() + 5 * 86_400),
            trial_end: None,
            status: SubscriptionStatus::Unverified,
            confidence: 0.5,
            source_doc_id: None,
            created_ts: now_ts().unwrap(),
        }
    }

    #[test]
    fn subscriptions_and_evidence() {
        let mut store = Store::open_in_memory().unwrap();
        store.add_subscription(&sample_sub("s1")).unwrap();
        assert_eq!(store.list_subscriptions().unwrap().len(), 1);
        assert_eq!(store.upcoming_events(30).unwrap().len(), 1);
        assert!(store.upcoming_events(1).unwrap().is_empty());

        let rec = store
            .add_evidence("receipt", Some("june receipt"), b"trial ends soon, renews per month",
                         Some("Free trial ends in 3 days. Renews automatically per month at $9.99."))
            .unwrap();
        assert_eq!(rec.sha256.len(), 64);
        assert_eq!(store.list_evidence().unwrap().len(), 1);
        assert!(store.list_claims(&rec.id).unwrap().len() >= 2);
        assert_eq!(store.verify_evidence(&rec.id).unwrap(), Some(true));
        assert_eq!(store.verify_evidence("nope").unwrap(), None);
    }
}
