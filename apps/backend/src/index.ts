import "express-async-errors";

import cors from "cors";
import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import rateLimit from "express-rate-limit";
import helmet from "helmet";

import { closePool, pingDatabase } from "./db/index.ts";
import { migrate } from "./db/migrate.ts";
import { env } from "./env.ts";
import { AppError } from "./http/errors.ts";
import { requestId } from "./http/request-id.ts";
import { requireDevice } from "./middleware/auth.ts";
import { authRouter } from "./routes/auth.ts";
import { notesRouter } from "./routes/notes.ts";
import { syncRouter } from "./routes/sync.ts";
import { tagsRouter } from "./routes/tags.ts";
import { startPurgeSchedule } from "./services/purge.ts";

/**
 * Nex backend — Phase 2 sync API.
 *
 * Field-aware conflict resolution (ADR-020): scalar LWW, tag union-merge,
 * tombstones, media_hash dedupe. See 04-architecture.md → Sync.
 */
const app = express();

app.disable("x-powered-by");
app.use(requestId);
app.use(helmet());
app.use(
  cors({
    // Empty allow-list means no browser origin is permitted, which is the
    // correct default for a native-client-only API.
    origin: env.allowedOrigins.length > 0 ? env.allowedOrigins : false,
    credentials: true,
  }),
);

/* ---------------------------------------------------------------- health */

// Liveness: is the process up? Must not depend on the database.
app.get("/health/live", (_req: Request, res: Response) => {
  res.json({ status: "ok", service: "nex-backend", phase: 2 });
});

// Readiness: can this instance actually serve? 503 when it cannot, so an
// orchestrator stops routing traffic to a non-functional replica.
app.get("/health/ready", async (_req: Request, res: Response) => {
  const database = await pingDatabase();
  res
    .status(database === "up" ? 200 : 503)
    .json({
      status: database === "up" ? "ok" : "degraded",
      service: "nex-backend",
      phase: 2,
      database,
    });
});

// Back-compat alias used by the CI sync-integration job.
app.get("/health", async (_req: Request, res: Response) => {
  const database = await pingDatabase();
  res
    .status(database === "up" ? 200 : 503)
    .json({
      status: database === "up" ? "ok" : "degraded",
      service: "nex-backend",
      phase: 2,
      database,
    });
});

/* ----------------------------------------------------------------- rates */

const authLimiter = rateLimit({
  windowMs: 60_000,
  limit: 10,
  standardHeaders: "draft-7",
  legacyHeaders: false,
});

const syncLimiter = rateLimit({
  windowMs: 60_000,
  limit: 60,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  keyGenerator: (req: Request) => req.auth?.deviceId ?? req.ip ?? "unknown",
});

const readLimiter = rateLimit({
  windowMs: 60_000,
  limit: 120,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  keyGenerator: (req: Request) => req.auth?.deviceId ?? req.ip ?? "unknown",
});

/* ---------------------------------------------------------------- routes */

// Body limits are per-route and sized to the payload each one accepts, rather
// than one unauthenticated 10 MB limit applied to everything.
app.use("/auth", authLimiter, express.json({ limit: "16kb" }), authRouter);

app.use(
  "/sync",
  express.json({ limit: "2mb" }),
  requireDevice,
  syncLimiter,
  syncRouter,
);

app.use(
  "/notes",
  express.json({ limit: "256kb" }),
  requireDevice,
  readLimiter,
  notesRouter,
);

app.use(
  "/tags",
  express.json({ limit: "64kb" }),
  requireDevice,
  readLimiter,
  tagsRouter,
);

/* -------------------------------------------------------------- fallback */

app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: "NotFound" });
});

// Terminal error middleware. Replaces the per-handler try/catch blocks that
// returned raw `e.message` — pg messages contain SQL fragments, constraint
// names and column names.
app.use((err: unknown, req: Request, res: Response, _next: NextFunction) => {
  const isApp = err instanceof AppError;
  const status = isApp ? err.status : 500;
  const code = isApp ? err.code : "InternalError";

  console.log(
    JSON.stringify({
      level: status >= 500 ? "error" : "warn",
      module: "backend.http",
      message: err instanceof Error ? err.message : String(err),
      context: {
        request_id: req.id,
        method: req.method,
        path: req.path,
        status,
        ...(isApp ? { detail: err.context } : {}),
      },
      stack: status >= 500 && err instanceof Error ? err.stack : undefined,
    }),
  );

  if (res.headersSent) return;

  res.status(status).json({
    error: code,
    request_id: req.id,
    ...(isApp && err.context ? { detail: err.context } : {}),
  });
});

/* ------------------------------------------------------------- bootstrap */

async function main(): Promise<void> {
  // Auto-migration is opt-in and intended for tests/local only. Production
  // runs `npm run migrate` as an explicit deploy step. A failure is fatal —
  // the API must never start against a half-applied schema.
  if (env.NEX_AUTO_MIGRATE === "1") {
    try {
      const applied = await migrate();
      console.log(
        JSON.stringify({
          level: "info",
          module: "backend.migrate",
          message: "schema ready",
          context: { applied },
        }),
      );
    } catch (e) {
      console.error(
        JSON.stringify({
          level: "fatal",
          module: "backend.migrate",
          message: "migration failed — refusing to start",
          context: { error: e instanceof Error ? e.message : String(e) },
        }),
      );
      process.exit(1);
    }
  }

  const stopPurge = startPurgeSchedule();

  const server = app.listen(env.PORT, () => {
    console.log(
      JSON.stringify({
        level: "info",
        module: "backend.bootstrap",
        message: "nex backend listening",
        context: { port: env.PORT, phase: 2, env: env.NODE_ENV },
      }),
    );
  });

  const shutdown = (signal: string) => {
    console.log(
      JSON.stringify({
        level: "info",
        module: "backend.shutdown",
        message: "shutting down",
        context: { signal },
      }),
    );
    stopPurge();
    server.close(() => {
      void closePool().finally(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

void main();

export { app };
