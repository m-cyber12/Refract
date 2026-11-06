//! Phase 2 — Personal Memory: tags, collections, annotations, export,
//! and the Daily Edition foundation. All local; no cloud dependency.

use crate::Store;
use refract_core::{Annotation, Collection, Item, RefractError, RefractResult, Tag};
use rusqlite::params;

fn now_ts() -> RefractResult<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| RefractError::internal(e.to_string()))?
        .as_secs() as i64)
}

impl Store {
    /// Create a tag (idempotent by name). Returns the tag.
    pub fn add_tag(&self, name: &str, color: Option<&str>) -> RefractResult<Tag> {
        let name = name.trim();
        if name.is_empty() {
            return Err(RefractError::invalid("empty tag name"));
        }
        if let Some(t) = self.get_tag_by_name(name)? {
            return Ok(t);
        }
        let tag = Tag {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            color: color.map(|c| c.to_string()),
        };
        self.conn
            .execute(
                "INSERT INTO tags (id, name, color) VALUES (?1, ?2, ?3)",
                params![tag.id, tag.name, tag.color],
            )
            .map_err(|e| RefractError::storage(format!("add tag: {e}")))?;
        Ok(tag)
    }

    pub fn get_tag_by_name(&self, name: &str) -> RefractResult<Option<Tag>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, color FROM tags WHERE name = ?1")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut rows = stmt
            .query_map(params![name], |r| {
                Ok(Tag {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    color: r.get(2)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        Ok(rows.next().transpose().map_err(|e| RefractError::storage(e.to_string()))?)
    }

    pub fn list_tags(&self) -> RefractResult<Vec<Tag>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, color FROM tags ORDER BY name")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Tag {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    color: r.get(2)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Attach a tag to an item (creating the tag if needed).
    pub fn tag_item(&self, item_id: &str, tag_name: &str) -> RefractResult<Tag> {
        let tag = self.add_tag(tag_name, None)?;
        self.conn
            .execute(
                "INSERT OR IGNORE INTO item_tags (item_id, tag_id) VALUES (?1, ?2)",
                params![item_id, tag.id],
            )
            .map_err(|e| RefractError::storage(format!("tag item: {e}")))?;
        Ok(tag)
    }

    pub fn list_tags_for_item(&self, item_id: &str) -> RefractResult<Vec<Tag>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT t.id, t.name, t.color FROM tags t
                 JOIN item_tags it ON it.tag_id = t.id
                 WHERE it.item_id = ?1 ORDER BY t.name",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![item_id], |r| {
                Ok(Tag {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    color: r.get(2)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    pub fn create_collection(&self, name: &str) -> RefractResult<Collection> {
        let name = name.trim();
        if name.is_empty() {
            return Err(RefractError::invalid("empty collection name"));
        }
        let c = Collection {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            created_ts: now_ts()?,
        };
        self.conn
            .execute(
                "INSERT INTO collections (id, name, created_ts) VALUES (?1, ?2, ?3)",
                params![c.id, c.name, c.created_ts],
            )
            .map_err(|e| RefractError::storage(format!("create collection: {e}")))?;
        Ok(c)
    }

    pub fn list_collections(&self) -> RefractResult<Vec<Collection>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, created_ts FROM collections ORDER BY created_ts DESC")
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Collection {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    created_ts: r.get(2)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    pub fn add_item_to_collection(&self, item_id: &str, collection_id: &str) -> RefractResult<()> {
        self.conn
            .execute(
                "INSERT OR IGNORE INTO item_collections (item_id, collection_id) VALUES (?1, ?2)",
                params![item_id, collection_id],
            )
            .map_err(|e| RefractError::storage(format!("add to collection: {e}")))?;
        Ok(())
    }

    /// Add an annotation anchored to a quote within an item.
    pub fn add_annotation(
        &self,
        item_id: &str,
        quote: &str,
        note: Option<&str>,
        block_idx: Option<u32>,
    ) -> RefractResult<Annotation> {
        let quote = quote.trim();
        if quote.is_empty() {
            return Err(RefractError::invalid("empty annotation quote"));
        }
        let a = Annotation {
            id: uuid::Uuid::new_v4().to_string(),
            item_id: item_id.to_string(),
            quote: quote.to_string(),
            note: note.map(|n| n.to_string()),
            block_idx,
            visibility: "private".to_string(),
            created_ts: now_ts()?,
        };
        self.conn
            .execute(
                "INSERT INTO annotations (id, item_id, quote, note, block_idx, visibility, created_ts)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![a.id, a.item_id, a.quote, a.note, a.block_idx, a.visibility, a.created_ts],
            )
            .map_err(|e| RefractError::storage(format!("add annotation: {e}")))?;
        Ok(a)
    }

    pub fn list_annotations(&self, item_id: &str) -> RefractResult<Vec<Annotation>> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, item_id, quote, note, block_idx, visibility, created_ts
                 FROM annotations WHERE item_id = ?1 ORDER BY created_ts",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![item_id], |r| {
                Ok(Annotation {
                    id: r.get(0)?,
                    item_id: r.get(1)?,
                    quote: r.get(2)?,
                    note: r.get(3)?,
                    block_idx: r.get::<_, Option<i64>>(4)?.map(|v| v as u32),
                    visibility: r.get(5)?,
                    created_ts: r.get(6)?,
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }

    /// Export the whole library as a JSON string (user sovereignty, spec §3.3).
    pub fn export_all(&self) -> RefractResult<String> {
        let items = self.list_items(10_000, 0)?;
        let mut full: Vec<Item> = Vec::new();
        for mut it in items {
            it.blocks = self.load_blocks(&it.id)?;
            full.push(it);
        }
        let tags = self.list_tags()?;
        let collections = self.list_collections()?;
        let payload = serde_json::json!({
            "format": "refract-export",
            "version": 1,
            "exported_ts": now_ts()?,
            "items": full,
            "tags": tags,
            "collections": collections,
        });
        serde_json::to_string_pretty(&payload)
            .map_err(|e| RefractError::internal(format!("export json: {e}")))
    }

    /// Daily Edition foundation: items from the last `days` days, newest first.
    pub fn daily_edition(&self, days: u32) -> RefractResult<Vec<Item>> {
        let since = now_ts()? - days as i64 * 86_400;
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, source_url, source_type, import_ts, content_hash, title, author,
                        language, extraction_confidence, status
                 FROM items WHERE import_ts >= ?1 ORDER BY import_ts DESC LIMIT 50",
            )
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let rows = stmt
            .query_map(params![since], |r| {
                Ok(Item {
                    id: r.get(0)?,
                    source_url: r.get(1)?,
                    source_type: crate::parse_source_type(&r.get::<_, String>(2)?),
                    import_ts: r.get(3)?,
                    content_hash: r.get(4)?,
                    title: r.get(5)?,
                    author: r.get(6)?,
                    language: r.get(7)?,
                    extraction_confidence: r.get::<_, f64>(8)? as f32,
                    status: crate::parse_status(&r.get::<_, String>(9)?),
                    blocks: Vec::new(),
                })
            })
            .map_err(|e| RefractError::storage(e.to_string()))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| RefractError::storage(e.to_string()))?);
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;
    use refract_core::{Block, BlockKind, ImportStatus, SourceType};

    fn seed(store: &mut Store) -> Item {
        let item = Item {
            id: "i1".into(),
            source_url: None,
            source_type: SourceType::Text,
            import_ts: 1_700_000_000,
            content_hash: "cd".repeat(32),
            title: Some("Doc".into()),
            author: None,
            language: None,
            extraction_confidence: 1.0,
            status: ImportStatus::Ready,
            blocks: vec![Block { idx: 0, kind: BlockKind::Paragraph, text: "hello".into() }],
        };
        store.insert_item(&item, b"raw", &item.content_hash).unwrap();
        item
    }

    #[test]
    fn tags_collections_annotations_export() {
        let mut store = Store::open_in_memory().unwrap();
        let item = seed(&mut store);

        let tag = store.tag_item(&item.id, "research").unwrap();
        assert_eq!(tag.name, "research");
        assert_eq!(store.list_tags_for_item(&item.id).unwrap().len(), 1);

        let c = store.create_collection("Reading list").unwrap();
        store.add_item_to_collection(&item.id, &c.id).unwrap();
        assert_eq!(store.list_collections().unwrap().len(), 1);

        let a = store.add_annotation(&item.id, "hello", Some("my note"), Some(0)).unwrap();
        assert_eq!(a.visibility, "private");
        assert_eq!(store.list_annotations(&item.id).unwrap().len(), 1);

        let json = store.export_all().unwrap();
        assert!(json.contains("refract-export"));
        assert!(json.contains("research"));

        let edition = store.daily_edition(3650).unwrap();
        assert_eq!(edition.len(), 1);
    }
}
