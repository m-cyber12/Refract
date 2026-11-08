-- Local Recall index. Derived vectors never replace source blocks or originals.
-- The versioned encoder is deterministic concept expansion + feature hashing,
-- not a downloaded neural embedding model.
CREATE TABLE IF NOT EXISTS recall_vectors (
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    block_idx INTEGER NOT NULL,
    encoder TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    vector_json TEXT NOT NULL,
    PRIMARY KEY (item_id, block_idx)
);
UPDATE meta SET value = '6' WHERE key = 'schema_version';
