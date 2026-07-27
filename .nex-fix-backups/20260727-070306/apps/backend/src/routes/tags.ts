import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";

import { getPool } from "../db/index.ts";

export const tagsRouter: Router = createRouter();

tagsRouter.get("/", async (_req: Request, res: Response) => {
  try {
    const result = await getPool().query(
      `SELECT * FROM tags ORDER BY name ASC`,
    );
    res.json({ tags: result.rows });
  } catch (e) {
    res.status(500).json({
      error: "ListFailed",
      message: e instanceof Error ? e.message : String(e),
    });
  }
});
