import { getPool } from "../db/index.ts";
import { env } from "../env.ts";

/**
 * Phase two of the two-phase delete.
 *
 * mergeNotes() erases a tombstone's payload immediately. This reclaims the row
 * itself — and any media no longer referenced by a live note — once every known
 * device has pulled past it and the retention window has elapsed.
 *
 * Without this, a user who deleted a sensitive note had it retained in full,
 * in plaintext, forever.
 */
export async function purgeTombstones(): Promise<{
  notes: number;
  media: number;
}> {
  const pool = getPool();

  const notesRes = await pool.query(
    `DELETE FROM notes n
      WHERE n.deleted_at IS NOT NULL
        AND n.deleted_at < NOW() - ($1 || ' days')::interval
        AND n.seq <= COALESCE(
              (SELECT MIN(last_pull_seq) FROM device_acks WHERE user_id = n.user_id),
              0
            )`,
    [env.TOMBSTONE_RETENTION_DAYS],
  );

  const mediaRes = await pool.query(
    `DELETE FROM media_objects m
      WHERE NOT EXISTS (
        SELECT 1 FROM notes n
         WHERE n.user_id = m.user_id
           AND n.media_hash = m.media_hash
           AND n.deleted_at IS NULL
      )`,
  );

  return { notes: notesRes.rowCount ?? 0, media: mediaRes.rowCount ?? 0 };
}

/** Starts the recurring purge. Returns a stop function. */
export function startPurgeSchedule(): () => void {
  const intervalMs = env.PURGE_INTERVAL_MINUTES * 60_000;

  const timer = setInterval(() => {
    void purgeTombstones()
      .then((result) => {
        if (result.notes > 0 || result.media > 0) {
          console.log(
            JSON.stringify({
              level: "info",
              module: "backend.purge",
              message: "tombstones reclaimed",
              context: result,
            }),
          );
        }
      })
      .catch((e: unknown) => {
        console.log(
          JSON.stringify({
            level: "warn",
            module: "backend.purge",
            message: "purge failed",
            context: { error: e instanceof Error ? e.message : String(e) },
          }),
        );
      });
  }, intervalMs);

  timer.unref();
  return () => clearInterval(timer);
}
