import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

// Set before the route module is imported. `sync.ts` reaches the db module
// through the sync service, and `env.ts` validates its configuration when its
// body runs — so a static import of the enum would fail this file on a machine
// with no DATABASE_URL, which is every machine that runs the unit suite.
// Same reason and same shape as rate-limit.test.ts. No connection is opened.
process.env.DATABASE_URL ??=
  "postgresql://user:pass@127.0.0.1:5432/nex-note-types-test";

const { NOTE_TYPES } = await import("./sync.ts");

/**
 * Cross-language conformance, the same shape as merge.conformance.test.ts.
 *
 * This file and packages/core/test/note_type_conformance_test.dart read the
 * identical list at spec/note-types.json. If the server's wire enum and the
 * client's `NoteType` ever disagree about which types exist, one of the two
 * suites fails.
 *
 * It exists because they did disagree, and nothing noticed. The client shipped
 * `checklist` and `link`; this route still listed four types. A device that
 * captured a checklist got a 400 on the whole push — and `sync()` pushes
 * before it pulls and throws on any non-2xx, so that device stopped receiving
 * other devices' changes too, permanently, on every retry. Deleting the note
 * did not clear it: `listPending(includeDeleted: true)` re-sends the tombstone
 * with the same type. Only a hard purge unblocked it, at the cost of the note.
 *
 * No test could have caught that. The backend suite pushes only types the
 * enum already allowed, and the one end-to-end suite that drives a real client
 * uses text notes. A list both sides check themselves against is the cheapest
 * thing that would have.
 */
const SPEC_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "..",
  "spec",
  "note-types.json",
);

test("the wire enum matches spec/note-types.json exactly", () => {
  const spec = JSON.parse(readFileSync(SPEC_PATH, "utf8")) as {
    types: string[];
  };

  // Order included, not just membership. The two enums are read side by side
  // whenever someone adds a type, and a list that agrees on contents while
  // disagreeing on order makes that comparison harder than it needs to be.
  assert.deepEqual(
    [...NOTE_TYPES],
    spec.types,
    "apps/backend/src/routes/sync.ts and spec/note-types.json disagree — a " +
      "type in one and not the other is a device that cannot sync",
  );
});

test("the types the client actually mints are all accepted", () => {
  // Named individually rather than derived, so that deleting one from the
  // spec cannot quietly delete it from this assertion too. These six are what
  // packages/core/lib/capture/capture_service.dart can produce.
  for (const type of [
    "text",
    "voice",
    "photo",
    "file",
    "checklist",
    "link",
  ]) {
    assert.ok(
      (NOTE_TYPES as readonly string[]).includes(type),
      `the server rejects "${type}", which a capture can create`,
    );
  }
});
