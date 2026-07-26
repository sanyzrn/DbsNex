/**
 * Unit tests for field-aware merge (kept in sync with
 * packages/core/test/field_aware_merger_test.dart).
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { mergeNotes, type NoteRow } from "./merge.ts";

function row(partial: Partial<NoteRow> & Pick<NoteRow, "id" | "content">): NoteRow {
  return {
    type: "text",
    media_uri: null,
    media_hash: null,
    duration_ms: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T12:00:00.000Z",
    deleted_at: null,
    device_id: "dev",
    rev: 1,
    tag_ids: [],
    ...partial,
  };
}

describe("mergeNotes", () => {
  it("updated_at+rev tie: merge is commutative (device_id tie-break)", () => {
    const stamp = "2026-01-01T12:00:00.000Z";
    const a = row({
      id: "n1",
      content: "from-alpha",
      updated_at: stamp,
      rev: 5,
      device_id: "device-alpha",
    });
    const b = row({
      id: "n1",
      content: "from-beta",
      updated_at: stamp,
      rev: 5,
      device_id: "device-beta",
    });
    const ab = mergeNotes(a, b);
    const ba = mergeNotes(b, a);
    assert.equal(ab.content, ba.content);
    assert.equal(ab.device_id, ba.device_id);
    // Lexical device_id: 'device-beta' > 'device-alpha'
    assert.equal(ab.content, "from-beta");
    assert.equal(ab.device_id, "device-beta");
  });
});
