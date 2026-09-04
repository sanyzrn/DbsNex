import { randomUUID } from "node:crypto";
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

// The optional fields spell `| undefined` out explicitly because tsconfig sets
// `exactOptionalPropertyTypes`, under which `content?: string | null` forbids an
// explicit `undefined`. These objects are built by zod (`.nullish()` yields
// `T | null | undefined`), so the wider type is the one that actually crosses
// the route boundary. Both spellings reach pg as NULL.
export type IncomingNote = {
  id: string;
  type: string;
  content?: string | null | undefined;
  media_uri?: string | null | undefined;
  media_hash?: string | null | undefined;
  duration_ms?: number | null | undefined;
  created_at: string;
  updated_at: string;
  deleted_at?: string | null | undefined;
  device_id: string;
  rev: number;
  tags?: IncomingTag[] | undefined;
};

export type IncomingTag = {
  id: string;
  name: string;
  color?: string | null | undefined;
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

/** A unique-violation on a named constraint, whatever pg's error shape. */
function isUniqueViolationOn(error: unknown, constraint: string): boolean {
  if (typeof error !== "object" || error === null) return false;
  const e = error as { code?: unknown; constraint?: unknown };
  return e.code === "23505" && e.constraint === constraint;
}

/**
 * Upserts a tag on its natural key and returns the canonical id.
 *
 * The conflict target used to be (id) while the table had UNIQUE(name), so two
 * devices creating the same tag offline produced a 23505 that permanently broke
 * sync for that user. Identity is now (user_id, lower(name)); the caller
 * forwards the returned canonical id to the client as a remap.
 *
 * That fixed one tenant's two devices and left the same failure standing
 * between two tenants. `tags.id` is still a *global* primary key — migration
 * 0005 dropped `tags_name_key` and added `uq_tags_user_name_ci`, but never
 * re-keyed the table the way 0003 re-keyed `media_objects` to
 * `(user_id, media_hash)`. And the id a client sends is not random: starter
 * tags are seeded on every install with `stableUuidV5(name)`, which hashes
 * the name and nothing else, so every user on earth mints the same id for
 * "Work".
 *
 * So the second tenant to push a starter tag collided on `tags_pkey` — a
 * constraint this statement's `ON CONFLICT (user_id, lower(name))` cannot
 * arbitrate — the whole push transaction rolled back, the seeds stayed
 * pending, and every later sync failed the same way. Permanently, for
 * everyone but the first user of a shared backend.
 *
 * The client's id is therefore a suggestion, not an identity. When it is
 * already spoken for by somebody else, the server mints its own and hands it
 * back through the remap channel that already exists for exactly this.
 */
async function upsertTag(
  client: PoolClient,
  userId: string,
  tag: IncomingTag,
): Promise<string> {
  // A savepoint, because a failed statement poisons the whole transaction:
  // without one, absorbing a collision here would still lose the notes
  // pushed alongside it. The checks below make the ordinary cases explicit;
  // this is the backstop for two of this user's devices racing.
  await client.query("SAVEPOINT tag_upsert");
  try {
    return await insertTag(client, userId, tag, tag.id);
  } catch (error) {
    if (!isUniqueViolationOn(error, "tags_pkey")) throw error;
    await client.query("ROLLBACK TO SAVEPOINT tag_upsert");

    // The id is taken. By whom decides what this push meant.
    const { rows } = await client.query<{ user_id: string }>(
      "SELECT user_id FROM tags WHERE id = $1",
      [tag.id],
    );

    if (rows[0]?.user_id === userId) {
      // Ours already, under a name that no longer matches: the client
      // renamed it. `renameTag` on the device changes the name and leaves
      // `sync_state` alone, so a rename never travels on its own — it
      // arrives embedded in the next note push, as this tag's own id
      // carrying a new name. Answering that by minting a second id would
      // turn a rename into a duplicate: the old row would keep the old name
      // forever and every device would end up with both.
      return renameTag(client, userId, tag);
    }

    // Somebody else's id, which is what a deterministic starter-tag id makes
    // routine. Ours is a different tag that merely hashed the same.
    return insertTag(client, userId, tag, randomUUID());
  }
}

/**
 * Applies a rename to a tag this tenant already owns, keeping its id.
 *
 * The id is the one thing every device already agrees on, so a rename must
 * not change it. If the new name is one this tenant already uses, the two
 * tags have become one — the natural key is the identity, so the surviving
 * row's id is returned and the remap channel folds the client's onto it.
 */
async function renameTag(
  client: PoolClient,
  userId: string,
  tag: IncomingTag,
): Promise<string> {
  await client.query("SAVEPOINT tag_rename");
  try {
    const { rows } = await client.query<{ id: string }>(
      `UPDATE tags
          SET name = $3,
              color = COALESCE($4, color),
              seq = nextval('sync_seq')
        WHERE id = $1 AND user_id = $2
        RETURNING id`,
      [tag.id, userId, tag.name, tag.color ?? null],
    );
    const renamed = rows[0]?.id;
    if (!renamed) throw new BadRequest(`tag rename failed for "${tag.name}"`);
    return renamed;
  } catch (error) {
    if (!isUniqueViolationOn(error, "uq_tags_user_name_ci")) throw error;
    await client.query("ROLLBACK TO SAVEPOINT tag_rename");
    // Renamed onto a name this tenant already has: a merge, not a rename.
    const { rows } = await client.query<{ id: string }>(
      `SELECT id FROM tags WHERE user_id = $1 AND lower(name) = lower($2)`,
      [userId, tag.name],
    );
    const survivor = rows[0]?.id;
    if (!survivor) throw error;
    return survivor;
  }
}

async function insertTag(
  client: PoolClient,
  userId: string,
  tag: IncomingTag,
  id: string,
): Promise<string> {
  const { rows } = await client.query<{ id: string }>(
    // The sequence only moves when something material moved with it.
    //
    // It used to be `nextval` unconditionally, so an upsert that changed
    // nothing still put the row above every other device's cursor — and since
    // the client pushed its whole tag table on every sync, *every* tag was
    // re-broadcast to *every* device on *every* sync from anyone. Both halves
    // of that had to go; this is the server's.
    `INSERT INTO tags (id, user_id, name, color, created_at, seq)
     VALUES ($1, $2, $3, $4, $5, nextval('sync_seq'))
     ON CONFLICT (user_id, lower(name)) DO UPDATE
        SET color      = COALESCE(EXCLUDED.color, tags.color),
            created_at = LEAST(tags.created_at, EXCLUDED.created_at),
            seq        = CASE
                           WHEN tags.color IS DISTINCT FROM
                                COALESCE(EXCLUDED.color, tags.color)
                             OR tags.created_at IS DISTINCT FROM
                                LEAST(tags.created_at, EXCLUDED.created_at)
                           THEN nextval('sync_seq')
                           ELSE tags.seq
                         END
     RETURNING id`,
    [id, userId, tag.name, tag.color ?? null, normaliseIso(tag.created_at)],
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
    // PostgreSQL rejects FOR UPDATE alongside GROUP BY outright:
    //   ERROR: FOR UPDATE is not allowed with GROUP BY clause
    // so this statement could never have run. It went unnoticed because the
    // only caller is the sync path, and the sync suite never got past the auth
    // middleware to reach it.
    //
    // Collecting the tags in a scalar subquery keeps the aggregate one query
    // level down, where it does not conflict with the row lock, and locks
    // exactly the notes row the merge is about to rewrite.
    `SELECT n.*, COALESCE(
              (SELECT array_agg(nt.tag_id)
                 FROM note_tags nt
                WHERE nt.note_id = n.id),
              '{}'
            ) AS tag_ids
       FROM notes n
      WHERE n.id = $1 AND n.user_id = $2
      FOR UPDATE`,
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
             'synced', NOW(), nextval('sync_seq'), $13)
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
            seq               = nextval('sync_seq'),
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

/* ----------------------------------------------------------- comparison */

/**
 * The fields a merge can change. Compared explicitly, field by field.
 *
 * This used to be `JSON.stringify(resolved) !== JSON.stringify(local)`, which
 * worked only because `mergeNotes` and the `local` literal in `pushChanges`
 * happened to declare their twelve fields in the same order. Nothing enforced
 * that. Reordering a field in merge.ts — a formatting-level change no reviewer
 * would flag — would silently flip `merged_by_server` to true for every merge,
 * and that flag is what the pull query uses to decide whether to echo a row
 * back to its author. The failure mode is every device re-downloading its own
 * writes, forever, from a diff that looks like whitespace.
 */
const MERGE_FIELDS = [
  "type",
  "content",
  "media_uri",
  "media_hash",
  "duration_ms",
  "created_at",
  "updated_at",
  "deleted_at",
  "device_id",
] as const satisfies readonly (keyof NoteRow)[];

function differs(a: NoteRow, b: NoteRow): boolean {
  for (const field of MERGE_FIELDS) {
    if (a[field] !== b[field]) return true;
  }
  // tag_ids is the one array field; both sides are sorted by construction.
  if (a.tag_ids.length !== b.tag_ids.length) return true;
  return a.tag_ids.some((id, i) => id !== b.tag_ids[i]);
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

      const mergedByServer = existing !== null && differs(resolved, local);

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

    // Paged, like the notes query. It used to have no LIMIT at all, which is
    // what let the cursor outrun the notes page below.
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
        ORDER BY seq ASC
        LIMIT $3`,
      [input.user_id, sinceSeq, limit],
    );

    const notes = notesRes.rows.map(rowToNote);

    const notesTruncated = notesRes.rowCount === limit;
    const tagsTruncated = tagsRes.rowCount === limit;

    const lastSeq = (rows: { seq: unknown }[]): bigint | null =>
      rows.length ? BigInt(String(rows[rows.length - 1]!.seq)) : null;

    const noteFrontier = lastSeq(notesRes.rows);
    const tagFrontier = lastSeq(tagsRes.rows);

    // Cursor is derived from the data, never from a process clock — and never
    // from a stream that was cut short.
    //
    // It used to be the maximum sequence across both result sets while only
    // the notes query was bounded. One touched tag with a sequence above a
    // truncated notes page moved the watermark past notes that were never
    // sent, and the next pull asked for rows beyond them: permanent, silent
    // loss, unrecoverable without a manual cursor reset. A truncated stream
    // now caps the cursor; an exhausted one imposes no cap.
    const caps = [
      notesTruncated ? noteFrontier : null,
      tagsTruncated ? tagFrontier : null,
    ].filter((v): v is bigint => v !== null);

    const reached = [noteFrontier, tagFrontier].filter(
      (v): v is bigint => v !== null,
    );

    let cursor = BigInt(sinceSeq);
    if (reached.length) cursor = reached.reduce((a, b) => (a > b ? a : b));
    if (caps.length) {
      cursor = caps.reduce((a, b) => (a < b ? a : b), cursor);
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
      cursor: cursor.toString(),
      has_more: notesTruncated || tagsTruncated,
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
