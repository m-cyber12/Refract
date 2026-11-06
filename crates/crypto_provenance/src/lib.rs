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
    pub leaf_hash: String,
    pub root: String,
    pub path: Vec<(String, bool)>, // (sibling hash, sibling is on the right)
    pub statement: String,
}

const STATEMENT: &str = "This proof shows the record's hash is included in the local append-only log. \
It does NOT prove who created the file or that its contents were authentic at the source.";

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
            leaf_hash: hex(&self.leaves[index]),
            root: hex(&root),
            path,
            statement: STATEMENT.to_string(),
        })
    }
}

/// Verify a Merkle inclusion proof against an expected root.
pub fn verify_proof(proof: &MerkleProof, expected_root: &str) -> bool {
    if proof.root != expected_root {
        return false;
    }
    let mut acc: [u8; 32] = match hex_decode(&proof.leaf_hash) {
        Some(b) if b.len() == 32 => b.try_into().unwrap(),
        _ => return false,
    };
    for (sib, sib_right) in &proof.path {
        let sib_arr: [u8; 32] = match hex_decode(sib).and_then(|b| b.try_into().ok()) {
            Some(a) => a,
            None => return false,
        };
        acc = if *sib_right { hash_node(&acc, &sib_arr) } else { hash_node(&sib_arr, &acc) };
    }
    hex(&acc) == expected_root
}

fn hex_decode(s: &str) -> Option<Vec<u8>> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

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
