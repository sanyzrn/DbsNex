import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";

import { handleRequest, type Env } from "./index.ts";

const configuredEnv: Env = {
  TELEGRAM_BOT_TOKEN: "test-token",
  TELEGRAM_CHAT_ID: "12345",
};

function post(body: unknown, headers: Record<string, string> = {}): Request {
  const json = JSON.stringify(body);
  return new Request("https://example.invalid/feedback", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: json,
  });
}

describe("feedback worker", () => {
  const realFetch = globalThis.fetch;
  let telegramCalls: { url: string; body: unknown }[];
  let telegramResponse: () => Response;

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
    const res = await handleRequest(
      post({ message: "the timeline is great", appVersion: "0.3.0", platform: "android" }),
      configuredEnv,
    );

    assert.equal(res.status, 202);
    assert.equal(telegramCalls.length, 1);
    const call = telegramCalls[0]!;
    assert.match(
      call.url,
      /^https:\/\/api\.telegram\.org\/bottest-token\/sendMessage$/,
    );
    const body = call.body as { chat_id: string; text: string };
    assert.equal(body.chat_id, "12345");
    assert.match(body.text, /the timeline is great/);
    assert.match(body.text, /0\.3\.0/);
    assert.match(body.text, /android/);
  });

  test("unconfigured credentials answer 503 without ever touching Telegram", async () => {
    const res = await handleRequest(post({ message: "hello" }), {});

    assert.equal(res.status, 503);
    assert.equal(telegramCalls.length, 0);
  });

  test("an empty message is rejected before ever reaching Telegram", async () => {
    const res = await handleRequest(post({ message: "   " }), configuredEnv);

    assert.equal(res.status, 400);
    assert.equal(telegramCalls.length, 0);
  });

  test("a message past Telegram's own limit is rejected, not truncated", async () => {
    const res = await handleRequest(
      post({ message: "x".repeat(4001) }),
      configuredEnv,
    );

    assert.equal(res.status, 400);
    assert.equal(telegramCalls.length, 0);
  });

  test("Telegram refusing the message is a 502, with nothing leaked from its body", async () => {
    telegramResponse = () =>
      new Response(
        JSON.stringify({ ok: false, description: "chat not found" }),
        { status: 400 },
      );

    const res = await handleRequest(post({ message: "hello" }), configuredEnv);

    assert.equal(res.status, 502);
    const text = await res.text();
    assert.ok(!text.includes("chat not found"));
  });

  test("a non-object body is rejected", async () => {
    const res = await handleRequest(post("just a string"), configuredEnv);

    assert.equal(res.status, 400);
    assert.equal(telegramCalls.length, 0);
  });

  test("malformed JSON is a 400, not a crash", async () => {
    const request = new Request("https://example.invalid/feedback", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{not json",
    });

    const res = await handleRequest(request, configuredEnv);

    assert.equal(res.status, 400);
  });

  test("an oversized body is rejected by content-length before parsing", async () => {
    const res = await handleRequest(
      post({ message: "hello" }, { "content-length": String(9 * 1024) }),
      configuredEnv,
    );

    assert.equal(res.status, 413);
    assert.equal(telegramCalls.length, 0);
  });

  test("wrong method or path answers 404", async () => {
    const wrongMethod = await handleRequest(
      new Request("https://example.invalid/feedback", { method: "GET" }),
      configuredEnv,
    );
    assert.equal(wrongMethod.status, 404);

    const wrongPath = await handleRequest(
      new Request("https://example.invalid/other", { method: "POST" }),
      configuredEnv,
    );
    assert.equal(wrongPath.status, 404);
  });
});
