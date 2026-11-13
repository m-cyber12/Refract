-- Capture duplicate lookup. No originals, user organization or prior data rewritten.
BEGIN IMMEDIATE;
CREATE INDEX IF NOT EXISTS idx_items_capture_hash ON items(content_hash, source_type, source_url);
CREATE INDEX IF NOT EXISTS idx_items_capture_source ON items(source_url, content_hash);
INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','14');
COMMIT;
