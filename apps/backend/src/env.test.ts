import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { describe, test } from "node:test";

/**
 * Configuration combinations that must not be allowed to boot.
 *
 * `env.ts` calls `process.exit(1)` on invalid configuration, which cannot be
 * asserted in-process — so each case starts a real child that imports the
 * module and reports what happened. That is also the honest test: what matters
 * is that the *process* refuses to start, not that a function returns an error.
 */
function boot(overrides: Record<string, string>): {
  ok: boolean;
  output: string;
} {
  const base = {
    ...process.env,
    DATABASE_URL: "postgresql://user:pass@127.0.0.1:5432/nex-env-test",
  };
  try {
    const output = execFileSync(
      process.execPath,
      [
        "--experimental-strip-types",
        "--no-warnings",
        "-e",
        'import("./src/env.ts").then(() => console.log("BOOTED"));',
      ],
      { env: { ...base, ...overrides }, encoding: "utf8", stdio: "pipe" },
    );
    return { ok: output.includes("BOOTED"), output };
  } catch (e) {
    const err = e as { stdout?: string; stderr?: string };
    return { ok: false, output: `${err.stdout ?? ""}${err.stderr ?? ""}` };
  }
}

describe("env", () => {
  test("test mode and production together refuse to start", () => {
    // NEX_TEST_MODE=1 exposes an endpoint that permanently deletes the
    // caller's entire library. Each variable used to be validated in isolation,
    // so nothing stopped the two from being set together — and this is a plain
    // string in a .env file, exactly the kind of value that gets copied from
    // staging into production.
    const result = boot({ NODE_ENV: "production", NEX_TEST_MODE: "1" });
    assert.equal(result.ok, false);
    assert.match(result.output, /NEX_TEST_MODE/);
  });

  test("test mode alone is fine outside production", () => {
    const result = boot({ NODE_ENV: "development", NEX_TEST_MODE: "1" });
    assert.equal(result.ok, true);
  });

  test("production alone is fine", () => {
    const result = boot({ NODE_ENV: "production", NEX_TEST_MODE: "0" });
    assert.equal(result.ok, true);
  });

  test("a cursor beyond bigint is refused by the schema", async () => {
    process.env.DATABASE_URL ??=
      "postgresql://user:pass@127.0.0.1:5432/nex-env-test";
    const { pullSchema } = await import("./routes/sync.ts");

    // The regex checked the character class and not the magnitude, so this
    // passed validation, reached PostgreSQL as a bigint comparison and raised
    // `22003 numeric field overflow` — which the generic error middleware
    // reported as a 500. A corrupt client cursor is not a server fault: a 400
    // tells the client to reset it, a 500 tells it to retry forever.
    assert.equal(pullSchema.safeParse({ since: "9".repeat(23) }).success, false);
    assert.equal(
      pullSchema.safeParse({ since: "9223372036854775808" }).success,
      false,
      "one past the bigint ceiling",
    );
    assert.equal(
      pullSchema.safeParse({ since: "9223372036854775807" }).success,
      true,
      "the ceiling itself is a legal cursor",
    );
    assert.equal(pullSchema.safeParse({ since: "42" }).success, true);
    assert.equal(pullSchema.safeParse({}).success, true);
  });
});
