import { Router } from "express";

/** Phase 0 stub. Implemented when sync ships (Phase 2). */
export const tagsRouter: Router = Router();

tagsRouter.all("/{*splat}", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});

tagsRouter.all("/", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});
