-- 0002_server_updated_at.sql
--
-- The previous inline version was:
--   ALTER TABLE notes ADD COLUMN IF NOT EXISTS server_updated_at
--     TIMESTAMPTZ NOT NULL DEFAULT NOW();
--
-- On a populated table that stamps every existing row with the migration
-- instant, which (a) puts every row above every device watermark at once and
-- (b) collapses the ordering the cursor depends on. Backfill from updated_at,
-- which is the real history and is already present on every row.

ALTER TABLE notes ADD COLUMN IF NOT EXISTS server_updated_at TIMESTAMPTZ;

UPDATE notes
   SET server_updated_at = updated_at
 WHERE server_updated_at IS NULL;

ALTER TABLE notes ALTER COLUMN server_updated_at SET NOT NULL;
ALTER TABLE notes ALTER COLUMN server_updated_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_notes_server_updated_at
  ON notes (server_updated_at);
