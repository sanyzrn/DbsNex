import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";

// Ordinary npm test may skip this suite; the dedicated CI runner must prove it ran.
describe("HTTP authentication with PostgreSQL", { skip: process.env.NEX_PG_TESTS !== "1" }, () => {
  const users = [randomUUID(), randomUUID()];
  let base: string;
  let server: import("node:http").Server;
  let db: typeof import("../db/index.ts");
  let hashToken: typeof import("../middleware/auth.ts").hashToken;
  type Device = { device_id: string; token: string };

  before(async () => {
    db = await import("../db/index.ts");
    ({ hashToken } = await import("../middleware/auth.ts"));
    const { app } = await import("../index.ts");
    await db.getPool().query("INSERT INTO users (id) VALUES ($1), ($2)", users);
    server = app.listen(0);
    await new Promise<void>((resolve) => server.once("listening", resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  after(async () => {
    if (server) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    if (db) {
      await db.getPool().query("DELETE FROM users WHERE id = ANY($1::text[])", [users]);
      await db.closePool();
    }
  });
  function request(path: string, token?: string, body?: unknown) {
    return fetch(`${base}${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  }
  async function code(user = users[0], expires = "2099-01-01T00:00:00Z") {
    const secret = randomUUID();
    await db.getPool().query("INSERT INTO pairing_codes (code_hash, user_id, expires_at) VALUES ($1, $2, $3)", [hashToken(secret), user, expires]);
    return secret;
  }
  async function pair(user = users[0]): Promise<Device> {
    const response = await request("/auth/pair", undefined, { code: await code(user) });
    assert.equal(response.status, 201);
    return await response.json() as Device;
  }
  test("pairing stores a hashed expiring token and rejects reuse", async () => {
    const secret = await code();
    const response = await request("/auth/pair", undefined, { code: secret });
    assert.equal(response.status, 201);
    const device = await response.json() as Device;
    const row = (await db.getPool().query("SELECT token_hash, expires_at FROM devices WHERE device_id = $1", [device.device_id])).rows[0];
    assert.equal(row.token_hash, hashToken(device.token));
    assert.ok(row.expires_at > new Date());
    assert.equal((await request("/auth/pair", undefined, { code: secret })).status, 401);
    assert.equal((await request("/notes", device.token)).status, 200);
    const minted = await request("/auth/pairing-code", device.token, {});
    assert.equal(minted.status, 201);
    const child = await request("/auth/pair", undefined, await minted.json());
    assert.equal(child.status, 201);
    const childDevice = await child.json() as Device;
    assert.equal((await db.getPool().query("SELECT user_id FROM devices WHERE device_id = $1", [childDevice.device_id])).rows[0].user_id, users[0]);
  });
  test("expired code creates no device and remains unconsumed", async () => {
    const secret = await code(users[0], "2000-01-01T00:00:00Z");
    const count = (await db.getPool().query("SELECT count(*) FROM devices WHERE user_id = $1", [users[0]])).rows[0].count;
    assert.equal((await request("/auth/pair", undefined, { code: secret })).status, 401);
    assert.equal((await db.getPool().query("SELECT count(*) FROM devices WHERE user_id = $1", [users[0]])).rows[0].count, count);
    assert.equal((await db.getPool().query("SELECT consumed_at FROM pairing_codes WHERE code_hash = $1", [hashToken(secret)])).rows[0].consumed_at, null);
  });
  test("concurrent redemption admits exactly one device and acknowledgement", async () => {
    const secret = await code();
    const beforeCount = (await db.getPool().query("SELECT count(*) FROM devices WHERE user_id = $1", [users[0]])).rows[0].count;
    const results = await Promise.all(Array.from({ length: 4 }, () => request("/auth/pair", undefined, { code: secret })));
    assert.deepEqual(results.map(r => r.status).sort(), [201, 401, 401, 401]);
    const afterCount = (await db.getPool().query("SELECT count(*) FROM devices WHERE user_id = $1", [users[0]])).rows[0].count;
    assert.equal(Number(afterCount) - Number(beforeCount), 1);
    const device = await results.find(r => r.status === 201)!.json() as Device;
    const acks = await db.getPool().query("SELECT user_id FROM device_acks WHERE device_id = $1", [device.device_id]);
    assert.equal(acks.rowCount, 1);
    assert.equal(acks.rows[0].user_id, users[0]);
    assert.notEqual((await db.getPool().query("SELECT consumed_at FROM pairing_codes WHERE code_hash = $1", [hashToken(secret)])).rows[0].consumed_at, null);
  });
  test("expired, revoked and unknown tokens cannot read, push or mint codes", async () => {
    const expired = await pair();
    await db.getPool().query("UPDATE devices SET expires_at = '2000-01-01' WHERE device_id = $1", [expired.device_id]);
    const revoked = await pair();
    assert.equal((await request("/auth/revoke", revoked.token, {})).status, 200);
    for (const token of [expired.token, revoked.token, randomUUID()]) {
      for (const [path, body] of [["/notes", undefined], ["/tags", undefined], ["/sync/pull", undefined], ["/sync/push", { device_id: expired.device_id }], ["/auth/pairing-code", {}]] as const) {
        assert.equal((await request(path, token, body)).status, 401, path);
      }
    }
  });
  test("device spoofing is rejected and users are isolated over HTTP", async () => {
    const a = await pair();
    const sibling = await pair();
    const b = await pair(users[1]);
    const id = randomUUID();
    const note = { id, type: "text", content: "tenant A secret", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z", device_id: a.device_id, rev: 1 };
    for (const forged of [sibling.device_id, b.device_id]) {
      assert.equal((await request("/sync/push", a.token, { device_id: forged, notes: [note] })).status, 403);
    }
    assert.equal((await db.getPool().query("SELECT id FROM notes WHERE id = $1", [id])).rowCount, 0);
    assert.equal((await request("/sync/push", a.token, { device_id: a.device_id, user_id: users[1], notes: [note] })).status, 200);
    const own = await request("/sync/pull?since=0", sibling.token);
    assert.equal(own.status, 200);
    assert.ok(JSON.stringify(await own.json()).includes(id));
    for (const path of [`/notes/${id}`, "/notes", "/sync/pull?since=0"]) {
      const response = await request(path, b.token);
      assert.equal(response.status, path === `/notes/${id}` ? 404 : 200);
      assert.ok(!JSON.stringify(await response.json()).includes(id), path);
    }
  });
});
