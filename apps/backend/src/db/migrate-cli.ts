import { closePool } from "./index.ts";
import { migrate } from "./migrate.ts";

/**
 * Explicit migration entry point: `npm run migrate`.
 *
 * Migration is a deploy step, not a boot side effect. This exits non-zero on
 * failure so a deployment pipeline halts instead of starting the API against a
 * half-applied schema.
 */
async function main(): Promise<void> {
  try {
    const applied = await migrate();
    console.log(
      JSON.stringify({
        level: "info",
        module: "backend.migrate-cli",
        message: "migrations complete",
        context: { applied, count: applied.length },
      }),
    );
    await closePool();
    process.exit(0);
  } catch (e) {
    console.error(
      JSON.stringify({
        level: "fatal",
        module: "backend.migrate-cli",
        message: "migrations failed",
        context: { error: e instanceof Error ? e.message : String(e) },
      }),
    );
    await closePool();
    process.exit(1);
  }
}

void main();
