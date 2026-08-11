-- 0007_device_token_expiry.sql — device bearer tokens gain an expiry.
--
-- pairing_codes always expired; the device token minted from redeeming one
-- never did. A token leaked once — a log line, a synced clipboard, a lost
-- phone's local storage — stayed valid forever, with revocation as the only
-- way to end it, and revocation requires knowing it needs ending.
--
-- Existing devices are left at NULL (never expires) rather than backfilled to
-- an already-elapsed timestamp that would silently log every paired device
-- out on deploy. Only devices paired after this migration get an expiry.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
