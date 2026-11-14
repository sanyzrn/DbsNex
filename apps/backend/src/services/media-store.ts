import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, rename, stat, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { Readable } from "node:stream";

import { getPool } from "../db/index.ts";
import { env } from "../env.ts";
import { BadRequest } from "../http/errors.ts";

/**
 * Media bytes behind the hashes that travel on the sync wire (ADR-019).
 *
 * A note's push carries only `media_hash` (and a portable file name); the
 * bytes themselves arrive here, addressed by their own content hash, and are
 * served back by the same address to a peer that has the hash but not the
 * file. One object per (user, hash): identical bytes are stored once, which
 * is the same dedupe `registerMedia` records for note pushes.
 *
 * The path is always *derived* from (userId, hash) and never read back from
 * the database: `media_objects.storage_key` historically holds whatever the
 * client pushed as `media_uri` — another device's absolute filesystem path —
 * and serving from that column would let a crafted push name any file on this
 * host. Deriving the path means a request can only ever reach a file this
 * service itself wrote.
 */

/** SHA-256 hex: 64 lowercase hex characters, nothing else. */
export function isValidMediaHash(hash: string): boolean {
  return /^[0-9a-f]{64}$/.test(hash);
}

function mediaPath(userId: string, hash: string): string {
  // Not from the client, but cheap to assert: a path component that is not a
  // plain id would mean the tenancy tables hold something they should not.
  if (!/^[0-9a-fA-F-]{1,64}$/.test(userId)) {
    throw new BadRequest("invalid media owner");
  }
  return join(env.NEX_MEDIA_DIR, userId, hash.slice(0, 2), hash);
}

/** Verifies the bytes against the hash they claim, then stores them once. */
export async function storeMedia(
  userId: string,
  hash: string,
  bytes: Buffer,
): Promise<{ deduped: boolean }> {
  const stored = await storeMediaFile(userId, hash, bytes);

  // The row is what `purgeTombstones` walks; without it the file would outlive
  // every note that referenced it. `ON CONFLICT DO NOTHING`: a legacy row may
  // already hold this (user, hash) with a client-supplied storage_key, and it
  // is the derived path that is authoritative now.
  await getPool().query(
    `INSERT INTO media_objects (user_id, media_hash, storage_key)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, media_hash) DO NOTHING`,
    [userId, hash, mediaPath(userId, hash)],
  );
  return stored;
}

/**
 * The filesystem half of [storeMedia] — verification and the atomic write,
 * without the database row. Split so the file contract (hash is the address,
 * writes are atomic, re-stores are free) can be tested against a real
 * directory with no PostgreSQL behind it.
 */
export async function storeMediaFile(
  userId: string,
  hash: string,
  bytes: Buffer,
): Promise<{ deduped: boolean }> {
  if (!isValidMediaHash(hash)) {
    throw new BadRequest("media hash must be 64 lowercase hex characters");
  }
  if (bytes.length === 0) {
    throw new BadRequest("media body is empty");
  }
  if (bytes.length > env.NEX_MEDIA_MAX_BYTES) {
    throw new BadRequest("media body exceeds the configured size limit");
  }
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== hash) {
    // The address is the content. Anything else under this name would poison
    // every note that references the hash, on every device, silently.
    throw new BadRequest("media body does not match its content hash");
  }

  const path = mediaPath(userId, hash);
  const existing = await stat(path).then(
    () => true,
    () => false,
  );
  if (existing) {
    // Bytes verified against the same hash: the object is already here.
    return { deduped: true };
  }

  // Write beside the target and rename into place, so a reader never sees a
  // half-written object and a crashed upload leaves no corrupt file behind.
  await mkdir(dirname(path), { recursive: true });
  const staging = `${path}.${process.pid}.${Date.now()}.part`;
  await writeFile(staging, bytes);
  try {
    await rename(staging, path);
  } catch (error) {
    await unlink(staging).catch(() => undefined);
    throw error;
  }
  return { deduped: false };
}

/** Opens a stored object for reading, or null when this account has none. */
export async function openMedia(
  userId: string,
  hash: string,
): Promise<{ stream: Readable; size: number } | null> {
  if (!isValidMediaHash(hash)) return null;
  const path = mediaPath(userId, hash);
  try {
    const info = await stat(path);
    if (!info.isFile()) return null;
    return { stream: createReadStream(path), size: info.size };
  } catch {
    return null;
  }
}

/**
 * Whether this account's bytes are present under this hash.
 *
 * The file system, not `media_objects`, is the truth: a restored device can
 * re-push a live note whose media row survived while its bytes were purged,
 * and only the push learning "I have the row but not the object" lets a
 * device that *does* hold the bytes put them back.
 */
export async function mediaFileExists(
  userId: string,
  hash: string,
): Promise<boolean> {
  if (!isValidMediaHash(hash)) return false;
  try {
    return (await stat(mediaPath(userId, hash))).isFile();
  } catch {
    return false;
  }
}

/** Removes one stored object; used by the purge when its last note dies. */
export async function removeMedia(userId: string, hash: string): Promise<void> {
  if (!isValidMediaHash(hash)) return;
  await unlink(mediaPath(userId, hash)).catch(() => undefined);
}
