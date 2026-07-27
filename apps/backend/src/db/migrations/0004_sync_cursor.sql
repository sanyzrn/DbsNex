-- 0004_sync_cursor.sql — replace the timestamp watermark with a sequence.
--
-- The pull cursor used to be a timestamp produced by the Node process clock
-- while rows were stamped with the PostgreSQL clock. Any skew between those two
-- clocks silently dropped rows forever. A monotonic sequence removes clocks
-- from the protocol entirely.

CREATE SEQUENCE IF NOT EXISTS notes_seq_seq AS BIGINT;
CREATE SEQUENCE IF NOT EXISTS tags_seq_seq  AS BIGINT;

-- ---------------------------------------------------------------- notes
ALTER TABLE notes ADD COLUMN IF NOT EXISTS seq BIGINT;
UPDATE notes SET seq = nextval('notes_seq_seq') WHERE seq IS NULL;
ALTER TABLE notes ALTER COLUMN seq SET NOT NULL;
ALTER TABLE notes ALTER COLUMN seq SET DEFAULT nextval('notes_seq_seq');

-- True when the server's merge produced a row different from what the pushing
-- device sent. Lets pull skip pure echoes without hiding real merge results.
ALTER TABLE notes
  ADD COLUMN IF NOT EXISTS merged_by_server BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_notes_user_seq ON notes (user_id, seq);

-- ---------------------------------------------------------------- tags
ALTER TABLE tags ADD COLUMN IF NOT EXISTS seq BIGINT;
UPDATE tags SET seq = nextval('tags_seq_seq') WHERE seq IS NULL;
ALTER TABLE tags ALTER COLUMN seq SET NOT NULL;
ALTER TABLE tags ALTER COLUMN seq SET DEFAULT nextval('tags_seq_seq');

CREATE INDEX IF NOT EXISTS idx_tags_user_seq ON tags (user_id, seq);

-- ---------------------------------------------------------- device_acks
ALTER TABLE device_acks
  ADD COLUMN IF NOT EXISTS last_pull_seq BIGINT NOT NULL DEFAULT 0;
