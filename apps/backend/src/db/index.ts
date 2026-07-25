import { Pool } from "pg";

/**
 * Phase 0: a lazily-created PostgreSQL pool and a liveness probe. No schema and
 * no migrations exist yet — the sync schema lands with Phase 2.
 */
let pool: Pool | undefined;

export function getPool(): Pool {
  pool ??= new Pool({ connectionString: process.env.DATABASE_URL });
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
