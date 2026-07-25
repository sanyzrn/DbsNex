import { Router } from "express";

/** Phase 0 stub. Implemented when sync ships (Phase 2). */
export const notesRouter: Router = Router();

notesRouter.all("/{*splat}", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});

notesRouter.all("/", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});
