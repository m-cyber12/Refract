-- Local adapter consent, not OAuth grants, OS permissions or connection status.
CREATE TABLE IF NOT EXISTS integration_policies (
 connector_id TEXT PRIMARY KEY,
 enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),
 categories_json TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(revision > 0)
);
UPDATE meta SET value='13' WHERE key='schema_version';
