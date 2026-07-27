import "dotenv/config";
import express from "express";

import { pingDatabase } from "./db/index.ts";
import { migrate } from "./db/migrate.ts";
import { notesRouter } from "./routes/notes.ts";
import { syncRouter } from "./routes/sync.ts";
import { tagsRouter } from "./routes/tags.ts";

/**
 * Nex backend — Phase 2 sync API.
 *
 * Field-aware conflict resolution (ADR-020): scalar LWW, tag union-merge,
 * tombstones, media_hash dedupe. See 04-architecture.md → Sync.
 */
const app = express();

app.use(express.json({ limit: "10mb" }));

app.get("/health", async (_req, res) => {
  const database = await pingDatabase();
  res.json({ status: "ok", service: "nex-backend", phase: 2, database });
});

app.use("/notes", notesRouter);
app.use("/tags", tagsRouter);
app.use("/sync", syncRouter);

const port = Number(process.env.PORT ?? 4000);

async function main(): Promise<void> {
  if (process.env.NEX_AUTO_MIGRATE !== "0") {
    try {
      await migrate();
      console.log(
        JSON.stringify({
          level: "info",
          module: "backend.migrate",
          message: "schema ready",
        }),
      );
    } catch (e) {
      console.log(
        JSON.stringify({
          level: "warn",
          module: "backend.migrate",
          message: "migrate skipped or failed",
          context: { error: e instanceof Error ? e.message : String(e) },
        }),
      );
    }
  }

  app.listen(port, () => {
    console.log(
      JSON.stringify({
        level: "info",
        module: "backend.bootstrap",
        message: "nex backend listening",
        context: { port, phase: 2 },
      }),
    );
  });
}

void main();

export { app };
