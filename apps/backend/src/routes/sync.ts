import express, {
  type Request,
  type Response,
  type Router,
} from "express";
import { pipeline } from "node:stream/promises";
import { z } from "zod";

import { env } from "../env.ts";
import { BadRequest, NotFound } from "../http/errors.ts";
import { assertOwnDevice, auth } from "../middleware/auth.ts";
import {
  isValidMediaHash,
  openMedia,
  storeMedia,
} from "../services/media-store.ts";
import { pullChanges, pushChanges } from "../services/sync-service.ts";

const createRouter = express.Router;

export const syncRouter: Router = createRouter();

const isoString = z.string().refine((v) => !Number.isNaN(Date.parse(v)), {
  message: "must be a valid ISO-8601 instant",
});

// Per-item bounds are deliberately loose: the client imposes no length cap of
// its own on tag names or note bodies, and the push used to be one zod schema
// for the whole request, so a single honest-but-over-long item 400'd the
// entire batch and every later push the same way. The request-level array
// caps below (500, matching the client's chunking) are the real bound on
// payload shape; these exist only to keep one item from being a payload all
// by itself.
const incomingTag = z.object({
  id: z.string().min(1).max(256),
  name: z.string().min(1).max(512),
  color: z.string().max(64).nullish(),
  created_at: isoString,
});

/**
 * The note types this server accepts on the wire.
 *
 * Kept in step with `NoteType` in packages/core/lib/models/note.dart through
 * spec/note-types.json, which a test in each language compares its own enum
 * against. That guard exists because these two lists drifted once and the
 * result was not a rejected note but a dead device: the client shipped
 * `checklist` and `link`, this enum still named four types, and a push
 * carrying one got a 400 for the whole batch. `sync()` pushes before it
 * pulls, so the device stopped receiving as well as sending, on every retry,
 * for as long as the note existed — and deleting it did not help, because the
 * tombstone is pushed with the same type.
 *
 * Exported so the conformance test reads the enum the route actually uses
 * rather than a copy of it.
 */
export const NOTE_TYPES = [
  "text",
  "voice",
  "photo",
  "file",
  "checklist",
  "link",
] as const;

const incomingNote = z.object({
  id: z.string().min(1).max(256),
  type: z.enum(NOTE_TYPES),
  content: z.string().nullish(),
  media_uri: z.string().max(4096).nullish(),
  media_hash: z.string().max(256).nullish(),
  duration_ms: z.number().int().nonnegative().nullish(),
  created_at: isoString,
  updated_at: isoString,
  deleted_at: isoString.nullish(),
  device_id: z.string().min(1).max(256),
  rev: z.number().int().nonnegative(),
  tags: z.array(incomingTag).max(200).optional(),
});

const pushSchema = z.object({
  device_id: z.string().min(1).max(256),
  notes: z.array(incomingNote).max(500).default([]),
  tags: z.array(incomingTag).max(500).default([]),
});

/** The largest value a PostgreSQL bigint can hold. */
const MAX_CURSOR = 9223372036854775807n;

export const pullSchema = z.object({
  // Bounded, not just digit-shaped. The regex checked the character class and
  // not the magnitude, so a value above 2^63-1 passed validation, reached
  // PostgreSQL as a bigint comparison and raised `22003 numeric field
  // overflow` — reported to the client as a 500. A corrupt cursor is the
  // client's problem to fix, and a 400 tells it to reset; a 500 tells it to
  // retry forever, and puts a client-side typo on the server's error budget.
  since: z
    .string()
    .regex(/^\d{1,19}$/, "since must be a non-negative integer cursor")
    .refine((v) => BigInt(v) <= MAX_CURSOR, {
      message: "since exceeds the maximum cursor value",
    })
    .optional(),
});

/** Push local outbox changes; server applies field-aware merge (ADR-020). */
syncRouter.post("/push", async (req: Request, res: Response) => {
  const parsed = pushSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new BadRequest("invalid push payload", parsed.error.flatten().fieldErrors);
  }

  const { userId, deviceId } = auth(req);
  assertOwnDevice(req, parsed.data.device_id);

  const result = await pushChanges({
    user_id: userId,
    device_id: deviceId,
    notes: parsed.data.notes,
    tags: parsed.data.tags,
  });

  res.json(result);
});

/**
 * Pull remote deltas since an opaque integer cursor.
 *
 * The cursor is a sequence value produced by the database, not a timestamp
 * produced by the Node process, so clock skew can no longer drop rows.
 */
syncRouter.get("/pull", async (req: Request, res: Response) => {
  const parsed = pullSchema.safeParse(req.query);
  if (!parsed.success) {
    throw new BadRequest("invalid pull query", parsed.error.flatten().fieldErrors);
  }

  const { userId, deviceId } = auth(req);

  const result = await pullChanges({
    user_id: userId,
    device_id: deviceId,
    since: parsed.data.since ?? "0",
  });

  res.json(result);
});

/**
 * Store one media object, addressed by its own content hash.
 *
 * The body is raw `application/octet-stream`, so this route parses it itself —
 * the JSON parser mounted on `/sync` skips non-JSON content types — and the
 * size limit comes from the same config the hash store is sized against.
 * `storeMedia` re-hashes the bytes and refuses a body that does not match its
 * address, which is what makes the address trustworthy for every peer that
 * later fetches by it.
 */
syncRouter.put(
  "/media/:hash",
  express.raw({
    type: "application/octet-stream",
    limit: env.NEX_MEDIA_MAX_BYTES,
  }),
  async (req: Request, res: Response) => {
    const { userId } = auth(req);
    const hash = String(req.params.hash ?? "");
    if (!isValidMediaHash(hash)) {
      throw new BadRequest("media hash must be 64 lowercase hex characters");
    }
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      throw new BadRequest(
        "media body must be non-empty application/octet-stream",
      );
    }
    await storeMedia(userId, hash, req.body);
    res.status(204).end();
  },
);

/** Fetch one media object by content hash, or 404 when this account has none. */
syncRouter.get("/media/:hash", async (req: Request, res: Response) => {
  const { userId } = auth(req);
  const object = await openMedia(userId, String(req.params.hash ?? ""));
  if (!object) throw new NotFound("no such media object");

  res.status(200);
  res.setHeader("content-type", "application/octet-stream");
  res.setHeader("content-length", String(object.size));
  // A peer verifies the body against the hash it asked for, so correctness
  // does not depend on transport integrity — but a short read must not hang
  // the client's request either. Errors past the headers destroy the socket.
  await pipeline(object.stream, res).catch(() => res.destroy());
});
