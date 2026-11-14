import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

// env.ts validates configuration at import time and refuses to load without a
// DATABASE_URL. Nothing in this suite touches the database — it is about the
// file contract behind the media routes — so a placeholder keeps it
// self-contained, and NEX_MEDIA_DIR points the store at a directory this
// suite makes and removes. The assignment has to precede the dynamic import:
// env.ts freezes its parsed values at load, so a later process.env write
// would never reach `env.NEX_MEDIA_DIR`.
process.env.DATABASE_URL ??=
  "postgresql://user:pass@127.0.0.1:5432/nex-media-store-test";

const mediaDir = await mkdtemp(join(tmpdir(), "nex-media-store-"));
process.env.NEX_MEDIA_DIR = mediaDir;

const {
  isValidMediaHash,
  mediaFileExists,
  openMedia,
  removeMedia,
  storeMediaFile,
} = await import("./media-store.ts");

/**
 * The file half of the hash-addressed media store (see media-store.ts).
 *
 * What these cases pin is the contract every other part of sync leans on:
 * the hash is the address (mismatched bytes are refused, not stored under a
 * lie), writes are atomic (no `.part` file survives), re-stores are free,
 * and a hash that is not 64 hex characters can never become a path.
 */
describe("media store (files, no database)", () => {
  const user = "00000000-0000-4000-8000-0000000000aa";

  function sha256(bytes: Buffer): string {
    return createHash("sha256").update(bytes).digest("hex");
  }

  after(async () => {
    await rm(mediaDir, { recursive: true, force: true });
  });

  test("round-trips bytes by content hash", async () => {
    const bytes = Buffer.from("a photo, in principle");
    const hash = sha256(bytes);

    const stored = await storeMediaFile(user, hash, bytes);
    assert.equal(stored.deduped, false, "the first store writes");

    assert.equal(await mediaFileExists(user, hash), true);
    const object = await openMedia(user, hash);
    assert.ok(object, "the object just stored opens for reading");
    const chunks: Buffer[] = [];
    for await (const chunk of object!.stream) chunks.push(chunk as Buffer);
    assert.deepEqual(Buffer.concat(chunks), bytes);
    assert.equal(object!.size, bytes.length);
  });

  test("re-storing identical bytes dedupes", async () => {
    const bytes = Buffer.from("same bytes, second request");
    const hash = sha256(bytes);
    await storeMediaFile(user, hash, bytes);

    const again = await storeMediaFile(user, hash, bytes);
    assert.equal(again.deduped, true, "the second store is a no-op");
  });

  test("refuses bytes that do not match their address", async () => {
    const bytes = Buffer.from("honest bytes");
    const honestHash = sha256(bytes);
    const otherHash = sha256(Buffer.from("different bytes"));

    await assert.rejects(
      () => storeMediaFile(user, otherHash, bytes),
      /does not match its content hash/,
    );
    // And the lie left nothing behind under either name.
    assert.equal(await mediaFileExists(user, honestHash), false);
    assert.equal(await mediaFileExists(user, otherHash), false);
  });

  test("rejects an empty body and a hash that is not 64 hex", async () => {
    await assert.rejects(() => storeMediaFile(user, "not-a-hash", Buffer.from("x")));
    await assert.rejects(
      () => storeMediaFile(user, sha256(Buffer.from("y")), Buffer.alloc(0)),
      /empty/,
    );
    assert.equal(isValidMediaHash("not-a-hash"), false);
    assert.equal(
      isValidMediaHash(sha256(Buffer.from("z")).toUpperCase()),
      false,
      "uppercase is not the canonical address",
    );
  });

  test("no staging file survives a successful write", async () => {
    const bytes = Buffer.from("atomic, or it is nothing");
    await storeMediaFile(user, sha256(bytes), bytes);

    // The store layout is <mediaDir>/<user>/<first 2 hex>/<hash>; a leftover
    // `.part` would appear as an extra entry beside it.
    const shard = join(mediaDir, user, sha256(bytes).slice(0, 2));
    const entries = await readdir(shard);
    assert.deepEqual(entries, [sha256(bytes)]);
  });

  test("a hash with path characters never becomes a path", async () => {
    // mediaFileExists and openMedia answer null/false rather than throwing —
    // and crucially, they never resolve anything outside the media root.
    assert.equal(await mediaFileExists(user, "../../etc/passwd"), false);
    assert.equal(await openMedia(user, "..%2f..%2fetc%2fpasswd"), null);
  });

  test("removeMedia clears the object, and absent removals are fine", async () => {
    const bytes = Buffer.from("gone soon");
    const hash = sha256(bytes);
    await storeMediaFile(user, hash, bytes);

    await removeMedia(user, hash);
    assert.equal(await mediaFileExists(user, hash), false);
    await removeMedia(user, hash); // absent: not an error
  });

  test("objects are isolated per tenant", async () => {
    const bytes = Buffer.from("user A's bytes");
    const hash = sha256(bytes);
    await storeMediaFile(user, hash, bytes);

    const stranger = "00000000-0000-4000-8000-0000000000bb";
    assert.equal(await mediaFileExists(stranger, hash), false);
    assert.equal(await openMedia(stranger, hash), null);
    // The bytes on disk are user A's, read back through A's path only.
    const disk = await readFile(join(mediaDir, user, hash.slice(0, 2), hash));
    assert.deepEqual(disk, bytes);
  });
});
