//! Personal Memory: local-first SQLite storage layer.
//!
//! Owns schema migrations, item/block persistence and full-text search.
//! All writes are transactional; the FTS index is kept in sync by triggers.

use refract_core::{
    Block, BlockKind, ImportStatus, Item, RefractError, RefractResult, SourceType,
};
use rusqlite::{params, Connection};
use std::path::{Path, PathBuf};

pub mod memory;

const MIGRATION_0001: &str = include_str!("../../../shared/schemas/migrations/0001_init.sql");
const MIGRATION_0002: &str = include_str!("../../../shared/schemas/migrations/0002_personal_memory.sql");
const MIGRATION_0003: &str = include_str!("../../../shared/schemas/migrations/0003_xray_vault.sql");

pub struct Store {
    conn: Connection,
    /// Directory where content blobs are written (<db>.blobs).
    pub blob_dir: PathBuf,
}

fn parse_source_type(s: &str) -> SourceType {
    match s {
        "url" => SourceType::Url,
        "shared_text" => SourceType::SharedText,
        "html" => SourceType::Html,
        "pdf" => SourceType::Pdf,
        "markdown" => SourceType::Markdown,
        "file" => SourceType::File,
        _ => SourceType::Text,
    }
}

fn parse_status(s: &str) -> ImportStatus {
    match s {
        "processing" => ImportStatus::Processing,
        "failed" => ImportStatus::Failed,
        _ => ImportStatus::Ready,
    }
}

fn parse_block_kind(s: &str) -> BlockKind {
    match s {
        "heading1" => BlockKind::Heading1,
        "heading2" => BlockKind::Heading2,
        "heading3" => BlockKind::Heading3,
        "list_item" => BlockKind::ListItem,
        "quote" => BlockKind::Quote,
        "code" => BlockKind::Code,
        "image" => BlockKind::Image,
        "divider" => BlockKind::Divider,
        _ => BlockKind::Paragraph,
    }
}

impl Store {
    /// Open (or create) a store at `db_path` and run migrations.
    pub fn open<P: AsRef<Path>>(db_path: P) -> RefractResult<Store> {
        let conn = Connection::open(&db_path)
            .map_err(|e| RefractError::storage(format!("open db: {e}")))?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(|e| RefractError::storage(format!("pragma: {e}")))?;
        let mut store = Store {
            conn,
            blob_dir: db_path.as_ref().to_path_buf().with_extension("blobs"),
        };
        store.migrate()?;
        Ok(store)
    }

    /// In-memory store for tests.
    #[cfg(test)]
    pub fn open_in_memory() -> RefractResult<Store> {
        let conn = Connection::open_in_memory()
            .map_err(|e| RefractError::storage(format!("open mem db: {e}")))?;
        let mut store = Store {
            conn,
            blob_dir: std::env::temp_dir().join(format!("refract-test-{}", uuid::Uuid::new_v4())),
        };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> RefractResult<()> {
        let version: i64 = self
            .conn
            .query_row("SELECT value FROM meta WHERE key='schema_version'", [], |r| {
                r.get::<_, String>(0)
            })
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        if version < 1 {
            self.conn
                .execute_batch(MIGRATION_0001)
                .map_err(|e| RefractError::storage(format!("migration 0001: {e}")))?;
        }
        if version < 2 {
            self.conn
                .execute_batch(MIGRATION_0002)
                .map_err(|e| RefractError::storage(format!("migration 0002: {e}")))?;
        }
        Ok(())
    }

    /// Persist a compiled item: item row, blocks, and the immutable original blob.
    pub fn insert_item(
        &mut self,
        item: &Item,
        original_bytes: &[u8],
        original_hash: &str,
    ) -> RefractResult<()> {
        std::fs::create_dir_all(&self.blob_dir)
            .map_err(|e| RefractError::storage(format!("blob dir: {e}")))?;
        let blob_path = self.blob_dir.join(format!("{}.original", item.id));
        std::fs::write(&blob_path, original_bytes)
            .map_err(|e| RefractError::storage(format!("write blob: {e}")))?;

        let tx = self
            .conn
            .transaction()
            .map_err(|e| RefractError::storage(format!("tx: {e}")))?;
        tx.execute(
            "INSERT INTO items (id, source_url, source_type, import_ts, content_hash,
                                title, author, language, extraction_confidence, status)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                item.id,
                item.source_url,
                item.source_type.as_str(),
                item.import_ts,
                item.content_hash,
                item.title,
                item.author,
                item.language,
                item.extraction_confidence,
                "ready",
            ],
        )
        .map_err(|e| RefractError::storage(format!("insert item: {e}")))?;
        tx.execute(
            "INSERT INTO blobs (item_id, kind, path, sha256) VALUES (?1, 'original', ?2, ?3)",
            params![item.id, blob_path.to_string_lossy(), original_hash],
        )
        .map_err(|e| RefractError::storage(format!("insert blob: {e}")))?;
        for b in &item.blocks {
            tx.execute(
                "INSERT INTO blocks (item_id, idx, kind, text) VALUES (?1, ?2, ?3, ?4)",
                params![item.id, b.idx, b.kind.as_str(), b.text],
            )
            .map_err(|e| RefractError::storage(format!("insert block: {e}")))?;
        }
        tx.commit()
            .map_err(|e| RefractError::storage(format!("commit: {e}")))?;
        Ok(())
    }

    fn row_to_item(
        &self,
        row: &rusqlite::Row,
    ) -> rusqlite::Result<Item> {
        let st: String = row.get("source_type")?;
        let status: String = row.get("status")?;
        Ok(Item {
            id: row.get("id")?,
            source_url: row.get("source_url")?,
            source_type: parse_source_type(&st),
            import_ts: row.get("import_ts")?,
            content_hash: row.get("content_hash")?,
            title: row.get("title")?,
            author: row.get("author")?,
            language: row.get("language")?,
            extraction_confidence: row.get::<_, f64>("extraction_confidence")? as f32,
            status: parse_status(&status),
            blocks: Vec::new(),
        })
    }

    fn load_blocks(&self, item_id: &str) -> RefractResult<Vec<Block>> {
        let mut stmt = self
            .conn
            .prepare("SELECT idx, kind, text FROM blocks WHERE item_id = ?1 ORDER BY idx")
            .map_err(|e| RefractError::storage(format!("prep blocks: {e}")))?;
        let rows = stmt
            .query_map(params![item_id], |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                ))
            })
            .map_err(|e| RefractError::storage(format!("query blocks: {e}")))?;
        let mut blocks = Vec::new();
        for row in rows {
            let (idx, kind, text) = row.map_err(|e| RefractError::storage(e.to_string()))?;
            blocks.push(Block {
                idx: idx as u32,
                kind: parse_block_kind(&kind),
                text,
            });
        }
        Ok(blocks)
    }

    /// List items newest-first.
    pub fn list_items(&self, limit: u32, offset: u32) -> RefractResult<Vec<Item>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, source_url, source_type, import_ts, content_hash, title, author,
                        language, extraction_confidence, status
                 FROM items ORDER BY import_ts DESC, id DESC LIMIT ?1 OFFSET ?2",
            )
            .map_err(|e| RefractError::storage(format!("prep list: {e}")))?;
        let rows = stmt
            .query_map(params![limit, offset], |r| self.row_to_item(r))
            .map_err(|e| RefractError::storage(format!("list: {e}")))?;
        let mut items = Vec::new();
        for r in rows {
            items.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(items)
    }

    /// Fetch one item with its blocks.
    pub fn get_item(&self, id: &str) -> RefractResult<Option<Item>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, source_url, source_type, import_ts, content_hash, title, author,
                        language, extraction_confidence, status
                 FROM items WHERE id = ?1",
            )
            .map_err(|e| RefractError::storage(format!("prep get: {e}")))?;
        let mut rows = stmt
            .query_map(params![id], |r| self.row_to_item(r))
            .map_err(|e| RefractError::storage(format!("get: {e}")))?;
        let Some(row) = rows.next() else {
            return Ok(None);
        };
        let mut item = row.map_err(|e| RefractError::storage(e.to_string()))?;
        item.blocks = self.load_blocks(&item.id)?;
        Ok(Some(item))
    }

    /// Full-text search over extracted content (FTS5).
    pub fn search(&self, query: &str) -> RefractResult<Vec<Item>> {
        let q = query.trim();
        if q.is_empty() {
            return Ok(Vec::new());
        }
        // Quote each term to make MATCH syntax safe for arbitrary user input.
        let match_expr = q
            .split_whitespace()
            .map(|t| format!("\"{}\"", t.replace('"', "")))
            .collect::<Vec<_>>()
            .join(" ");
        let mut stmt = self
            .conn
            .prepare(
                "SELECT i.id, i.source_url, i.source_type, i.import_ts, i.content_hash,
                        i.title, i.author, i.language, i.extraction_confidence, i.status
                 FROM blocks_fts f JOIN blocks b ON b.id = f.rowid
                 JOIN items i ON i.id = b.item_id
                 WHERE blocks_fts MATCH ?1
                 GROUP BY i.id ORDER BY i.import_ts DESC LIMIT 100",
            )
            .map_err(|e| RefractError::storage(format!("prep search: {e}")))?;
        let rows = stmt
            .query_map(params![match_expr], |r| self.row_to_item(r))
            .map_err(|e| RefractError::storage(format!("search: {e}")))?;
        let mut items = Vec::new();
        for r in rows {
            items.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(items)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use refract_core::SourceType;

    fn sample_item(id: &str) -> Item {
        Item {
            id: id.to_string(),
            source_url: Some("https://example.com".into()),
            source_type: SourceType::Text,
            import_ts: 1_700_000_000,
            content_hash: "ab".repeat(32),
            title: Some("Hello".into()),
            author: None,
            language: None,
            extraction_confidence: 0.9,
            status: ImportStatus::Ready,
            blocks: vec![
                Block { idx: 0, kind: BlockKind::Heading1, text: "Hello".into() },
                Block { idx: 1, kind: BlockKind::Paragraph, text: "world of refraction".into() },
            ],
        }
    }

    #[test]
    fn insert_list_get_search() {
        let mut store = Store::open_in_memory().unwrap();
        let item = sample_item("id-1");
        store.insert_item(&item, b"raw bytes", &item.content_hash).unwrap();

        let list = store.list_items(10, 0).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].title.as_deref(), Some("Hello"));

        let got = store.get_item("id-1").unwrap().unwrap();
        assert_eq!(got.blocks.len(), 2);
        assert_eq!(got.blocks[1].text, "world of refraction");

        let hits = store.search("refraction").unwrap();
        assert_eq!(hits.len(), 1);
        assert!(store.search("nonexistentterm").unwrap().is_empty());
        assert!(store.get_item("nope").unwrap().is_none());
    }
}
