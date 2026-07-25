import { Router } from "express";

/**
 * Phase 0 stub. The delta-sync contract (scalar last-writer-wins, tag
 * union-merge, tombstones, media dedupe by `media_hash`) is Phase 2 work —
 * see 04-architecture.md and ADR-020. Nothing is decided or implemented here.
 */
export const syncRouter: Router = Router();

syncRouter.all("/{*splat}", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});

syncRouter.all("/", (_req, res) => {
  res.status(501).json({ error: "NotImplemented", phase: 0 });
});
