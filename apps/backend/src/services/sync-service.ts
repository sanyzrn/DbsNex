import type { PoolClient } from "pg";

import { getPool, withTransaction } from "../db/index.ts";
import { env } from "../env.ts";
import { BadRequest } from "../http/errors.ts";
import {
  isDuplicateMedia,
  mergeNotes,
  normaliseIso,
  type NoteRow,
} from "./merge.ts";

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
  tags?: IncomingTag[];
};

export type IncomingTag = {
  id: string;
  name: string;
  color?: string | null;
  created_at: string;
};

export type OutgoingTag = IncomingTag & { seq: string };

export type TagRemap = { client_id: string; canonical_id: string };

export type PushResult = {
  merged: { id: string; rev: number }[];
  media_deduped: string[];
  tag_remap: TagRemap[];
  cursor: string;
};

export type PullResult = {
  notes: NoteRow[];
  tags: OutgoingTag[];
  cursor: string;
  has_more: boolean;
};

/* ------------------------------------------------------------------ tags */

/**
 * Upserts a tag on its natural key and returns the canonical id.
 *
 * The conflict target used to be (id) while the table had UNIQUE(name), so two
 * devices creating the same tag offline produced a 23505 that permanently broke
 * sync for that user. Identity is now (user_id, lower(name)); the caller
 * forwards the returned canonical id to the client as a remap.
 */
async function upsertTag(
  client: PoolClient,
  userId: string,
  tag: IncomingTag,
): Promise<string> {
  const { rows } = await client.query<{ id: string }>(
    `INSERT INTO tags (id, user_id, name, color, created_at, seq)
     VALUES ($1, $2, $3, $4, $5, nextval('tags_seq_seq'))
     ON CONFLICT (user_id, lower(name)) DO UPDATE
        SET color      = COALESCE(EXCLUDED.color, tags.color),
            created_at = LEAST(tags.created_at, EXCLUDED.created_at),
            seq        = nextval('tags_seq_seq')
     RETURNING id`,
    [tag.id, userId, tag.name, tag.color ?? null, normaliseIso(tag.created_at)],
  );

  const canonical = rows[0]?.id;
  if (!canonical) throw new BadRequest(`tag upsert failed for "${tag.name}"`);
  return canonical;
}

/* ----------------------------------------------------------------- notes */

async function loadNote(
  client: PoolClient,
  userId: string,
  id: string,
): Promise<NoteRow | null> {
  const { rows } = await client.query(
    `SELECT n.*, COALESCE(
              array_agg(nt.tag_id) FILTER (WHERE nt.tag_id IS NOT NULL),
              '{}'
            ) AS tag_ids
       FROM notes n
       LEFT JOIN note_tags nt ON nt.note_id = n.id
      WHERE n.id = $1 AND n.user_id = $2
      GROUP BY n.id
      FOR UPDATE OF n`,
    [id, userId],
  );

  const row = rows[0];
  return row ? rowToNote(row) : null;
}

function rowToNote(row: Record<string, unknown>): NoteRow {
  return {
    id: row.id as string,
    type: row.type as string,
    content: (row.content as string | null) ?? null,
    media_uri: (row.media_uri as string | null) ?? null,
    media_hash: (row.media_hash as string | null) ?? null,
    duration_ms: (row.duration_ms as number | null) ?? null,
    created_at: new Date(row.created_at as string).toISOString(),
    updated_at: new Date(row.updated_at as string).toISOString(),
    deleted_at: row.deleted_at
      ? new Date(row.deleted_at as string).toISOString()
      : null,
    device_id: row.device_id as string,
    rev: Number(row.rev),
    tag_ids: ((row.tag_ids as string[] | null) ?? []).slice().sort(),
  };
}

/**
 * Writes the merged note and reconciles its tag set.
 *
 * `rev` is server-authoritative: it is incremented here, never taken from the
 * client, and a stale write (client rev below stored rev) is rejected by the
 * WHERE clause. The tag reconciliation is a set difference rather than the old
 * DELETE-then-N-INSERTs, which had a destructive window on any partial failure.
 */
async function writeNote(
  client: PoolClient,
  userId: string,
  note: NoteRow,
  mergedByServer: boolean,
): Promise<{ rev: number; seq: string } | null> {
  const { rows } = await client.query<{ rev: number; seq: string }>(
    `INSERT INTO notes (
       id, user_id, type, content, media_uri, media_hash, duration_ms,
       created_at, updated_at, deleted_at, device_id, rev,
       sync_state, server_updated_at, seq, merged_by_server
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,
             'synced', NOW(), nextval('notes_seq_seq'), $13)
     ON CONFLICT (id) DO UPDATE
        SET type              = EXCLUDED.type,
            content           = EXCLUDED.content,
            media_uri         = EXCLUDED.media_uri,
            media_hash        = EXCLUDED.media_hash,
            duration_ms       = EXCLUDED.duration_ms,
            created_at        = EXCLUDED.created_at,
            updated_at        = EXCLUDED.updated_at,
            deleted_at        = EXCLUDED.deleted_at,
            device_id         = EXCLUDED.device_id,
            rev               = notes.rev + 1,
            sync_state        = 'synced',
            server_updated_at = NOW(),
            seq               = nextval('notes_seq_seq'),
            merged_by_server  = EXCLUDED.merged_by_server
      WHERE notes.user_id = EXCLUDED.user_id
        AND notes.rev <= EXCLUDED.rev
     RETURNING rev, seq`,
    [
      note.id,
      userId,
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
      mergedByServer,
    ],
  );

  const written = rows[0];
  if (!written) return null; // stale write rejected

  await client.query(
    `INSERT INTO note_tags (note_id, tag_id)
     SELECT $1, unnest($2::text[])
     ON CONFLICT DO NOTHING`,
    [note.id, note.tag_ids],
  );
  await client.query(
    `DELETE FROM note_tags
      WHERE note_id = $1 AND NOT (tag_id = ANY($2::text[]))`,
    [note.id, note.tag_ids],
  );

  return { rev: Number(written.rev), seq: String(written.seq) };
}

/* ----------------------------------------------------------------- media */

/** Register media by hash — identical content is not stored twice (ADR-019). */
export async function registerMedia(
  client: PoolClient,
  userId: string,
  mediaHash: string,
  storageKey: string,
): Promise<{ deduped: boolean; storage_key: string }> {
  const existing = await client.query<{ storage_key: string }>(
    `SELECT storage_key FROM media_objects
      WHERE user_id = $1 AND media_hash = $2`,
    [userId, mediaHash],
  );

  const hit = existing.rows[0];
  if (hit) return { deduped: true, storage_key: hit.storage_key };

  await client.query(
    `INSERT INTO media_objects (user_id, media_hash, storage_key)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, media_hash) DO NOTHING`,
    [userId, mediaHash, storageKey],
  );
  return { deduped: false, storage_key: storageKey };
}

/* ------------------------------------------------------------------ push */

export async function pushChanges(input: {
  user_id: string;
  device_id: string;
  notes: IncomingNote[];
  tags: IncomingTag[];
}): Promise<PushResult> {
  return withTransaction(async (client) => {
    const merged: { id: string; rev: number }[] = [];
    const mediaDeduped: string[] = [];
    const remap = new Map<string, string>();

    const resolveTag = async (tag: IncomingTag): Promise<string> => {
      const canonical = await upsertTag(client, input.user_id, tag);
      if (canonical !== tag.id) remap.set(tag.id, canonical);
      return canonical;
    };

    for (const tag of input.tags) await resolveTag(tag);

    let cursor = "0";

    for (const incoming of input.notes) {
      const tagIds: string[] = [];
      for (const tag of incoming.tags ?? []) tagIds.push(await resolveTag(tag));

      if (incoming.media_hash) {
        const key = incoming.media_uri ?? `hash:${incoming.media_hash}`;
        const reg = await registerMedia(
          client,
          input.user_id,
          incoming.media_hash,
          key,
        );
        if (reg.deduped) mediaDeduped.push(incoming.media_hash);
      }

      // Timestamps are normalised on ingress so merge comparisons are always
      // between identical fixed-width UTC representations.
      const local: NoteRow = {
        id: incoming.id,
        type: incoming.type,
        content: incoming.content ?? null,
        media_uri: incoming.media_uri ?? null,
        media_hash: incoming.media_hash ?? null,
        duration_ms: incoming.duration_ms ?? null,
        created_at: normaliseIso(incoming.created_at),
        updated_at: normaliseIso(incoming.updated_at),
        deleted_at: incoming.deleted_at
          ? normaliseIso(incoming.deleted_at)
          : null,
        device_id: incoming.device_id,
        rev: incoming.rev,
        tag_ids: Array.from(new Set(tagIds)).sort(),
      };

      // FOR UPDATE inside the transaction serialises concurrent pushes for the
      // same note id.
      const existing = await loadNote(client, input.user_id, incoming.id);
      const resolved = existing ? mergeNotes(existing, local) : local;

      if (
        existing &&
        isDuplicateMedia(existing.media_hash, resolved.media_hash) &&
        existing.media_uri
      ) {
        resolved.media_uri = existing.media_uri;
      }

      const mergedByServer =
        existing !== null &&
        JSON.stringify(resolved) !== JSON.stringify(local);

      const written = await writeNote(
        client,
        input.user_id,
        resolved,
        mergedByServer,
      );
      if (!written) continue; // stale write rejected — client must pull first

      merged.push({ id: incoming.id, rev: written.rev });
      if (BigInt(written.seq) > BigInt(cursor)) cursor = written.seq;
    }

    return {
      merged,
      media_deduped: mediaDeduped,
      tag_remap: Array.from(remap, ([client_id, canonical_id]) => ({
        client_id,
        canonical_id,
      })),
      cursor,
    };
  });
}

/* ------------------------------------------------------------------ pull */

export async function pullChanges(input: {
  user_id: string;
  device_id: string;
  since?: string | null;
}): Promise<PullResult> {
  const sinceSeq = input.since ?? "0";
  if (!/^\d+$/.test(sinceSeq)) {
    throw new BadRequest("since must be a non-negative integer cursor");
  }

  const limit = env.SYNC_PAGE_SIZE;

  // REPEATABLE READ so the notes page, the tags delta and the cursor all come
  // from one consistent snapshot.
  const page = await withTransaction(async (client) => {
    const notesRes = await client.query(
      `SELECT n.*, COALESCE(
                array_agg(nt.tag_id) FILTER (WHERE nt.tag_id IS NOT NULL),
                '{}'
              ) AS tag_ids
         FROM notes n
         LEFT JOIN note_tags nt ON nt.note_id = n.id
        WHERE n.user_id = $1
          AND n.seq > $2
          AND (n.device_id <> $3 OR n.merged_by_server)
        GROUP BY n.id
        ORDER BY n.seq ASC
        LIMIT $4`,
      [input.user_id, sinceSeq, input.device_id, limit],
    );

    const tagsRes = await client.query<{
      id: string;
      name: string;
      color: string | null;
      created_at: Date;
      seq: string;
    }>(
      `SELECT id, name, color, created_at, seq
         FROM tags
        WHERE user_id = $1 AND seq > $2
        ORDER BY seq ASC`,
      [input.user_id, sinceSeq],
    );

    const notes = notesRes.rows.map(rowToNote);

    // Cursor is derived from the data, never from a process clock.
    let cursor = sinceSeq;
    for (const row of notesRes.rows) {
      if (BigInt(row.seq as string) > BigInt(cursor)) cursor = String(row.seq);
    }
    for (const row of tagsRes.rows) {
      if (BigInt(row.seq) > BigInt(cursor)) cursor = String(row.seq);
    }

    return {
      notes,
      tags: tagsRes.rows.map((r) => ({
        id: r.id,
        name: r.name,
        color: r.color,
        created_at: new Date(r.created_at).toISOString(),
        seq: String(r.seq),
      })),
      cursor,
      has_more: notesRes.rowCount === limit,
    };
  }, "REPEATABLE READ");

  await getPool().query(
    `INSERT INTO device_acks (device_id, user_id, last_pull_at, last_pull_seq)
     VALUES ($1, $2, NOW(), $3)
     ON CONFLICT (device_id) DO UPDATE
        SET last_pull_at  = NOW(),
            last_pull_seq = GREATEST(device_acks.last_pull_seq, EXCLUDED.last_pull_seq)`,
    [input.device_id, input.user_id, page.cursor],
  );

  return page;
}
