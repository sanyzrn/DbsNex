-- 0001_init.sql — Phase 2 base schema.
-- Written with IF NOT EXISTS so that a database previously created by the old
-- inline migrate() can adopt the runner without re-creating anything.

CREATE TABLE IF NOT EXISTS notes (
  id            TEXT PRIMARY KEY,
  type          TEXT NOT NULL CHECK (type IN ('text', 'voice', 'photo', 'file')),
  content       TEXT,
  media_uri     TEXT,
  media_hash    TEXT,
  duration_ms   INTEGER,
  created_at    TIMESTAMPTZ NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL,
  deleted_at    TIMESTAMPTZ,
  device_id     TEXT NOT NULL,
  rev           INTEGER NOT NULL,
  sync_state    TEXT NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS tags (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  color      TEXT,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS note_tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);

CREATE TABLE IF NOT EXISTS media_objects (
  media_hash  TEXT PRIMARY KEY,
  storage_key TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_acks (
  device_id    TEXT PRIMARY KEY,
  last_pull_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes (updated_at);
CREATE INDEX IF NOT EXISTS idx_notes_media_hash ON notes (media_hash);
CREATE INDEX IF NOT EXISTS idx_note_tags_tag ON note_tags (tag_id);
