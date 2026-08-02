import "dotenv/config";
import { z } from "zod";

/**
 * Configuration is validated once, at boot, and frozen.
 *
 * Previously `process.env.DATABASE_URL` was read inline with no validation, so
 * an unset value made `pg` fall back to libpq defaults (local socket, $USER
 * database) instead of failing. A misconfigured deployment must not start.
 */
const schema = z.object({
  DATABASE_URL: z.string().url("DATABASE_URL must be a valid postgres:// URL"),
  PORT: z.coerce.number().int().positive().max(65535).default(4000),
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  ALLOWED_ORIGINS: z.string().default(""),
  NEX_TEST_MODE: z.enum(["0", "1"]).default("0"),
  NEX_AUTO_MIGRATE: z.enum(["0", "1"]).default("0"),
  SYNC_PAGE_SIZE: z.coerce.number().int().min(50).max(2000).default(500),
  // The three rate limits, tunable rather than baked in. They were literals in
  // index.ts, which meant an integration suite could not run more than sixty
  // requests without being throttled by the thing it was not testing.
  AUTH_RATE_LIMIT: z.coerce.number().int().positive().default(10),
  SYNC_RATE_LIMIT: z.coerce.number().int().positive().default(60),
  READ_RATE_LIMIT: z.coerce.number().int().positive().default(120),
  PAIRING_CODE_TTL_SECONDS: z.coerce.number().int().positive().default(600),
  TOMBSTONE_RETENTION_DAYS: z.coerce.number().int().positive().default(30),
  PURGE_INTERVAL_MINUTES: z.coerce.number().int().positive().default(60),
  // Number of trusted reverse-proxy hops in front of this process — never a
  // bare `true`, which tells Express to trust the left-most X-Forwarded-For
  // entry from *anyone*, meaning any client can hand-write the IP the rate
  // limiters key on and get its own private bucket. 0 (the default, no
  // deployment in front) makes Express use the socket's own address, which is
  // what it already did before this existed — so an unconfigured deployment
  // behaves exactly as before, and one that does sit behind a proxy opts in
  // to the exact hop count that proxy adds.
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),
  // Both unset by default: POST /feedback then answers 503 rather than
  // silently discarding what someone typed, or worse, pretending it sent.
  TELEGRAM_BOT_TOKEN: z.string().min(1).optional(),
  TELEGRAM_CHAT_ID: z.string().min(1).optional(),
})
  // Each variable used to be validated in isolation, so nothing stopped a
  // destructive test affordance and a production deployment from being
  // configured together — and NEX_TEST_MODE is a plain string in a .env file,
  // exactly the kind of value that gets copied between environments.
  .refine(
    (v) => !(v.NODE_ENV === "production" && v.NEX_TEST_MODE === "1"),
    {
      path: ["NEX_TEST_MODE"],
      message:
        "NEX_TEST_MODE=1 exposes POST /sync/test/reset, which permanently " +
        "deletes the caller's entire library. It must never be set in " +
        "production.",
    },
  );

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  console.error(
    JSON.stringify({
      level: "fatal",
      module: "backend.env",
      message: "invalid configuration — refusing to start",
      context: parsed.error.flatten().fieldErrors,
    }),
  );
  process.exit(1);
}

export const env = Object.freeze({
  ...parsed.data,
  isTestMode: parsed.data.NEX_TEST_MODE === "1",
  isProduction: parsed.data.NODE_ENV === "production",
  allowedOrigins: parsed.data.ALLOWED_ORIGINS.split(",")
    .map((o) => o.trim())
    .filter(Boolean),
  feedbackConfigured: Boolean(
    parsed.data.TELEGRAM_BOT_TOKEN && parsed.data.TELEGRAM_CHAT_ID,
  ),
});

export type Env = typeof env;
