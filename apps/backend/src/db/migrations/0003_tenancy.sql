-- 0003_tenancy.sql — introduce the account boundary.
--
-- Adds users and devices, then scopes every data table by user_id. Existing
-- rows are backfilled to a single well-known legacy user so this is safe on a
-- populated database.

CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,
  email      TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Well-known legacy owner for any data that predates tenancy.
INSERT INTO users (id, email)
VALUES ('00000000-0000-4000-8000-000000000000', NULL)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS devices (
  device_id    TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label        TEXT,
  -- SHA-256 of the bearer token. The plaintext token is shown exactly once,
  -- at pairing time, and is never stored.
  token_hash   TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ,
  revoked_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id);

CREATE TABLE IF NOT EXISTS pairing_codes (
  code_hash   TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pairing_codes_expiry ON pairing_codes (expires_at);

-- ---------------------------------------------------------------- notes
ALTER TABLE notes ADD COLUMN IF NOT EXISTS user_id TEXT;
UPDATE notes SET user_id = '00000000-0000-4000-8000-000000000000'
 WHERE user_id IS NULL;
ALTER TABLE notes ALTER COLUMN user_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notes_user_id_fkey'
  ) THEN
    ALTER TABLE notes
      ADD CONSTRAINT notes_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_notes_user ON notes (user_id);

-- ---------------------------------------------------------------- tags
ALTER TABLE tags ADD COLUMN IF NOT EXISTS user_id TEXT;
UPDATE tags SET user_id = '00000000-0000-4000-8000-000000000000'
 WHERE user_id IS NULL;
ALTER TABLE tags ALTER COLUMN user_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'tags_user_id_fkey'
  ) THEN
    ALTER TABLE tags
      ADD CONSTRAINT tags_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tags_user ON tags (user_id);

-- -------------------------------------------------------- media_objects
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS user_id TEXT;
UPDATE media_objects SET user_id = '00000000-0000-4000-8000-000000000000'
 WHERE user_id IS NULL;
ALTER TABLE media_objects ALTER COLUMN user_id SET NOT NULL;

-- Dedupe is per-user: two users must never share a storage key by hash.
ALTER TABLE media_objects DROP CONSTRAINT IF EXISTS media_objects_pkey;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'media_objects_user_hash_pkey'
  ) THEN
    ALTER TABLE media_objects
      ADD CONSTRAINT media_objects_user_hash_pkey
      PRIMARY KEY (user_id, media_hash);
  END IF;
END $$;

-- ---------------------------------------------------------- device_acks
ALTER TABLE device_acks ADD COLUMN IF NOT EXISTS user_id TEXT;
UPDATE device_acks SET user_id = '00000000-0000-4000-8000-000000000000'
 WHERE user_id IS NULL;
ALTER TABLE device_acks ALTER COLUMN user_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_device_acks_user ON device_acks (user_id);
