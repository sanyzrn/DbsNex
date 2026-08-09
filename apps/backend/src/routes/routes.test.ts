import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";

// env.ts validates configuration at import time and refuses to load without a
// DATABASE_URL. These cases never reach the database — they stop at the auth
// boundary — so a placeholder is enough, and setting it here keeps the suite
// self-contained rather than depending on the CI job's environment. The import
// has to be dynamic: static imports are hoisted above this assignment.
process.env.DATABASE_URL ??= "postgresql://user:pass@127.0.0.1:5432/nex-routes-test";

const { app } = await import("../index.ts");

/**
 * Route-level tests.
 *
 * The suite used to be the merge algorithm plus a /health/live smoke boot, and
 * nothing exercised a route. That gap is not hypothetical: the sync path held a
 * query PostgreSQL rejects outright —
 *
 *     ERROR: FOR UPDATE is not allowed with GROUP BY clause
 *
 * — and nothing noticed, because the only suite that reached that code was the
 * integration matrix, which was itself failing at the auth boundary with 401.
 * A broken query sat behind a broken login and both looked like "sync is red".
 *
 * These cases deliberately stop at the boundary rather than touching the
 * database, so they run in the same `npm test` as everything else, with no
 * PostgreSQL and no fixtures. What they pin down is the shape of the boundary:
 * that protected routes reject before doing work, that unknown routes 404, and
 * that failures do not leak internals.
 */
describe("HTTP boundary", () => {
  let baseUrl: string;
  let server: ReturnType<typeof app.listen>;

  before(async () => {
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => resolve());
    });
    const { port } = server.address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((e) => (e ? reject(e) : resolve()));
    });
  });

  test("liveness answers without a database", async () => {
    const res = await fetch(`${baseUrl}/health/live`);
    assert.equal(res.status, 200);
    const body = (await res.json()) as Record<string, unknown>;
    assert.equal(body.status, "ok");
    assert.equal(body.phase, 2);
  });

  test("unknown routes are a clean 404, not an HTML error page", async () => {
    const res = await fetch(`${baseUrl}/does-not-exist`);
    assert.equal(res.status, 404);
    assert.deepEqual(await res.json(), { error: "NotFound" });
  });

  // The regression this file exists for: every protected route must reject an
  // anonymous caller, and it must do so before touching the database.
  for (const [method, path] of [
    ["POST", "/sync/push"],
    ["GET", "/sync/pull"],
    ["GET", "/notes"],
    ["GET", "/tags"],
  ] as const) {
    test(`${method} ${path} rejects a request with no token`, async () => {
      const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers: { "content-type": "application/json" },
        ...(method === "POST" ? { body: "{}" } : {}),
      });
      assert.equal(res.status, 401);
    });

    test(`${method} ${path} rejects a malformed Authorization header`, async () => {
      const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers: {
          "content-type": "application/json",
          authorization: "not-a-bearer-token",
        },
        ...(method === "POST" ? { body: "{}" } : {}),
      });
      assert.equal(res.status, 401);
    });
  }

  test("a rejected request leaks no internals", async () => {
    const res = await fetch(`${baseUrl}/sync/push`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    const text = await res.text();
    for (const leak of ["postgres", "pg_", "SELECT", "FOR UPDATE", "at Object.", "node_modules"]) {
      assert.ok(
        !text.toLowerCase().includes(leak.toLowerCase()),
        `error body leaked ${leak}: ${text}`,
      );
    }
  });

  test("malformed JSON is a 4xx, not a stack trace", async () => {
    const res = await fetch(`${baseUrl}/sync/push`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer nope",
      },
      body: "{ this is not json",
    });
    assert.ok(
      res.status >= 400 && res.status < 500,
      `expected a client error, got ${res.status}`,
    );
    const text = await res.text();
    assert.ok(!text.includes("SyntaxError:"), `leaked a parser stack: ${text}`);
  });

  // This process never sets TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID — the
  // deliberate case of a deployment that has not configured feedback yet.
  test("feedback answers 503 rather than silently discarding the message", async () => {
    const res = await fetch(`${baseUrl}/feedback`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message: "hello" }),
    });
    assert.equal(res.status, 503);
  });
});
