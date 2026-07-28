import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";

import { withTransaction } from "../db/index.ts";
import { auth } from "../middleware/auth.ts";

/**
 * Test-only routes, mounted only when NEX_TEST_MODE=1.
 *
 * This used to live inside syncRouter behind `if (!env.isTestMode) throw new
 * NotFound()`. A 404 guard is a runtime check on a route that is always
 * present; a route that is never mounted cannot be reached by a bug in the
 * guard, a misordered middleware, or anything else. Combined with the env
 * refinement that refuses to boot on `NODE_ENV=production` with
 * `NEX_TEST_MODE=1`, the endpoint is now unreachable in production by
 * construction rather than by vigilance.
 */
export const testRouter: Router = createRouter();

/** Wipes the authenticated tenant's corpus. Scoped to one user, never global. */
testRouter.post("/reset", async (req: Request, res: Response) => {
  const { userId } = auth(req);

  // One transaction. It used to be five sequential pool queries, each on an
  // arbitrary connection and each autocommitting, so a failure partway through
  // left the tenant half-wiped — and because this runs between matrix cases, a
  // partial failure produced a corrupt fixture and a cascade of unrelated
  // assertion failures rather than one clear error.
  await withTransaction(async (client) => {
    // note_tags cascades from notes (0001_init.sql), so it needs no statement
    // of its own.
    await client.query("DELETE FROM notes WHERE user_id = $1", [userId]);
    await client.query("DELETE FROM tags WHERE user_id = $1", [userId]);
    await client.query("DELETE FROM media_objects WHERE user_id = $1", [
      userId,
    ]);
    await client.query(
      "UPDATE device_acks SET last_pull_seq = 0 WHERE user_id = $1",
      [userId],
    );
  });

  res.json({ status: "ok" });
});
