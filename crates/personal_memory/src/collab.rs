//! Phase 5 — Multiplayer Margins: workspaces, CRDT annotation docs, outbox.
//!
//! Privacy controls (spec §C5): annotations default to private; sharing is
//! explicit per annotation/workspace. The original source document is never
//! shared automatically — only the annotation payload.

use crate::Store;
use annotation_engine::AnnotationDoc;
use refract_core::{RefractError, RefractResult};
use sync_engine::SyncEngine;

impl Store {
    fn sync(&self) -> SyncEngine<'_> {
        let engine = SyncEngine::new(&self.conn);
        engine.init_schema().ok();
        engine
    }

    pub fn create_workspace(&self, name: &str) -> RefractResult<String> {
        self.sync().create_workspace(name)
    }

    pub fn list_workspaces(&self) -> RefractResult<Vec<(String, String)>> {
        self.sync().list_workspaces()
    }

    /// Enqueue a CRDT state payload for a workspace (opportunistic sync).
    pub fn enqueue_sync(&self, doc_id: &str, payload: &[u8]) -> RefractResult<String> {
        self.sync().enqueue(doc_id, payload)
    }

    pub fn pending_sync(&self, limit: u32) -> RefractResult<usize> {
        Ok(self.sync().pending(limit)?.len())
    }

    /// Build (or load) the CRDT doc for a workspace and upsert an annotation.
    pub fn upsert_shared_annotation(
        &self,
        workspace_id: &str,
        annotation_id: &str,
        payload_json: &str,
    ) -> RefractResult<Vec<u8>> {
        let mut doc = AnnotationDoc::new();
        // Merge any previously queued state for this workspace if present.
        for entry in self.sync().pending(100)? {
            if entry.doc_id == workspace_id {
                doc.merge(&entry.payload).ok();
            }
        }
        doc.upsert(annotation_id, payload_json)?;
        let state = doc.export_state()?;
        self.sync().enqueue(workspace_id, &state)?;
        Ok(state)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    #[test]
    fn workspace_collab_flow() {
        let store = Store::open_in_memory().unwrap();
        let ws = store.create_workspace("research").unwrap();
        assert_eq!(store.list_workspaces().unwrap().len(), 1);
        let state = store
            .upsert_shared_annotation(&ws, "a1", r#"{"quote":"prism","note":"shared"}"#)
            .unwrap();
        assert!(!state.is_empty());
        assert!(store.pending_sync(10).unwrap() >= 1);
    }
}
