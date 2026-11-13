-- Different collaborators can independently assign shared document identities
-- to the same source. Private local matching must allow many aliases per item.
BEGIN;
CREATE TABLE margin_bindings_next(
 workspace_id TEXT NOT NULL REFERENCES margin_workspaces(id) ON DELETE CASCADE,
 document_id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
 PRIMARY KEY(workspace_id,document_id)
);
INSERT INTO margin_bindings_next SELECT workspace_id,document_id,item_id FROM margin_bindings;
DROP TABLE margin_bindings;
ALTER TABLE margin_bindings_next RENAME TO margin_bindings;
CREATE INDEX margin_bindings_item ON margin_bindings(workspace_id,item_id);
UPDATE meta SET value='12' WHERE key='schema_version';
COMMIT;
