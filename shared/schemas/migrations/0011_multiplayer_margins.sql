-- New authenticated workspaces are deliberately separate from legacy anonymous
-- CRDT/outbox prototypes. Existing private annotations are never auto-promoted.
CREATE TABLE IF NOT EXISTS margin_identity(id INTEGER PRIMARY KEY CHECK(id=1),private_json TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS margin_workspaces(
 id TEXT PRIMARY KEY, policy_json TEXT NOT NULL, state BLOB NOT NULL,
 exchange_enabled INTEGER NOT NULL DEFAULT 0, local_revision INTEGER NOT NULL DEFAULT 0,
 created_ts INTEGER NOT NULL, updated_ts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS margin_contacts(
 workspace_id TEXT NOT NULL REFERENCES margin_workspaces(id) ON DELETE CASCADE,
 peer_key TEXT NOT NULL, contact_json TEXT NOT NULL, PRIMARY KEY(workspace_id,peer_key)
);
CREATE TABLE IF NOT EXISTS margin_bindings(
 workspace_id TEXT NOT NULL REFERENCES margin_workspaces(id) ON DELETE CASCADE,
 document_id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
 PRIMARY KEY(workspace_id,document_id), UNIQUE(workspace_id,item_id)
);
CREATE TABLE IF NOT EXISTS margin_transfers(
 hash TEXT PRIMARY KEY,workspace_id TEXT NOT NULL REFERENCES margin_workspaces(id) ON DELETE CASCADE,
 direction TEXT NOT NULL,kind TEXT NOT NULL,peer_key TEXT NOT NULL,local_revision INTEGER NOT NULL,
 packet TEXT,created_ts INTEGER NOT NULL,acknowledged_ts INTEGER
);
CREATE INDEX IF NOT EXISTS margin_transfers_workspace ON margin_transfers(workspace_id,created_ts);
CREATE TABLE IF NOT EXISTS margin_history(
 id INTEGER PRIMARY KEY,workspace_id TEXT NOT NULL REFERENCES margin_workspaces(id) ON DELETE CASCADE,
 kind TEXT NOT NULL, detail TEXT NOT NULL, recorded_ts INTEGER NOT NULL
);
UPDATE meta SET value='11' WHERE key='schema_version';
