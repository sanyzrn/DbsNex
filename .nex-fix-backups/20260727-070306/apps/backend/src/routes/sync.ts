import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";

import { migrate } from "../db/migrate.ts";
import { pullChanges, pushChanges } from "../services/sync-service.ts";

export const syncRouter: Router = createRouter();

syncRouter.post("/migrate", async (_req: Request, res: Response) => {
  try {
    await migrate();
    res.json({ status: "ok" });
  } catch (e) {
    res.status(500).json({
      error: "MigrateFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});

/** Push local outbox changes; server applies field-aware merge (ADR-020). */
syncRouter.post("/push", async (req: Request, res: Response) => {
  try {
    const deviceId = String(req.body?.device_id ?? "");
    if (!deviceId) {
      res.status(400).json({ error: "device_id required" });
      return;
    }
    const result = await pushChanges({
      device_id: deviceId,
      notes: Array.isArray(req.body?.notes) ? req.body.notes : [],
      tags: Array.isArray(req.body?.tags) ? req.body.tags : [],
    });
    res.json(result);
  } catch (e) {
    res.status(500).json({
      error: "PushFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});

/** Pull remote deltas since a watermark. */
syncRouter.get("/pull", async (req: Request, res: Response) => {
  try {
    const deviceId = String(req.query.device_id ?? "");
    if (!deviceId) {
      res.status(400).json({ error: "device_id required" });
      return;
    }
    const since = req.query.since ? String(req.query.since) : null;
    const result = await pullChanges({ device_id: deviceId, since });
    res.json(result);
  } catch (e) {
    res.status(500).json({
      error: "PullFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});

/** Test-only reset — enabled when NEX_TEST_MODE=1. */
syncRouter.post("/test/reset", async (_req: Request, res: Response) => {
  if (process.env.NEX_TEST_MODE !== "1") {
    res.status(404).json({ error: "NotFound" });
    return;
  }
  try {
    const { getPool } = await import("../db/index.ts");
    await getPool().query(`
TRUNCATE note_tags, notes, tags, media_objects, device_acks CASCADE;
`);
    res.json({ status: "ok" });
  } catch (e) {
    res.status(500).json({
      error: "ResetFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});
