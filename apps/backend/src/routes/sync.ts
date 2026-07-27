import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";
import { z } from "zod";

import { getPool } from "../db/index.ts";
import { env } from "../env.ts";
import { BadRequest, NotFound } from "../http/errors.ts";
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

const pullSchema = z.object({
  since: z
    .string()
    .regex(/^\d+$/, "since must be a non-negative integer cursor")
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
 * Test-only reset — enabled when NEX_TEST_MODE=1.
 *
 * Scoped to the authenticated user so it cannot wipe another tenant even in a
 * shared test environment. The unauthenticated POST /sync/migrate DDL trigger
 * that used to live here has been removed; migrations are an explicit deploy
 * step (`npm run migrate`).
 */
syncRouter.post("/test/reset", async (req: Request, res: Response) => {
  if (!env.isTestMode) throw new NotFound();

  const { userId } = auth(req);
  await getPool().query(
    `DELETE FROM note_tags
       WHERE note_id IN (SELECT id FROM notes WHERE user_id = $1)`,
    [userId],
  );
  await getPool().query("DELETE FROM notes WHERE user_id = $1", [userId]);
  await getPool().query("DELETE FROM tags WHERE user_id = $1", [userId]);
  await getPool().query("DELETE FROM media_objects WHERE user_id = $1", [userId]);
  await getPool().query(
    "UPDATE device_acks SET last_pull_seq = 0 WHERE user_id = $1",
    [userId],
  );

  res.json({ status: "ok" });
});
