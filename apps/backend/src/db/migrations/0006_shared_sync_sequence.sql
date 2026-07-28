-- 0006_shared_sync_sequence.sql — one sequence behind the pull cursor.
--
-- 0004 replaced the timestamp watermark with a sequence, which was the right
-- move, but it created *two*: notes_seq_seq and tags_seq_seq. The pull cursor
-- is a single scalar compared against both — `WHERE n.seq > $2` for notes and
-- `WHERE t.seq > $2` for tags — so a note's sequence value and a tag's
-- sequence value were treated as points on one line when they were points on
-- two unrelated ones.
--
-- Concretely: touch six tags and the tag sequence reaches 6, so the cursor
-- comes back as 6. The next pull asks for notes with seq > 6 and skips the
-- first six notes ever written — permanently, because nothing renumbers them.
-- It happens just as easily the other way round.
--
-- This has been invisible only because the Dart client read a response field
-- the server had stopped sending, so `since` was never transmitted and every
-- pull silently restarted from zero. Repairing incremental pull without
-- repairing this would turn a masked bug into live, silent note loss.
--
-- One sequence, every existing row renumbered from it, and every device's
-- watermark reset so the corpus is walked once against the new ordering.

CREATE SEQUENCE IF NOT EXISTS sync_seq AS BIGINT;

-- Notes first, then tags, each in the order the server last touched them.
-- Two statements rather than one interleaved pass: the cursor only needs the
-- values to be comparable and monotonic, and a single statement cannot draw
-- from one sequence for two update targets.
WITH renumbered AS (
  SELECT id, nextval('sync_seq') AS new_seq
    FROM (
      SELECT id FROM notes
       ORDER BY COALESCE(server_updated_at, updated_at) ASC, id ASC
    ) ordered
)
UPDATE notes n
   SET seq = renumbered.new_seq
  FROM renumbered
 WHERE renumbered.id = n.id;

WITH renumbered AS (
  SELECT id, nextval('sync_seq') AS new_seq
    FROM (SELECT id FROM tags ORDER BY created_at ASC, id ASC) ordered
)
UPDATE tags t
   SET seq = renumbered.new_seq
  FROM renumbered
 WHERE renumbered.id = t.id;

ALTER TABLE notes ALTER COLUMN seq SET DEFAULT nextval('sync_seq');
ALTER TABLE tags  ALTER COLUMN seq SET DEFAULT nextval('sync_seq');

DROP SEQUENCE IF EXISTS notes_seq_seq;
DROP SEQUENCE IF EXISTS tags_seq_seq;

-- Every stored watermark refers to the old, incomparable numbering. Leaving it
-- would skip exactly the rows this migration exists to make reachable.
UPDATE device_acks SET last_pull_seq = 0;
