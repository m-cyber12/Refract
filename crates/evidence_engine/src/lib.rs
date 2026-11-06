//! Evidence engine (System B): Proof Vault + explainable claim extraction.
//!
//! Rules (spec §B4/B5): records are append-only; a SHA-256 hash proves a file
//! has not changed since hashing — never who created it. Every extracted claim
//! keeps its source quote/offset; interpretations are labeled as such.

use refract_core::{EvidenceClaim, RefractError, RefractResult};
use sha2::{Digest, Sha256};

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Re-verify a blob against its recorded hash. Returns true iff unchanged.
pub fn verify_blob(path: &str, expected_sha256: &str) -> RefractResult<bool> {
    let bytes = std::fs::read(path).map_err(|e| RefractError::storage(format!("read {path}: {e}")))?;
    Ok(sha256_hex(&bytes) == expected_sha256.to_lowercase())
}

/// Deterministic, explainable extraction of subscription-relevant clauses
/// from plain text (receipts, terms). No AI: keyword + pattern rules, each
/// claim carrying the matched quote and byte offset.
pub fn extract_claims(record_id: &str, text: &str) -> Vec<EvidenceClaim> {
    let mut claims = Vec::new();
    let lower = text.to_lowercase();

    let rules: &[(&str, &str, f32)] = &[
        ("trial", "quote", 0.9),
        ("renew", "extracted", 0.85),
        ("cancel", "extracted", 0.85),
        ("refund", "extracted", 0.8),
        ("price", "extracted", 0.7),
        ("per month", "extracted", 0.75),
        ("per year", "extracted", 0.75),
        ("automatically", "extracted", 0.7),
        ("terms", "quote", 0.6),
    ];

    for (needle, claim_type, conf) in rules {
        let mut start = 0;
        while let Some(pos) = lower[start..].find(needle) {
            let abs = start + pos;
            // Take the surrounding sentence as the quotable evidence.
            let s = lower[..abs].rfind(['.', '!', '?', '\n']).map(|i| i + 1).unwrap_or(0);
            let e = lower[abs..]
                .find(['.', '!', '?', '\n'])
                .map(|i| abs + i + 1)
                .unwrap_or(lower.len());
            let quote = text[s..e.min(text.len())].trim().to_string();
            if quote.is_empty() || quote.len() > 400 {
                start = abs + needle.len();
                continue;
            }
            claims.push(EvidenceClaim {
                id: uuid::Uuid::new_v4().to_string(),
                record_id: record_id.to_string(),
                claim_type: claim_type.to_string(),
                text: quote.clone(),
                offset: Some(s as i64),
                confidence: *conf,
            });
            start = abs + needle.len();
            if claims.len() > 60 {
                return claims;
            }
        }
    }
    claims
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_trial_and_renewal_with_offsets() {
        let text = "Your free trial ends in 7 days. The subscription renews automatically per month at $9.99. You may cancel anytime.";
        let claims = extract_claims("rec-1", text);
        assert!(claims.iter().any(|c| c.text.contains("trial") && c.offset.is_some()));
        assert!(claims.iter().any(|c| c.text.contains("renews")));
        assert!(claims.iter().any(|c| c.text.contains("cancel")));
    }

    #[test]
    fn hash_roundtrip() {
        let h = sha256_hex(b"receipt");
        assert_eq!(h.len(), 64);
    }
}
