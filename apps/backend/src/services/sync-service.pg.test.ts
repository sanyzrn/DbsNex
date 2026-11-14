import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { after, before, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

/**
 * The cases that need a real PostgreSQL, because what they are about is a
 * constraint.
 *
 * Everything else in this suite deliberately stops at the auth boundary so it
 * can run with no database. That is the right trade for route shape, and it is
 * the wrong one for a unique index: a conflict that the `ON CONFLICT` clause
 * cannot arbitrate is invisible to every test that never reaches Postgres, and
 * this file exists because one of them shipped.
 *
 * Gated on NEX_PG_TESTS=1 rather than on "can I connect", and that difference
 * matters. A suite that skips itself when the database happens to be missing
 * reports success for work it did not do — the same vacuous green this repo
 * already carries elsewhere. Here the flag says somebody asked for these; if
 * they were asked for and the database is not there, that is a failure, not a
 * skip.
 */
const enabled = process.env.NEX_PG_TESTS === "1";

const USER_A = "00000000-0000-4000-8000-00000000000a";
const USER_B = "00000000-0000-4000-8000-00000000000b";

/**
 * The id every install mints for the "Work" starter tag.
 *
 * `stableUuidV5` in packages/core hashes the tag's name and nothing else —
 * no user, no device — so this exact value is seeded on every phone on
 * earth. Written down rather than computed so that a change to that function
 * has to come past this test.
 */
const WORK_TAG_ID = "38ef462b-9f60-528c-b01f-0433ac89a7af";

/** The list both languages check their note-type enum against. */
const SPEC_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "..",
  "spec",
  "note-types.json",
);

describe("sync against a real database", { skip: enabled ? false : "set NEX_PG_TESTS=1 with a migrated PostgreSQL" }, () => {
  let pushChanges: typeof import("./sync-service.ts").pushChanges;
  let pullChanges: typeof import("./sync-service.ts").pullChanges;
  let storeMedia: typeof import("./media-store.ts").storeMedia;
  let getPool: typeof import("../db/index.ts").getPool;
  let closePool: typeof import("../db/index.ts").closePool;

  before(async () => {
    ({ pushChanges, pullChanges } = await import("./sync-service.ts"));
    ({ storeMedia } = await import("./media-store.ts"));
    ({ getPool, closePool } = await import("../db/index.ts"));

    // Two tenants, which is the whole point: CI's sync matrix seeds one user
    // with two devices, and a same-user push resolves through the natural-key
    // arbiter and works. Nothing exercised two users until now.
    await getPool().query(
      `INSERT INTO users (id) VALUES ($1), ($2) ON CONFLICT DO NOTHING`,
      [USER_A, USER_B],
    );
    await getPool().query(
      `INSERT INTO devices (device_id, user_id, label, token_hash)
       VALUES ('pg-test-a', $1, 'pg-test-a', 'pg-test-hash-a'),
              ('pg-test-b', $2, 'pg-test-b', 'pg-test-hash-b')
       ON CONFLICT (device_id) DO NOTHING`,
      [USER_A, USER_B],
    );
    await getPool().query(`DELETE FROM notes WHERE user_id = ANY($1)`, [
      [USER_A, USER_B],
    ]);
    await getPool().query(`DELETE FROM tags WHERE user_id = ANY($1)`, [
      [USER_A, USER_B],
    ]);
  });

  after(async () => {
    await getPool().query(`DELETE FROM notes WHERE user_id = ANY($1)`, [
      [USER_A, USER_B],
    ]);
    await getPool().query(`DELETE FROM tags WHERE user_id = ANY($1)`, [
      [USER_A, USER_B],
    ]);
    await closePool();
  });

  test("a second tenant's starter tag does not wedge its sync forever", async () => {
    const tag = {
      id: WORK_TAG_ID,
      name: "Work",
      color: null,
      created_at: new Date().toISOString(),
    };

    const first = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      notes: [],
      tags: [tag],
    });
    assert.equal(first.tag_remap.length, 0, "the first tenant keeps its id");

    // Before this was fixed: `tags.id` is a *global* primary key (0001_init
    // created it that way and 0005 never re-keyed it, though 0003 did exactly
    // that for media_objects), and `ON CONFLICT (user_id, lower(name))` cannot
    // arbitrate `tags_pkey`. So this raised 23505, the whole transaction
    // rolled back — taking any notes pushed alongside it — the tag stayed
    // pending on the device, and every later sync failed identically. Sync was
    // permanently broken for every user of a shared backend except the first.
    const second = await pushChanges({
      user_id: USER_B,
      device_id: "pg-test-b",
      notes: [],
      tags: [tag],
    });

    assert.equal(second.tag_remap.length, 1, "the server minted its own id");
    assert.equal(second.tag_remap[0]!.client_id, WORK_TAG_ID);
    assert.notEqual(second.tag_remap[0]!.canonical_id, WORK_TAG_ID);

    // And it is repeatable — the failure this replaces was permanent, so
    // "it worked once" is not the property worth asserting.
    const third = await pushChanges({
      user_id: USER_B,
      device_id: "pg-test-b",
      notes: [],
      tags: [tag],
    });
    assert.equal(
      third.tag_remap[0]!.canonical_id,
      second.tag_remap[0]!.canonical_id,
      "the same tag resolves to the same row on every later push",
    );

    // Neither tenant's row moved under the other.
    const { rows } = await getPool().query<{ user_id: string; id: string }>(
      `SELECT user_id, id FROM tags WHERE user_id = ANY($1) ORDER BY user_id`,
      [[USER_A, USER_B]],
    );
    assert.equal(rows.length, 2, "one Work tag each, not one shared row");
    assert.equal(rows[0]!.id, WORK_TAG_ID, "the first tenant is untouched");
    assert.notEqual(rows[1]!.id, rows[0]!.id);
  });

  test("renaming a tag keeps its id instead of minting a second one", async () => {
    const id = "11111111-1111-4111-8111-111111111111";
    const created = new Date().toISOString();

    await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      notes: [],
      tags: [{ id, name: "Errands", color: null, created_at: created }],
    });

    // `renameTag` on the device changes the name and leaves `sync_state`
    // alone, so the rename never travels on its own — it arrives embedded in
    // the next note push, as this id carrying a different name. The server
    // used to find no natural-key conflict, hit `tags_pkey` on the id it
    // already had, and 500: the push rolled back with every note in it, and
    // every retry failed the same way. Sync was over for that device.
    //
    // Absorbing the collision by minting a fresh id would be no better in a
    // quieter way — the old row would keep the old name forever and the user
    // would end up with both.
    const renamed = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      notes: [],
      tags: [{ id, name: "Chores", color: null, created_at: created }],
    });

    assert.equal(renamed.tag_remap.length, 0, "a rename is not a remap");

    const { rows } = await getPool().query<{ id: string; name: string }>(
      `SELECT id, name FROM tags WHERE user_id = $1 AND id = $2`,
      [USER_A, id],
    );
    assert.equal(rows.length, 1, "one row, renamed — not two");
    assert.equal(rows[0]!.name, "Chores");
  });

  test("renaming onto a name already in use merges rather than fails", async () => {
    const keep = "22222222-2222-4222-8222-222222222222";
    const folded = "33333333-3333-4333-8333-333333333333";
    const created = new Date().toISOString();

    await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      notes: [],
      tags: [
        { id: keep, name: "Reading", color: null, created_at: created },
        { id: folded, name: "Books", color: null, created_at: created },
      ],
    });

    // "Books" renamed to "Reading", which this tenant already has. The
    // natural key is the identity, so the two tags have become one.
    const merged = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      notes: [],
      tags: [{ id: folded, name: "Reading", color: null, created_at: created }],
    });

    assert.equal(merged.tag_remap.length, 1);
    assert.equal(merged.tag_remap[0]!.client_id, folded);
    assert.equal(
      merged.tag_remap[0]!.canonical_id,
      keep,
      "the surviving row is the one that already held the name",
    );
  });

  test("every note type the client can capture reaches the table", async () => {
    // The other half of the checklist/link failure, and the half a schema test
    // cannot see. Widening the route's zod enum gets a push past validation and
    // straight into `CHECK (type IN ('text','voice','photo','file'))`, written
    // by 0001_init and never revisited — 23514, the whole transaction rolled
    // back, and the same permanent wedge one layer lower down. 0008 drops it;
    // this is what says so.
    //
    // Read from the spec rather than listed here, so a seventh type added to
    // spec/note-types.json is pushed against a real database by this test the
    // moment it exists, with no second edit to remember.
    const spec = JSON.parse(readFileSync(SPEC_PATH, "utf8")) as {
      types: string[];
    };
    const now = new Date().toISOString();

    const result = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: spec.types.map((type, i) => ({
        id: `44444444-4444-4444-8444-00000000000${i}`,
        type,
        content: `a ${type} note`,
        created_at: now,
        updated_at: now,
        device_id: "pg-test-a",
        rev: 1,
      })),
    });

    assert.equal(
      result.merged.length,
      spec.types.length,
      "every type the client can mint must be storable",
    );

    const { rows } = await getPool().query<{ type: string }>(
      `SELECT type FROM notes WHERE user_id = $1 ORDER BY type`,
      [USER_A],
    );
    assert.deepEqual(
      rows.map((r) => r.type).sort(),
      [...spec.types].sort(),
      "a type that validated but did not persist is the same outage",
    );
  });

  test("a behind-the-server revision is merged, not refused", async () => {
    // The rev guard this replaces (`notes.rev <= EXCLUDED.rev`) rejected any
    // push whose revision the stored row had passed. Combined with the pull
    // path's echo suppression, that was a permanent wedge: the note stayed
    // pending, was re-pushed and re-rejected on every cycle, and no pull
    // could heal it. Merging instead lets last-writer-wins decide — and an
    // ancient push loses that race to the stored row on every field.
    const id = "55555555-5555-4555-8555-555555555555";
    const now = new Date().toISOString();

    const first = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [
        {
          id,
          type: "text",
          content: "the newer version",
          created_at: now,
          updated_at: new Date(Date.now() + 10_000).toISOString(),
          device_id: "pg-test-a",
          rev: 3,
        },
      ],
    });
    assert.equal(first.merged.length, 1);

    // A stale revision with an older updated_at: LWW says it loses, and the
    // push is still acknowledged so the device can drain its outbox.
    const stale = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [
        {
          id,
          type: "text",
          content: "the older version",
          created_at: now,
          updated_at: now,
          device_id: "pg-test-a",
          rev: 1,
        },
      ],
    });

    assert.equal(
      stale.merged.length,
      1,
      "a stale push is acknowledged so the outbox can drain",
    );
    assert.ok(stale.merged[0]!.rev >= 3, "the stored revision is not regressed");

    const { rows } = await getPool().query<{ content: string }>(
      `SELECT content FROM notes WHERE id = $1`,
      [id],
    );
    assert.equal(rows[0]!.content, "the newer version");
    assert.equal(stale.rejected.length, 0, "nothing was dropped per-item");
  });

  test("a re-push of identical bytes neither writes nor re-broadcasts", async () => {
    // The lost-ack case: the first push committed but its response never
    // arrived, so the device re-sends the same version. Writing it again
    // would mint a fresh sequence and push the note to every peer for
    // nothing; the ack must instead report the stored revision unchanged.
    const id = "66666666-6666-4666-8666-666666666666";
    const now = new Date().toISOString();
    const note = {
      id,
      type: "text",
      content: "re-sent after a lost response",
      created_at: now,
      updated_at: now,
      device_id: "pg-test-a",
      rev: 1,
    };

    await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [note],
    });
    const { rows: afterFirst } = await getPool().query<{
      rev: string;
      seq: string;
    }>(`SELECT rev, seq FROM notes WHERE id = $1`, [id]);

    const again = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [note],
    });
    const { rows: afterAgain } = await getPool().query<{
      rev: string;
      seq: string;
    }>(`SELECT rev, seq FROM notes WHERE id = $1`, [id]);

    assert.equal(again.merged.length, 1, "the re-push is acknowledged");
    assert.equal(
      String(afterAgain[0]!.seq),
      String(afterFirst[0]!.seq),
      "no new sequence: the note is not re-broadcast to every peer",
    );
    assert.equal(Number(afterAgain[0]!.rev), Number(afterFirst[0]!.rev));
    assert.equal(again.merged[0]!.rev, Number(afterFirst[0]!.rev));
  });

  test("pull returns a device's own writes", async () => {
    // The echo filter this replaces (`device_id <> $3 OR merged_by_server`)
    // assumed the author of a row always holds what it says. A lost ack or a
    // restored backup under the same device id broke that assumption, and the
    // one device that needed the row could never see it again. Suppression
    // is the client's decision now — it has the local state to make it.
    const id = "77777777-7777-4777-8777-777777777777";
    const now = new Date().toISOString();

    await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [
        {
          id,
          type: "text",
          content: "mine, but I have not seen the ack",
          created_at: now,
          updated_at: now,
          device_id: "pg-test-a",
          rev: 1,
        },
      ],
    });

    const page = await pullChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      since: "0",
    });
    assert.ok(
      page.notes.some((n) => n.id === id),
      "the author's own row is visible to the author",
    );
  });

  test("a note id owned by another tenant is rejected, not merged", async () => {
    const id = "88888888-8888-4888-8888-888888888888";
    const now = new Date().toISOString();

    await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [
        {
          id,
          type: "text",
          content: "belongs to A",
          created_at: now,
          updated_at: now,
          device_id: "pg-test-a",
          rev: 1,
        },
      ],
    });

    const across = await pushChanges({
      user_id: USER_B,
      device_id: "pg-test-b",
      tags: [],
      notes: [
        {
          id,
          type: "text",
          content: "B attempting to write A's note id",
          created_at: now,
          updated_at: now,
          device_id: "pg-test-b",
          rev: 2,
        },
      ],
    });

    assert.equal(across.merged.length, 0, "the foreign id is not taken");
    assert.equal(across.rejected.length, 1);
    assert.equal(across.rejected[0]!.id, id);
    assert.equal(across.rejected[0]!.reason, "foreign_id");

    const { rows } = await getPool().query<{ content: string; user_id: string }>(
      `SELECT content, user_id FROM notes WHERE id = $1`,
      [id],
    );
    assert.equal(rows[0]!.content, "belongs to A");
    assert.equal(rows[0]!.user_id, USER_A);
  });

  test("a push names the media hashes it lacks the bytes for", async () => {
    // media_wanted is what recovers a lost object with the row still live:
    // the server has just looked at its own disk, which no client-side
    // "already sent" cache can speak to.
    const id = "99999999-9999-4999-8999-999999999999";
    const now = new Date().toISOString();
    const present = Buffer.from("bytes the server already has");
    const presentHash = createHash("sha256").update(present).digest("hex");
    const absentHash = createHash("sha256")
      .update(Buffer.from("bytes nobody uploaded"))
      .digest("hex");
    await storeMedia(USER_A, presentHash, present);

    const first = await pushChanges({
      user_id: USER_A,
      device_id: "pg-test-a",
      tags: [],
      notes: [
        {
          id,
          type: "photo",
          media_uri: "present.jpg",
          media_hash: presentHash,
          created_at: now,
          updated_at: now,
          device_id: "pg-test-a",
          rev: 1,
        },
        {
          id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          type: "photo",
          media_uri: "absent.jpg",
          media_hash: absentHash,
          created_at: now,
          updated_at: now,
          device_id: "pg-test-a",
          rev: 1,
        },
      ],
    });

    assert.deepEqual(
      first.media_wanted,
      [absentHash],
      "the stored hash is not wanted; the missing one is",
    );
  });
});
