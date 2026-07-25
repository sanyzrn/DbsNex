/**
 * Field-aware note merge (ADR-020 / 04-architecture.md).
 * Port of packages/core FieldAwareMerger — kept in sync deliberately.
 */

export type NoteRow = {
  id: string;
  type: string;
  content: string | null;
  media_uri: string | null;
  media_hash: string | null;
  duration_ms: number | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  device_id: string;
  rev: number;
  tag_ids: string[];
};

export function mergeNotes(a: NoteRow, b: NoteRow): NoteRow {
  if (a.id !== b.id) throw new Error("mergeNotes: id mismatch");

  const aDeleted = a.deleted_at != null;
  const bDeleted = b.deleted_at != null;
  const tagUnion = Array.from(new Set([...a.tag_ids, ...b.tag_ids]));

  if (aDeleted || bDeleted) {
    const tombstone = aDeleted && bDeleted ? later(a, b) : aDeleted ? a : b;
    return {
      ...tombstone,
      created_at: earlier(a.created_at, b.created_at),
      updated_at: maxIso(a.updated_at, b.updated_at),
      rev: Math.max(a.rev, b.rev),
      tag_ids: tagUnion,
    };
  }

  const winner = later(a, b);
  const loser = winner === a ? b : a;
  // Same-device sequential edits: later tag set wins (allows removals).
  // Concurrent multi-device: ADR-020 union-merge.
  const resolvedTags =
    a.device_id === b.device_id ? [...winner.tag_ids] : tagUnion;
  return {
    id: a.id,
    type: winner.type,
    content: winner.content,
    media_uri: winner.media_uri,
    media_hash: winner.media_hash ?? loser.media_hash,
    duration_ms: winner.duration_ms ?? loser.duration_ms,
    created_at: earlier(a.created_at, b.created_at),
    updated_at: winner.updated_at,
    deleted_at: null,
    device_id: winner.device_id,
    rev: Math.max(a.rev, b.rev),
    tag_ids: resolvedTags,
  };
}

export function isDuplicateMedia(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  return !!a && !!b && a === b;
}

function later(a: NoteRow, b: NoteRow): NoteRow {
  const cmp = a.updated_at.localeCompare(b.updated_at);
  if (cmp > 0) return a;
  if (cmp < 0) return b;
  return a.rev >= b.rev ? a : b;
}

function earlier(a: string, b: string): string {
  return a.localeCompare(b) <= 0 ? a : b;
}

function maxIso(a: string, b: string): string {
  return a.localeCompare(b) >= 0 ? a : b;
}
