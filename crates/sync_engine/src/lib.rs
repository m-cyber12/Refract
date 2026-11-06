//! Sync engine (spec §C4/C5).
//!
//! Design: **opportunistic**, never a hard dependency. Local changes are
//! preserved in an outbox; CRDT state can be exported/imported over any
//! channel (WebRTC/iroh/relay are transport research, Phase 6). E2E encryption
//! of sync payloads is required before any relay ships.

use refract_core::{RefractError, RefractResult};
use rusqlite::{params, Connection};

/// A queued sync payload awaiting transport.
pub struct OutboxEntry {
    pub id: String,
    pub doc_id: String,
    pub payload: Vec<u8>,
    pub created_ts: i64,
    pub status: String,
}

/// Storage-backed outbox. Works fully offline.
pub struct SyncEngine<'a> {
    conn: &'a Connection,
}

impl<'a> SyncEngine<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        SyncEngine { conn }
    }

    pub fn init_schema(&self) -> RefractResult<()> {
        self.conn
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS workspaces (
                     id TEXT PRIMARY KEY, name TEXT NOT NULL, created_ts INTEGER NOT NULL
                 );
                 CREATE TABLE IF NOT EXISTS sync_outbox (
                     id TEXT PRIMARY KEY,
                     doc_id TEXT NOT NULL,
                     payload BLOB NOT NULL,
                     created_ts INTEGER NOT NULL,
                     status TEXT NOT NULL DEFAULT 'pending'
                 );",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(())
    }

    pub fn create_workspace(&self, name: &str) -> RefractResult<String> {
        let id = uuid::Uuid::new_v4().to_string();
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| RefractError::internal(e.to_string()))?
            .as_secs() as i64;
        self.conn
            .execute(
                "INSERT INTO workspaces (id, name, created_ts) VALUES (?1, ?2, ?3)",
                params![id, name, ts],
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(id)
    }

    pub fn list_workspaces(&self) -> RefractResult<Vec<(String, String)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name FROM workspaces ORDER BY created_ts DESC")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Queue a CRDT state payload for a workspace. Preserved until acked.
    pub fn enqueue(&self, doc_id: &str, payload: &[u8]) -> RefractResult<String> {
        let id = uuid::Uuid::new_v4().to_string();
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| RefractError::internal(e.to_string()))?
            .as_secs() as i64;
        self.conn
            .execute(
                "INSERT INTO sync_outbox (id, doc_id, payload, created_ts, status) VALUES (?1,?2,?3,?4,'pending')",
                params![id, doc_id, payload, ts],
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(id)
    }

    pub fn pending(&self, limit: u32) -> RefractResult<Vec<OutboxEntry>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, doc_id, payload, created_ts, status FROM sync_outbox WHERE status='pending' ORDER BY created_ts LIMIT ?1")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![limit], |r| {
                Ok(OutboxEntry {
                    id: r.get(0)?,
                    doc_id: r.get(1)?,
                    payload: r.get(2)?,
                    created_ts: r.get(3)?,
                    status: r.get(4)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    pub fn mark_sent(&self, id: &str) -> RefractResult<()> {
        self.conn
            .execute("UPDATE sync_outbox SET status='sent' WHERE id = ?1", params![id])
            .map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_and_outbox_offline() {
        let conn = Connection::open_in_memory().unwrap();
        let engine = SyncEngine::new(&conn);
        engine.init_schema().unwrap();
        let ws = engine.create_workspace("team").unwrap();
        assert_eq!(engine.list_workspaces().unwrap(), vec![(ws, "team".to_string())]);
        let id = engine.enqueue("doc1", b"crdt-state").unwrap();
        assert_eq!(engine.pending(10).unwrap().len(), 1);
        engine.mark_sent(&id).unwrap();
        assert!(engine.pending(10).unwrap().is_empty());
    }
}
