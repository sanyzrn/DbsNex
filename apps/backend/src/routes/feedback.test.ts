import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { after, afterEach, before, beforeEach, describe, test } from "node:test";

// Same reasoning as routes.test.ts: env.ts validates at import time, and the
// import has to be dynamic so this assignment runs first.
process.env.DATABASE_URL ??=
  "postgresql://user:pass@127.0.0.1:5432/nex-feedback-test";
process.env.TELEGRAM_BOT_TOKEN ??= "test-token";
process.env.TELEGRAM_CHAT_ID ??= "12345";

const { app } = await import("../index.ts");

/**
 * POST /feedback never touches the database — it stops at validation or at
 * the Telegram call — so, like routes.test.ts, this runs against a real
 * listening server with no PostgreSQL involved. `fetch` is stubbed only for
 * requests to api.telegram.org; the test's own calls into the app go through
 * the real network stack.
 */
describe("POST /feedback", () => {
  let baseUrl: string;
  let server: ReturnType<typeof app.listen>;
  const realFetch = globalThis.fetch;
  let telegramCalls: { url: string; body: unknown }[];
  let telegramResponse: () => Response;

  before(async () => {
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => resolve());
    });
    const { port } = server.address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    globalThis.fetch = realFetch;
    await new Promise<void>((resolve, reject) => {
      server.close((e) => (e ? reject(e) : resolve()));
    });
  });

  beforeEach(() => {
    telegramCalls = [];
    telegramResponse = () => new Response("{}", { status: 200 });
    globalThis.fetch = (async (
      input: Parameters<typeof fetch>[0],
      init?: RequestInit,
    ) => {
      const url = input.toString();
      if (url.startsWith("https://api.telegram.org/")) {
        telegramCalls.push({
          url,
          body: init?.body ? JSON.parse(init.body as string) : null,
        });
        return telegramResponse();
      }
      return realFetch(input, init);
    }) as typeof fetch;
  });

  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  test("a real message is forwarded to Telegram with the configured chat id", async () => {
    const res = await fetch(`${baseUrl}/feedback`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        message: "the timeline is great",
        appVersion: "0.3.0",
        platform: "android",
      }),
    });

    assert.equal(res.status, 202);
    assert.equal(telegramCalls.length, 1);
    const call = telegramCalls[0]!;
    assert.match(call.url, /^https:\/\/api\.telegram\.org\/bottest-token\/sendMessage$/);
    const body = call.body as { chat_id: string; text: string };
    assert.equal(body.chat_id, "12345");
    assert.match(body.text, /the timeline is great/);
    assert.match(body.text, /0\.3\.0/);
    assert.match(body.text, /android/);
  });

  test("an empty message is rejected before ever reaching Telegram", async () => {
    const res = await fetch(`${baseUrl}/feedback`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message: "   " }),
    });

    assert.equal(res.status, 400);
    assert.equal(telegramCalls.length, 0);
  });

  test("a message past Telegram's own limit is rejected, not truncated", async () => {
    const res = await fetch(`${baseUrl}/feedback`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message: "x".repeat(4001) }),
    });

    assert.equal(res.status, 400);
    assert.equal(telegramCalls.length, 0);
  });

  test("Telegram refusing the message is a 502, with nothing leaked from its body", async () => {
    telegramResponse = () =>
      new Response(
        JSON.stringify({ ok: false, description: "chat not found" }),
        { status: 400 },
      );

    const res = await fetch(`${baseUrl}/feedback`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message: "hello" }),
    });

    assert.equal(res.status, 502);
    const text = await res.text();
    assert.ok(!text.includes("chat not found"));
  });
});
