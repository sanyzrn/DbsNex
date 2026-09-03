import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";

// Set before the app is imported, because `env.ts` freezes its configuration
// at import time and the limiter reads it when the module body runs. Its own
// file rather than a case inside routes.test.ts: `node --test` gives each file
// its own process, so three requests' worth of budget here cannot throttle the
// dozen requests that suite makes.
process.env.DATABASE_URL ??=
  "postgresql://user:pass@127.0.0.1:5432/nex-rate-limit-test";
process.env.PRE_AUTH_RATE_LIMIT = "3";

const { app } = await import("../index.ts");

/**
 * The limiter that has to run before the token lookup.
 *
 * `/sync`, `/notes` and `/tags` each carry a rate limiter keyed on the
 * authenticated device — which means it never saw a request whose token did
 * not resolve. An anonymous caller, or one holding a revoked token, was
 * answered 401 by a database round trip that nothing counted, as fast as it
 * could send them: the limiter was mounted behind the very check that
 * rejected them.
 *
 * These cases pin the ordering rather than the numbers. What matters is that
 * a request nobody has authenticated is counted at all.
 */
describe("pre-auth rate limiting", () => {
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

  test("an anonymous flood is throttled, not answered 401 forever", async () => {
    const statuses: number[] = [];
    // One past the budget. No Authorization header at all, so every one of
    // these stops at the auth boundary — the point is that the boundary is
    // no longer the *first* thing they reach.
    for (let i = 0; i < 4; i++) {
      const res = await fetch(`${baseUrl}/tags`);
      statuses.push(res.status);
    }

    assert.deepEqual(
      statuses.slice(0, 3),
      [401, 401, 401],
      "requests inside the budget still answer normally",
    );
    assert.equal(
      statuses[3],
      429,
      "the request past the budget must be refused before the token lookup",
    );
  });

  test("health checks are not behind it", async () => {
    // Liveness has to keep answering while a flood is in progress, or an
    // orchestrator restarts the instance that is successfully shedding load.
    const res = await fetch(`${baseUrl}/health/live`);
    assert.equal(res.status, 200);
  });
});
