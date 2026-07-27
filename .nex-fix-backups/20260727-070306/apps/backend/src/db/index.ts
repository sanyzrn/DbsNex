import pg from "pg";

/**
 * PostgreSQL pool for the Phase 2 sync API. Connection is opened lazily;
 * `/health` reports database liveness without failing the process.
 *
 * `pg` is CommonJS; default-import then use `pg.Pool` so
 * `node --experimental-strip-types` (ESM) can load it. Named
 * `import { Pool } from "pg"` fails at runtime with SyntaxError.
 */
let pool: pg.Pool | undefined;

export function getPool(): pg.Pool {
  pool ??= new pg.Pool({ connectionString: process.env.DATABASE_URL });
  return pool;
}

/** Returns `"up"` when a local PostgreSQL instance answers, `"down"` otherwise. */
export async function pingDatabase(): Promise<"up" | "down"> {
  try {
    await getPool().query("SELECT 1");
    return "up";
  } catch {
    // Reads fail open (06-development.md → Error Handling): the API stays up.
    return "down";
  }
}
