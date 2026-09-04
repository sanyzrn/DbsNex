import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";

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

describe("sync against a real database", { skip: enabled ? false : "set NEX_PG_TESTS=1 with a migrated PostgreSQL" }, () => {
  let pushChanges: typeof import("./sync-service.ts").pushChanges;
  let getPool: typeof import("../db/index.ts").getPool;
  let closePool: typeof import("../db/index.ts").closePool;

  before(async () => {
    ({ pushChanges } = await import("./sync-service.ts"));
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
    await getPool().query(`DELETE FROM tags WHERE user_id = ANY($1)`, [
      [USER_A, USER_B],
    ]);
  });

  after(async () => {
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
});
