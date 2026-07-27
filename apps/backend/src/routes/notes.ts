import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";
import { z } from "zod";

import { getPool } from "../db/index.ts";
import { BadRequest, NotFound } from "../http/errors.ts";
import { auth } from "../middleware/auth.ts";

export const notesRouter: Router = createRouter();

/**
 * Explicit projection. Internal columns (sync_state, server_updated_at, seq,
 * merged_by_server, device_id, media_uri, user_id) are not part of any client
 * contract and must not leak.
 */
const PUBLIC_COLUMNS =
  "id, type, content, media_hash, duration_ms, created_at, updated_at, rev";

const listSchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

notesRouter.get("/", async (req: Request, res: Response) => {
  const parsed = listSchema.safeParse(req.query);
  if (!parsed.success) {
    throw new BadRequest("invalid query", parsed.error.flatten().fieldErrors);
  }

  const { userId } = auth(req);
  const result = await getPool().query(
    `SELECT ${PUBLIC_COLUMNS}
       FROM notes
      WHERE user_id = $1
        AND deleted_at IS NULL
      ORDER BY updated_at DESC
      LIMIT $2`,
    [userId, parsed.data.limit],
  );

  res.json({ notes: result.rows });
});

notesRouter.get("/:id", async (req: Request, res: Response) => {
  const { userId } = auth(req);
  const result = await getPool().query(
    `SELECT ${PUBLIC_COLUMNS}
       FROM notes
      WHERE id = $1
        AND user_id = $2
        AND deleted_at IS NULL`,
    [req.params.id, userId],
  );

  const note = result.rows[0];
  if (!note) throw new NotFound("note not found");

  res.json(note);
});
