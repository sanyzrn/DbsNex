import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";
import { z } from "zod";

import { BadRequest } from "../http/errors.ts";
import { assertOwnDevice, auth } from "../middleware/auth.ts";
import { pullChanges, pushChanges } from "../services/sync-service.ts";

export const syncRouter: Router = createRouter();

const isoString = z.string().refine((v) => !Number.isNaN(Date.parse(v)), {
  message: "must be a valid ISO-8601 instant",
});

const incomingTag = z.object({
  id: z.string().min(1).max(128),
  name: z.string().min(1).max(200),
  color: z.string().max(32).nullish(),
  created_at: isoString,
});

const incomingNote = z.object({
  id: z.string().min(1).max(128),
  type: z.enum(["text", "voice", "photo", "file"]),
  content: z.string().nullish(),
  media_uri: z.string().max(2048).nullish(),
  media_hash: z.string().max(128).nullish(),
  duration_ms: z.number().int().nonnegative().nullish(),
  created_at: isoString,
  updated_at: isoString,
  deleted_at: isoString.nullish(),
  device_id: z.string().min(1).max(128),
  rev: z.number().int().nonnegative(),
  tags: z.array(incomingTag).max(200).optional(),
});

const pushSchema = z.object({
  device_id: z.string().min(1).max(128),
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
