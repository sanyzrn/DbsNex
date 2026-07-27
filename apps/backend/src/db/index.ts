import pg from "pg";

import { env } from "../env.ts";

/**
 * PostgreSQL pool for the Phase 2 sync API.
 *
 * `pg` is CommonJS; default-import then use `pg.Pool` so Node ESM can load it.
 * Named `import { Pool } from "pg"` fails at runtime with SyntaxError.
 *
 * The connection string comes from the validated, frozen env — never from
 * `process.env` directly — so an unset DATABASE_URL fails at boot rather than
 * silently falling back to libpq defaults.
 */
let pool: pg.Pool | undefined;

export function getPool(): pg.Pool {
  pool ??= new pg.Pool({
    connectionString: env.DATABASE_URL,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
  return pool;
}

export async function closePool(): Promise<void> {
  await pool?.end();
  pool = undefined;
}

/**
 * Runs `fn` inside a single transaction on one checked-out connection.
 *
 * Every multi-statement write must go through this. Using `pool.query()` in a
 * loop checks out an arbitrary connection per statement and autocommits each
 * one, which is how the push path used to destroy note_tags rows on partial
 * failure.
 */
export async function withTransaction<T>(
  fn: (client: pg.PoolClient) => Promise<T>,
  isolation: "READ COMMITTED" | "REPEATABLE READ" = "READ COMMITTED",
): Promise<T> {
  const client = await getPool().connect();
  try {
    await client.query(`BEGIN ISOLATION LEVEL ${isolation}`);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // The connection is already broken; releasing it is enough.
    }
    throw e;
  } finally {
    client.release();
  }
}

/** Returns `"up"` when PostgreSQL answers, `"down"` otherwise. */
export async function pingDatabase(): Promise<"up" | "down"> {
  try {
    await getPool().query("SELECT 1");
    return "up";
  } catch {
    return "down";
  }
}
