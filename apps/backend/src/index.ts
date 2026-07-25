import "dotenv/config";
import express from "express";

import { pingDatabase } from "./db/index.ts";
import { notesRouter } from "./routes/notes.ts";
import { syncRouter } from "./routes/sync.ts";
import { tagsRouter } from "./routes/tags.ts";

/**
 * Nex backend — Phase 0 skeleton.
 *
 * The backend exists from v1 as infrastructure only: the client never calls it
 * until v2 sync ships (04-architecture.md → Sequencing). Every product route
 * below is a deliberate stub.
 */
const app = express();

app.use(express.json({ limit: "1mb" }));

app.get("/health", async (_req, res) => {
  const database = await pingDatabase();
  res.json({ status: "ok", service: "nex-backend", phase: 0, database });
});

app.use("/notes", notesRouter);
app.use("/tags", tagsRouter);
app.use("/sync", syncRouter);

const port = Number(process.env.PORT ?? 4000);

app.listen(port, () => {
  // Structured logging (06-development.md → Logging). Never logs note content.
  console.log(
    JSON.stringify({
      level: "info",
      module: "backend.bootstrap",
      message: "nex backend listening",
      context: { port },
    }),
  );
});

export { app };
