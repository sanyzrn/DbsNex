import type { Pool } from "pg";

import { getPool } from "../db/index.ts";
import { isDuplicateMedia, mergeNotes, type NoteRow } from "./merge.ts";

export type IncomingNote = {
  id: string;
  type: string;
  content?: string | null;
  media_uri?: string | null;
  media_hash?: string | null;
  duration_ms?: number | null;
  created_at: string;
  updated_at: string;
  deleted_at?: string | null;
  device_id: string;
  rev: number;
  tags?: Array<{ id: string; name: string; color?: string | null; created_at: string }>;
};

export type IncomingTag = {
  id: string;
  name: string;
  color?: string | null;
  created_at: string;
};

async function loadNote(pool: Pool, id: string): Promise<NoteRow | null> {
  const noteRes = await pool.query(`SELECT * FROM notes WHERE id = $1`, [id]);
  if (noteRes.rowCount === 0) return null;
  const row = noteRes.rows[0];
  const tagsRes = await pool.query(
    `SELECT tag_id FROM note_tags WHERE note_id = $1`,
    [id],
  );
  return {
    id: row.id,
    type: row.type,
    content: row.content,
    media_uri: row.media_uri,
    media_hash: row.media_hash,
    duration_ms: row.duration_ms,
    created_at: new Date(row.created_at).toISOString(),
    updated_at: new Date(row.updated_at).toISOString(),
    deleted_at: row.deleted_at ? new Date(row.deleted_at).toISOString() : null,
    device_id: row.device_id,
    rev: row.rev,
    tag_ids: tagsRes.rows.map((r: { tag_id: string }) => r.tag_id),
  };
}

async function upsertTag(pool: Pool, tag: IncomingTag): Promise<void> {
  await pool.query(
    `
INSERT INTO tags (id, name, color, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  color = COALESCE(EXCLUDED.color, tags.color)
`,
    [tag.id, tag.name, tag.color ?? null, tag.created_at],
  );
}

async function writeNote(pool: Pool, note: NoteRow): Promise<void> {
  await pool.query(
    `
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'synced')
ON CONFLICT (id) DO UPDATE SET
  type = EXCLUDED.type,
  content = EXCLUDED.content,
  media_uri = EXCLUDED.media_uri,
  media_hash = EXCLUDED.media_hash,
  duration_ms = EXCLUDED.duration_ms,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at,
  deleted_at = EXCLUDED.deleted_at,
  device_id = EXCLUDED.device_id,
  rev = EXCLUDED.rev,
  sync_state = 'synced'
`,
    [
      note.id,
      note.type,
      note.content,
      note.media_uri,
      note.media_hash,
      note.duration_ms,
      note.created_at,
      note.updated_at,
      note.deleted_at,
      note.device_id,
      note.rev,
    ],
  );
  await pool.query(`DELETE FROM note_tags WHERE note_id = $1`, [note.id]);
  for (const tagId of note.tag_ids) {
    await pool.query(
      `INSERT INTO note_tags (note_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [note.id, tagId],
    );
  }
}

/** Register media by hash — identical content is not stored twice (ADR-019). */
export async function registerMedia(
  mediaHash: string,
  storageKey: string,
  pool: Pool = getPool(),
): Promise<{ deduped: boolean; storage_key: string }> {
  const existing = await pool.query(
    `SELECT storage_key FROM media_objects WHERE media_hash = $1`,
    [mediaHash],
  );
  if ((existing.rowCount ?? 0) > 0) {
    return { deduped: true, storage_key: existing.rows[0].storage_key as string };
  }
  await pool.query(
    `INSERT INTO media_objects (media_hash, storage_key) VALUES ($1, $2)`,
    [mediaHash, storageKey],
  );
  return { deduped: false, storage_key: storageKey };
}

export async function pushChanges(input: {
  device_id: string;
  notes: IncomingNote[];
  tags: IncomingTag[];
}): Promise<{ merged_ids: string[]; media_deduped: string[] }> {
  const pool = getPool();
  const mergedIds: string[] = [];
  const mediaDeduped: string[] = [];

  for (const tag of input.tags) {
    await upsertTag(pool, tag);
  }

  for (const incoming of input.notes) {
    for (const tag of incoming.tags ?? []) {
      await upsertTag(pool, tag);
    }

    if (incoming.media_hash) {
      const key = incoming.media_uri ?? `hash:${incoming.media_hash}`;
      const reg = await registerMedia(incoming.media_hash, key, pool);
      if (reg.deduped) mediaDeduped.push(incoming.media_hash);
    }

    const local: NoteRow = {
      id: incoming.id,
      type: incoming.type,
      content: incoming.content ?? null,
      media_uri: incoming.media_uri ?? null,
      media_hash: incoming.media_hash ?? null,
      duration_ms: incoming.duration_ms ?? null,
      created_at: incoming.created_at,
      updated_at: incoming.updated_at,
      deleted_at: incoming.deleted_at ?? null,
      device_id: incoming.device_id,
      rev: incoming.rev,
      tag_ids: (incoming.tags ?? []).map((t) => t.id),
    };

    const existing = await loadNote(pool, incoming.id);
    const merged = existing ? mergeNotes(existing, local) : local;

    // Prefer existing storage_key when hashes match (dedupe).
    if (
      existing &&
      isDuplicateMedia(existing.media_hash, local.media_hash) &&
      existing.media_uri
    ) {
      merged.media_uri = existing.media_uri;
    }

    await writeNote(pool, merged);
    if (existing) mergedIds.push(incoming.id);
  }

  return { merged_ids: mergedIds, media_deduped: mediaDeduped };
}

export async function pullChanges(input: {
  device_id: string;
  since?: string | null;
}): Promise<{ notes: NoteRow[]; tags: IncomingTag[]; server_time: string }> {
  const pool = getPool();
  const since = input.since ?? "1970-01-01T00:00:00.000Z";
  const notesRes = await pool.query(
    `
SELECT * FROM notes
WHERE updated_at > $1 OR (deleted_at IS NOT NULL AND deleted_at > $1)
ORDER BY updated_at ASC
`,
    [since],
  );

  const notes: NoteRow[] = [];
  for (const row of notesRes.rows) {
    const tagsRes = await pool.query(
      `SELECT tag_id FROM note_tags WHERE note_id = $1`,
      [row.id],
    );
    notes.push({
      id: row.id,
      type: row.type,
      content: row.content,
      media_uri: row.media_uri,
      media_hash: row.media_hash,
      duration_ms: row.duration_ms,
      created_at: new Date(row.created_at).toISOString(),
      updated_at: new Date(row.updated_at).toISOString(),
      deleted_at: row.deleted_at ? new Date(row.deleted_at).toISOString() : null,
      device_id: row.device_id,
      rev: row.rev,
      tag_ids: tagsRes.rows.map((r: { tag_id: string }) => r.tag_id),
    });
  }

  const tagsRes = await pool.query(`SELECT * FROM tags ORDER BY created_at ASC`);
  const tags: IncomingTag[] = tagsRes.rows.map(
    (r: {
      id: string;
      name: string;
      color: string | null;
      created_at: Date;
    }) => ({
      id: r.id,
      name: r.name,
      color: r.color,
      created_at: new Date(r.created_at).toISOString(),
    }),
  );

  const serverTime = new Date().toISOString();
  await pool.query(
    `
INSERT INTO device_acks (device_id, last_pull_at) VALUES ($1, $2)
ON CONFLICT (device_id) DO UPDATE SET last_pull_at = EXCLUDED.last_pull_at
`,
    [input.device_id, serverTime],
  );

  return { notes, tags, server_time: serverTime };
}
