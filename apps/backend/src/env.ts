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
  PAIRING_CODE_TTL_SECONDS: z.coerce.number().int().positive().default(600),
  TOMBSTONE_RETENTION_DAYS: z.coerce.number().int().positive().default(30),
  PURGE_INTERVAL_MINUTES: z.coerce.number().int().positive().default(60),
});

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
});

export type Env = typeof env;
