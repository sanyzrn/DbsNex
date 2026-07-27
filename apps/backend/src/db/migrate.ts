import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type pg from "pg";

import { getPool } from "./index.ts";

/**
 * File-based migration runner.
 *
 * Replaces the previous inline `CREATE TABLE IF NOT EXISTS` blob, which had no
 * version table, no ordering, no rollback, and stopped working the moment a
 * change was not purely additive.
 *
 * Guarantees:
 *  - migrations run in lexical filename order (0001_, 0002_, ...);
 *  - each file runs inside its own transaction — a failure rolls back cleanly;
 *  - a session-level advisory lock serialises concurrent replicas;
 *  - applied versions are recorded in schema_migrations.
 */
const MIGRATION_LOCK_ID = 8_274_113_905_461_223n;

const MIGRATIONS_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  "migrations",
);

async function ensureVersionTable(pool: pg.Pool): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}

async function pendingMigrations(pool: pg.Pool): Promise<string[]> {
  const applied = new Set(
    (await pool.query<{ version: string }>("SELECT version FROM schema_migrations"))
      .rows.map((r) => r.version),
  );
  const files = (await readdir(MIGRATIONS_DIR))
    .filter((f) => f.endsWith(".sql"))
    .sort();
  return files.filter((f) => !applied.has(f));
}

function log(level: "info" | "error", message: string, context?: unknown): void {
  console.log(
    JSON.stringify({ level, module: "backend.migrate", message, context }),
  );
}

/** Applies every pending migration. Idempotent and safe to call concurrently. */
export async function migrate(pool: pg.Pool = getPool()): Promise<string[]> {
  await ensureVersionTable(pool);

  const lock = await pool.connect();
  const applied: string[] = [];
  try {
    await lock.query("SELECT pg_advisory_lock($1)", [MIGRATION_LOCK_ID.toString()]);

    for (const file of await pendingMigrations(pool)) {
      const sql = await readFile(join(MIGRATIONS_DIR, file), "utf8");
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query(
          "INSERT INTO schema_migrations (version) VALUES ($1)",
          [file],
        );
        await client.query("COMMIT");
        applied.push(file);
        log("info", "migration applied", { version: file });
      } catch (e) {
        await client.query("ROLLBACK");
        log("error", "migration failed — rolled back", {
          version: file,
          error: e instanceof Error ? e.message : String(e),
        });
        throw e;
      } finally {
        client.release();
      }
    }
  } finally {
    await lock.query("SELECT pg_advisory_unlock($1)", [
      MIGRATION_LOCK_ID.toString(),
    ]);
    lock.release();
  }

  if (applied.length === 0) log("info", "schema already up to date");
  return applied;
}
