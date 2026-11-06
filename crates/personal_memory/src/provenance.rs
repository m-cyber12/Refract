//! Phase 6 — provenance queries over the evidence log (spec §B5).

use crate::Store;
use crypto_provenance::{hash_leaf, MerkleLog, MerkleProof};
use refract_core::{RefractError, RefractResult};
use rusqlite::params;

impl Store {
    /// Ordered evidence hashes (leaf inputs), oldest first.
    fn evidence_leaves(&self) -> RefractResult<Vec<[u8; 32]>> {
        let mut stmt = self
            .conn
            .prepare("SELECT sha256 FROM evidence_records ORDER BY imported_ts, id")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut leaves = Vec::new();
        for r in rows {
            let h = r.map_err(|e| RefractError::storage(e.to_string()))?;
            let bytes: Vec<u8> = (0..h.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0))
                .collect();
            if bytes.len() == 32 {
                leaves.push(bytes.try_into().unwrap());
            }
        }
        Ok(leaves)
    }

    fn merkle_log(&self) -> RefractResult<MerkleLog> {
        Ok(MerkleLog::from_hashes(&self.evidence_leaves()?))
    }

    /// Root hash of the append-only evidence Merkle log (hex), or null if empty.
    pub fn evidence_merkle_root(&self) -> RefractResult<Option<String>> {
        Ok(self.merkle_log()?.root().map(|r| r.iter().map(|b| format!("{b:02x}")).collect()))
    }

    /// Inclusion proof for one evidence record.
    pub fn evidence_merkle_proof(&self, record_id: &str) -> RefractResult<Option<MerkleProof>> {
        let leaves = self.evidence_leaves()?;
        let mut stmt = self
            .conn
            .prepare("SELECT sha256 FROM evidence_records WHERE id = ?1")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut rows = stmt
            .query_map(params![record_id], |r| r.get::<_, String>(0))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let Some(row) = rows.next() else { return Ok(None) };
        let h = row.map_err(|e| RefractError::storage(e.to_string()))?;
        let bytes: Vec<u8> = (0..h.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0))
            .collect();
        let target: [u8; 32] = bytes.try_into().map_err(|_| RefractError::invalid("bad hash"))?;
        let log = MerkleLog::from_hashes(&leaves);
        match leaves.iter().position(|l| *l == target) {
            Some(idx) => Ok(Some(log.proof(idx)?)),
            None => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    #[test]
    fn merkle_over_evidence() {
        let mut store = Store::open_in_memory().unwrap();
        assert_eq!(store.evidence_merkle_root().unwrap(), None);
        store.add_evidence("receipt", None, b"one", None).unwrap();
        store.add_evidence("receipt", None, b"two", None).unwrap();
        let root = store.evidence_merkle_root().unwrap().unwrap();
        assert_eq!(root.len(), 64);
        let recs = store.list_evidence().unwrap();
        let proof = store.evidence_merkle_proof(&recs[0].id).unwrap().unwrap();
        assert!(crypto_provenance::verify_proof(&proof, &root));
        assert!(store.evidence_merkle_proof("nope").unwrap().is_none());
    }
}
