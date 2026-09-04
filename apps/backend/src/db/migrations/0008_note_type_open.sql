-- 0008_note_type_open.sql — stop the notes table from having an opinion about
-- which note types exist.
--
-- 0001_init wrote `CHECK (type IN ('text', 'voice', 'photo', 'file'))` and
-- nothing revisited it. The client has since shipped two more types, and a
-- push carrying one of them was refused twice over: the route's zod enum
-- rejected it with a 400, and had it got past that, this constraint would have
-- raised 23514 and rolled the whole transaction back.
--
-- Either refusal is worse than it sounds. `SyncClient.sync()` pushes before it
-- pulls and throws on any non-2xx, so a single unsyncable note stopped that
-- device receiving everyone else's changes too, permanently, on every retry —
-- and deleting the note did not clear it, because the tombstone is pushed with
-- the same type.
--
-- The client made this same decision on its own table (see
-- `_dropLegacyTypeCheck` in packages/data/lib/schema/database.dart, which
-- rebuilds the table to remove the identical constraint) for the identical
-- reason: a storage-level allow-list means the day a type ships is the day
-- sync breaks for whoever uses it, and it breaks in the database, one layer
-- below where a useful error can be produced. Validation belongs in the wire
-- schema, which can answer 400 with a message, and it lives there now:
-- `NOTE_TYPES` in apps/backend/src/routes/sync.ts, pinned against
-- spec/note-types.json by a test in each language.
--
-- Written to find the constraint rather than name it. 0001_init declared it
-- inline, so PostgreSQL auto-named it — usually `notes_type_check`, but a
-- database that came from the pre-runner inline `migrate()` may carry another
-- name, and this has to be the same migration for both.

DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  FOR constraint_name IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'notes'::regclass
      AND contype = 'c'
      -- Identified by what it checks, not by what it is called. 'voice'
      -- appears in no other constraint on this table, and matching the column
      -- name alone would also catch a future NOT NULL-style check on `type`
      -- that someone added deliberately.
      AND pg_get_constraintdef(oid) ILIKE '%voice%'
  LOOP
    EXECUTE format('ALTER TABLE notes DROP CONSTRAINT %I', constraint_name);
  END LOOP;
END
$$;
