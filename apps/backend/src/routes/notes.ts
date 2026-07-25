import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";

import { getPool } from "../db/index.ts";

export const notesRouter: Router = createRouter();

notesRouter.get("/", async (_req: Request, res: Response) => {
  try {
    const result = await getPool().query(
      `SELECT id, type, content, updated_at, deleted_at, rev FROM notes ORDER BY updated_at DESC LIMIT 100`,
    );
    res.json({ notes: result.rows });
  } catch (e) {
    res.status(500).json({
      error: "ListFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});

notesRouter.get("/:id", async (req: Request, res: Response) => {
  try {
    const result = await getPool().query(`SELECT * FROM notes WHERE id = $1`, [
      req.params.id,
    ]);
    if ((result.rowCount ?? 0) === 0) {
      res.status(404).json({ error: "NotFound" });
      return;
    }
    res.json(result.rows[0]);
  } catch (e) {
    res.status(500).json({
      error: "GetFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});
