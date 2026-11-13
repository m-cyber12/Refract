-- Upgrade intermediate Phase 7 databases as well as fresh installs. Migration 9
-- may already exist on a device before the derived-source index was introduced.
CREATE TABLE IF NOT EXISTS compression_sources (
 compression_id TEXT NOT NULL REFERENCES knowledge_compressions(id) ON DELETE CASCADE,
 item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
 source_fingerprint TEXT NOT NULL, PRIMARY KEY(compression_id,item_id)
);
CREATE INDEX IF NOT EXISTS compression_sources_item ON compression_sources(item_id,compression_id);
CREATE INDEX IF NOT EXISTS decision_sources_item ON decision_sources(item_id,decision_id);
INSERT OR IGNORE INTO compression_sources(compression_id,item_id,source_fingerprint)
 SELECT c.id,j.key,j.value FROM knowledge_compressions c,
 json_each(c.payload_json,'$.source_hashes') j JOIN items i ON i.id=j.key;
UPDATE meta SET value='10' WHERE key='schema_version';
