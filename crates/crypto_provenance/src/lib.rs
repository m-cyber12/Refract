//! Cryptographic provenance (spec §B5, Phase 6).
//!
//! What we implement: an append-only **Merkle log** over evidence record
//! hashes. A Merkle proof shows a record's hash is included in the log at a
//! given position. What it does NOT prove: who created the file, or that its
//! contents were authentic at the source. Every proof carries this statement.
//!
//! TLSNotary / zkTLS: research modules only — documented in
//! docs/phase-0/11-phase-6-status.md with trust assumptions. They do not
//! block or ship in the MVP.

use refract_core::RefractError;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub fn hash_leaf(data: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update([0x00]);
    h.update(data);
    let out: [u8; 32] = h.finalize().into();
    out
}

pub fn hash_node(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update([0x01]);
    h.update(left);
    h.update(right);
    h.finalize().into()
}

fn hex(b: &[u8; 32]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// Append-only Merkle log over leaf hashes (ordered by import time).
pub struct MerkleLog {
    leaves: Vec<[u8; 32]>,
}

/// A Merkle inclusion proof for one leaf.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MerkleProof {
    pub leaf_index: usize,
    #[serde(default)]
    pub leaf_count: usize,
    pub leaf_hash: String,
    pub root: String,
    pub path: Vec<(String, bool)>, // (sibling hash, sibling is on the right)
    pub statement: String,
}

const STATEMENT: &str = "This inclusion proof relates a stored evidence hash to a supplied local Merkle root. It does NOT prove append-only history, an independent timestamp, author identity or source authenticity. Independently record the expected root, tree size and evidence hash for a bound position check.";

impl MerkleLog {
    pub fn new() -> Self {
        MerkleLog { leaves: Vec::new() }
    }

    pub fn from_hashes(hashes: &[[u8; 32]]) -> Self {
        MerkleLog { leaves: hashes.to_vec() }
    }

    pub fn push(&mut self, leaf: [u8; 32]) {
        self.leaves.push(leaf);
    }

    pub fn len(&self) -> usize {
        self.leaves.len()
    }

    pub fn root(&self) -> Option<[u8; 32]> {
        if self.leaves.is_empty() {
            return None;
        }
        let mut level: Vec<[u8; 32]> = self.leaves.clone();
        while level.len() > 1 {
            let mut next = Vec::with_capacity(level.len() / 2 + 1);
            let mut i = 0;
            while i < level.len() {
                if i + 1 < level.len() {
                    next.push(hash_node(&level[i], &level[i + 1]));
                } else {
                    next.push(hash_node(&level[i], &level[i])); // odd node promoted by self-hash
                }
                i += 2;
            }
            level = next;
        }
        Some(level[0])
    }

    pub fn proof(&self, index: usize) -> Result<MerkleProof, RefractError> {
        if index >= self.leaves.len() {
            return Err(RefractError::invalid("leaf index out of range"));
        }
        let root = self.root().ok_or_else(|| RefractError::invalid("empty log"))?;
        let mut path = Vec::new();
        let mut level: Vec<[u8; 32]> = self.leaves.clone();
        let mut idx = index;
        while level.len() > 1 {
            let sibling = if idx % 2 == 0 { idx + 1 } else { idx - 1 };
            let sib_hash = if sibling < level.len() { level[sibling] } else { level[idx] };
            path.push((hex(&sib_hash), idx % 2 == 0)); // sibling on the right when idx is even
            let mut next = Vec::with_capacity(level.len() / 2 + 1);
            let mut i = 0;
            while i < level.len() {
                if i + 1 < level.len() {
                    next.push(hash_node(&level[i], &level[i + 1]));
                } else {
                    next.push(hash_node(&level[i], &level[i]));
                }
                i += 2;
            }
            level = next;
            idx /= 2;
        }
        Ok(MerkleProof {
            leaf_index: index,
            leaf_count: self.leaves.len(),
            leaf_hash: hex(&self.leaves[index]),
            root: hex(&root),
            path,
            statement: STATEMENT.to_string(),
        })
    }
}

/// Verify a Merkle inclusion proof against an expected root.
pub fn verify_proof(proof: &MerkleProof, expected_root: &str) -> bool {
    // Compatibility helper: consistency with a supplied root, not an external
    // binding to independently known file bytes or tree size.
    verify_bound_proof(proof, expected_root, &proof.leaf_hash, proof.leaf_count)
}

/// A caller must independently trust all three expected values. They are not
/// authenticated merely because they appear inside a submitted proof.
pub fn verify_bound_proof(proof: &MerkleProof, expected_root: &str, expected_leaf_hash: &str, expected_count: usize) -> bool {
    if expected_count == 0 || proof.leaf_count != expected_count || proof.leaf_index >= expected_count || proof.root != expected_root || proof.leaf_hash != expected_leaf_hash || proof.path.len() > usize::BITS as usize {
        return false;
    }
    let Some(mut acc) = decode_hash(&proof.leaf_hash) else { return false; };
    if decode_hash(expected_root).is_none() { return false; }
    let (mut idx, mut width) = (proof.leaf_index, expected_count);
    for (sib, sib_right) in &proof.path {
        if width <= 1 || *sib_right != (idx % 2 == 0) { return false; }
        let Some(sibling) = decode_hash(sib) else { return false; };
        // An odd tail duplicates itself; it cannot masquerade as a real extra leaf.
        if idx % 2 == 0 && idx == width - 1 && sibling != acc { return false; }
        acc = if *sib_right { hash_node(&acc, &sibling) } else { hash_node(&sibling, &acc) };
        idx /= 2;
        width = width / 2 + width % 2;
    }
    width == 1 && idx == 0 && hex(&acc) == expected_root
}

/// Fixed-length ASCII decoding: malformed UTF-8 boundaries and odd hex never panic.
pub fn decode_hash(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 || !s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) { return None; }
    let mut out = [0; 32];
    for (i, pair) in s.as_bytes().chunks_exact(2).enumerate() {
        fn digit(b: u8) -> u8 { if b <= b'9' { b - b'0' } else { b - b'a' + 10 } }
        out[i] = digit(pair[0]) * 16 + digit(pair[1]);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_proofs_and_external_bindings_fail_closed() {
        let log = MerkleLog::from_hashes(&[[1;32],[2;32],[3;32]]);
        let proof = log.proof(2).unwrap();
        assert!(verify_bound_proof(&proof, &proof.root, &proof.leaf_hash, 3));
        assert!(!verify_bound_proof(&proof, &proof.root, &hex(&[4;32]), 3));
        assert!(!verify_bound_proof(&proof, &proof.root, &proof.leaf_hash, 4));
        let mut bad = proof.clone(); bad.leaf_index = 3;
        assert!(!verify_bound_proof(&bad, &proof.root, &proof.leaf_hash, 3));
        for text in ["f".to_string(), "é".repeat(32), "G".repeat(64), "F".repeat(64)] {
            bad = proof.clone(); bad.leaf_hash = text;
            assert!(!verify_proof(&bad, &proof.root));
        }
        bad = proof.clone(); bad.path[0].1 = false;
        assert!(!verify_bound_proof(&bad, &proof.root, &proof.leaf_hash, 3));
    }

    #[test]
    fn merkle_proof_roundtrip() {
        let mut log = MerkleLog::new();
        for i in 0..5u8 {
            log.push(hash_leaf(&[i]));
        }
        let root = hex(&log.root().unwrap());
        for i in 0..5 {
            let p = log.proof(i).unwrap();
            assert!(verify_proof(&p, &root), "proof {i} should verify");
        }
        let mut bad = log.proof(0).unwrap();
        bad.leaf_hash = hex(&hash_leaf(b"tampered"));
        assert!(!verify_proof(&bad, &root));
        assert!(log.proof(99).is_err());
    }
}
