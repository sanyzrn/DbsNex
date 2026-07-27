import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";

import { getPool } from "../db/index.ts";
import { auth } from "../middleware/auth.ts";

export const tagsRouter: Router = createRouter();

tagsRouter.get("/", async (req: Request, res: Response) => {
  const { userId } = auth(req);
  const result = await getPool().query(
    `SELECT id, name, color, created_at
       FROM tags
      WHERE user_id = $1
      ORDER BY name ASC`,
    [userId],
  );

  res.json({ tags: result.rows });
});
