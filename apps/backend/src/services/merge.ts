/**
 * Field-aware note merge (ADR-020 / 04-architecture.md).
 *
 * Behaviour is pinned by spec/merge-conformance.json, which both this file and
 * packages/core's FieldAwareMerger are tested against. Do not change semantics
 * here without adding a case to that corpus.
 */

import { BadRequest } from "../http/errors.ts";

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

/**
 * Parses an ISO-8601 instant to epoch milliseconds.
 *
 * Ordering used to be `String.localeCompare`, which is ICU-collation dependent
 * and only correct when both operands are identical fixed-width UTC strings.
 * The server side was normalised through `new Date().toISOString()` while the
 * client side was used verbatim, so "…00Z" beat "…00.000Z" — the less precise
 * timestamp won a tie it should have lost.
 */
export function ts(iso: string): number {
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) throw new BadRequest(`invalid timestamp: ${iso}`);
  return ms;
}

/** Normalises any valid ISO-8601 instant to fixed-width UTC. */
export function normaliseIso(iso: string): string {
  return new Date(ts(iso)).toISOString();
}

export function mergeNotes(a: NoteRow, b: NoteRow): NoteRow {
  if (a.id !== b.id) throw new BadRequest("mergeNotes: id mismatch");

  const aDeleted = a.deleted_at != null;
  const bDeleted = b.deleted_at != null;
  const tagUnion = Array.from(new Set([...a.tag_ids, ...b.tag_ids])).sort();

  if (aDeleted || bDeleted) {
    const tombstone = aDeleted && bDeleted ? later(a, b) : aDeleted ? a : b;
    // Deletion means deletion: the payload is erased at merge time rather than
    // retained forever behind a deleted_at flag.
    return {
      id: a.id,
      type: tombstone.type,
      content: null,
      media_uri: null,
      media_hash: null,
      duration_ms: null,
      created_at: earlier(a.created_at, b.created_at),
      updated_at: maxIso(a.updated_at, b.updated_at),
      deleted_at: tombstone.deleted_at,
      device_id: tombstone.device_id,
      rev: Math.max(a.rev, b.rev),
      tag_ids: [],
    };
  }

  const winner = later(a, b);
  const loser = winner === a ? b : a;
  // Same-device sequential edits: later tag set wins (allows removals).
  // Concurrent multi-device: ADR-020 union-merge.
  const resolvedTags =
    a.device_id === b.device_id ? [...winner.tag_ids].sort() : tagUnion;

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

/**
 * Invariant: later(a, b) and later(b, a) return the same row (commutativity).
 * Comparison is numeric on epoch milliseconds, then rev, then a plain byte
 * comparison of device_id — never locale-aware collation.
 */
function later(a: NoteRow, b: NoteRow): NoteRow {
  const delta = ts(a.updated_at) - ts(b.updated_at);
  if (delta !== 0) return delta > 0 ? a : b;
  if (a.rev !== b.rev) return a.rev > b.rev ? a : b;
  if (a.device_id > b.device_id) return a;
  if (a.device_id < b.device_id) return b;
  return a;
}

function earlier(a: string, b: string): string {
  return ts(a) <= ts(b) ? normaliseIso(a) : normaliseIso(b);
}

function maxIso(a: string, b: string): string {
  return ts(a) >= ts(b) ? normaliseIso(a) : normaliseIso(b);
}
