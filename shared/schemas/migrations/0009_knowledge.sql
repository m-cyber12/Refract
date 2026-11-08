-- Explicit user decisions and optional derived knowledge; originals stay independent.
CREATE TABLE IF NOT EXISTS knowledge_decisions (
 id TEXT PRIMARY KEY, title TEXT NOT NULL, context TEXT NOT NULL,
 options_json TEXT NOT NULL, selected_option TEXT NOT NULL, reasoning TEXT NOT NULL,
 decision_ts INTEGER NOT NULL, expected_outcome TEXT NOT NULL, review_ts INTEGER,
 project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
 created_ts INTEGER NOT NULL, updated_ts INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS decision_sources (
 decision_id TEXT NOT NULL REFERENCES knowledge_decisions(id) ON DELETE CASCADE,
 item_id TEXT NOT NULL REFERENCES items(id), PRIMARY KEY(decision_id,item_id)
);
CREATE TABLE IF NOT EXISTS decision_revisions (
 id INTEGER PRIMARY KEY, decision_id TEXT NOT NULL REFERENCES knowledge_decisions(id),
 recorded_ts INTEGER NOT NULL, snapshot_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS knowledge_compressions (
 id TEXT PRIMARY KEY, title TEXT NOT NULL, scope_kind TEXT NOT NULL,
 scope_id TEXT, selection_json TEXT NOT NULL, payload_json TEXT NOT NULL,
 created_ts INTEGER NOT NULL, generated_ts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS source_history (
 id INTEGER PRIMARY KEY, item_id TEXT NOT NULL REFERENCES items(id),
 stage TEXT NOT NULL, representation_kind TEXT NOT NULL, recorded_ts INTEGER NOT NULL,
 version TEXT NOT NULL, fingerprint TEXT NOT NULL, explanation TEXT NOT NULL,
 UNIQUE(item_id,stage,version,fingerprint)
);
-- A graph is a navigation projection over existing domain records, not a second
-- knowledge store. Suggestions retain their original basis/confidence/dismissal.
CREATE VIEW IF NOT EXISTS knowledge_nodes AS
 SELECT 'document' AS kind,i.id,COALESCE(i.title,i.id) AS label,i.import_ts AS ts,i.id AS source_item_id,NULL AS block_idx,'Stored source; capture time' AS detail FROM items i WHERE i.sense_decision!='ignore'
 UNION ALL SELECT 'topic',id,name,created_ts,NULL,NULL,'Topic association, not a belief' FROM topics
 UNION ALL SELECT 'project',id,name,created_ts,NULL,NULL,'Explicit Project Space' FROM projects
 UNION ALL SELECT 'entity',id,name,created_ts,NULL,NULL,'Extracted entity candidate' FROM entities
 UNION ALL SELECT 'note',a.id,substr(COALESCE(a.note,a.quote),1,100),a.created_ts,a.item_id,a.block_idx,'User annotation' FROM annotations a JOIN items i ON i.id=a.item_id WHERE i.sense_decision!='ignore'
 UNION ALL SELECT 'event',e.id,e.title,e.event_ts,e.item_id,e.block_idx,'Date candidate / user review: '||e.status FROM signal_events e JOIN items i ON i.id=e.item_id WHERE e.status!='dismissed' AND i.sense_decision!='ignore'
 UNION ALL SELECT 'decision',id,title,decision_ts,NULL,NULL,'Explicit user-recorded decision' FROM knowledge_decisions WHERE archived=0;
CREATE VIEW IF NOT EXISTS knowledge_edges AS
 SELECT 'document:'||item_id AS source_key,'topic:'||topic_id AS target_key,'topic_membership' AS kind,'Stored topic association' AS basis,1.0 AS confidence,NULL AS relationship_id FROM item_topics
 UNION ALL SELECT 'document:'||item_id,'entity:'||entity_id,'entity_mention','Extracted entity candidate',0.5,NULL FROM item_entities
 UNION ALL SELECT 'document:'||item_id,'project:'||project_id,'project_reference','Explicitly added project reference',1.0,NULL FROM project_items
 UNION ALL SELECT 'document:'||item_id,'note:'||id,'annotation','User-created annotation',1.0,NULL FROM annotations
 UNION ALL SELECT 'document:'||item_id,'event:'||id,'source_date','Date evidence; not automatically confirmed',0.5,NULL FROM signal_events WHERE status!='dismissed'
 UNION ALL SELECT 'document:'||item_id,'decision:'||decision_id,'decision_support','User-linked supporting source',1.0,NULL FROM decision_sources
 UNION ALL SELECT 'project:'||project_id,'decision:'||id,'project_decision','User-recorded project association',1.0,NULL FROM knowledge_decisions WHERE project_id IS NOT NULL AND archived=0
 UNION ALL SELECT 'document:'||r.source_item_id,'document:'||r.target_item_id,r.kind,r.basis,r.confidence,r.id FROM relationships r WHERE r.dismissed=0 AND (r.kind!='same_project' OR EXISTS(SELECT 1 FROM project_items pa JOIN project_items pb USING(project_id) WHERE pa.item_id=r.source_item_id AND pb.item_id=r.target_item_id));
UPDATE meta SET value='9' WHERE key='schema_version';
