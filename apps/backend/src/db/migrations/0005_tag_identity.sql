-- 0005_tag_identity.sql — make the tag natural key the merge key.
--
-- tags.name carried a global UNIQUE constraint while the upsert conflicted on
-- (id). Offline-first guarantees the same name will be minted with different
-- UUIDs on different devices, so the second push hit a 23505 and broke sync for
-- that user permanently.
--
-- Identity is now (user_id, lower(name)). Case-variant duplicates created
-- before this migration are folded into the lexically-smallest id.

-- 1. Re-point note_tags rows at the surviving tag id.
WITH canonical AS (
  SELECT user_id, lower(name) AS norm, MIN(id) AS keep_id
    FROM tags
   GROUP BY user_id, lower(name)
), dupes AS (
  SELECT t.id AS drop_id, c.keep_id
    FROM tags t
    JOIN canonical c
      ON c.user_id = t.user_id AND c.norm = lower(t.name)
   WHERE t.id <> c.keep_id
)
INSERT INTO note_tags (note_id, tag_id)
SELECT nt.note_id, d.keep_id
  FROM note_tags nt
  JOIN dupes d ON d.drop_id = nt.tag_id
ON CONFLICT DO NOTHING;

-- 2. Delete the now-redundant tag rows (note_tags cascades).
WITH canonical AS (
  SELECT user_id, lower(name) AS norm, MIN(id) AS keep_id
    FROM tags
   GROUP BY user_id, lower(name)
)
DELETE FROM tags t
 USING canonical c
 WHERE c.user_id = t.user_id
   AND c.norm = lower(t.name)
   AND t.id <> c.keep_id;

-- 3. Swap the constraint.
ALTER TABLE tags DROP CONSTRAINT IF EXISTS tags_name_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_tags_user_name_ci
  ON tags (user_id, lower(name));
