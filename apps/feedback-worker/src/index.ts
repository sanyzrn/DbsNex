/**
 * Standalone Cloudflare Worker: forwards app feedback to a Telegram chat.
 *
 * Deliberately independent of apps/backend — no Postgres, no Express, no
 * shared rate limiter or purge schedule. A single stateless endpoint is
 * exactly what Workers are for; the existing backend (direct-TCP Postgres,
 * a background purge timer) is not, and porting it here was never the goal.
 *
 * `handleRequest` takes a plain `Request` and returns a plain `Response`, so
 * it is testable with Node's own fetch/Request/Response globals — no need to
 * stand up a Workers runtime just to test the logic (see index.test.ts).
 */

export interface Env {
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_CHAT_ID?: string;
  FEEDBACK_LIMITER?: { limit(options: { key: string }): Promise<{ success: boolean }> };
}

// Telegram's own ceiling for a sendMessage text — reject past this rather
// than let Telegram truncate it silently on the other end.
const MAX_MESSAGE = 4000;
const MAX_CONTEXT_FIELD = 40;

// A generous cap on the request body itself, checked before it's ever
// parsed — mirrors apps/backend's `express.json({ limit: "8kb" })`. Workers
// have their own platform-level request size ceiling too; this just fails
// fast and cheaply for the common case of an oversized payload.
//
// 32 KB since the optional diagnostics report (below): its 20,000 characters
// are mostly ASCII, with room for Persian in the message itself.
const MAX_BODY_BYTES = 32 * 1024;

// The diagnostics report the person chose to attach, sent to the chat as a
// text file rather than inside the message, whose 4,000 characters it would
// not fit. The app sends its newest entries, redacted, up to 16 KB.
const MAX_DIAGNOSTICS = 20_000;

// What the person says it is. Anything else is refused rather than guessed,
// so the chat only ever shows a label the app actually offered.
const KINDS = { bug: "🐞 Bug", idea: "💡 Idea", other: "💬 Feedback" } as const;
type FeedbackKind = keyof typeof KINDS;
const MAX_CONTACT = 80;

interface FeedbackPayload {
  message: string;
  appVersion?: string;
  platform?: string;
  // The phone's maker and model, e.g. "Samsung SM-S918B".
  device?: string;
  kind?: FeedbackKind;
  contact?: string;
  diagnostics?: string;
}

function parsePayload(body: unknown): FeedbackPayload | null {
  if (typeof body !== "object" || body === null) return null;
  const { message, appVersion, platform, device, kind, contact, diagnostics } = body as Record<
    string,
    unknown
  >;

  if (typeof message !== "string") return null;
  const trimmed = message.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_MESSAGE) return null;

  if (
    appVersion !== undefined &&
    (typeof appVersion !== "string" || appVersion.length > MAX_CONTEXT_FIELD)
  ) {
    return null;
  }
  if (
    platform !== undefined &&
    (typeof platform !== "string" || platform.length > MAX_CONTEXT_FIELD / 2)
  ) {
    return null;
  }

  if (
    device !== undefined &&
    (typeof device !== "string" || device.length > MAX_CONTEXT_FIELD)
  ) {
    return null;
  }

  if (kind !== undefined && (typeof kind !== "string" || !(kind in KINDS))) {
    return null;
  }
  let reply: string | undefined;
  if (contact !== undefined) {
    if (typeof contact !== "string") return null;
    reply = contact.trim();
    if (reply.length > MAX_CONTACT) return null;
    if (reply.length === 0) reply = undefined;
  }

  let report: string | undefined;
  if (diagnostics !== undefined) {
    if (typeof diagnostics !== "string") return null;
    report = diagnostics.trim();
    if (report.length > MAX_DIAGNOSTICS) return null;
    if (report.length === 0) report = undefined;
  }

  return {
    message: trimmed,
    appVersion: appVersion as string | undefined,
    platform: platform as string | undefined,
    device: device as string | undefined,
    kind: kind as FeedbackKind | undefined,
    contact: reply,
    diagnostics: report,
  };
}

// Both optional context, never trusted for anything beyond the message text
// appended below — this is a feedback note, not a diagnostic report.
function buildTelegramText(payload: FeedbackPayload): string {
  const context = [
    payload.appVersion ? `v${payload.appVersion}` : null,
    payload.platform ?? null,
    payload.device ?? null,
  ]
    .filter(Boolean)
    .join(" · ");
  const lines = [
    payload.kind ? `${KINDS[payload.kind]}\n` : null,
    payload.message,
    context || payload.contact ? "" : null,
    context ? `— ${context}` : null,
    payload.contact ? `Reply to: ${payload.contact}` : null,
  ];
  return lines.filter((line) => line !== null).join("\n");
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export async function handleRequest(
  request: Request,
  env: Env,
): Promise<Response> {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.pathname !== "/feedback") {
    return jsonResponse(404, { error: "NotFound" });
  }

  // Same contract as apps/backend's own /feedback route: unset credentials
  // answer 503 rather than silently discarding what someone typed, or worse,
  // pretending it sent.
  if (!env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_CHAT_ID) {
    return jsonResponse(503, { error: "FeedbackNotConfigured" });
  }
  // A missing/failed binding must not expose an unlimited relay.
  if (!env.FEEDBACK_LIMITER) return jsonResponse(503, { error: "RateLimitNotConfigured" });
  try {
    const { success } = await env.FEEDBACK_LIMITER.limit({
      key: request.headers.get("CF-Connecting-IP") ?? "unknown",
    });
    if (!success) return new Response(JSON.stringify({ error: "RateLimited" }), {
      status: 429, headers: { "content-type": "application/json", "retry-after": "60" },
    });
  } catch {
    return jsonResponse(503, { error: "RateLimitUnavailable" });
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: "PayloadTooLarge" });
  }

  let body: unknown;
  try {
    const reader = request.body?.getReader();
    if (!reader) return jsonResponse(400, { error: "BadRequest" });
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BODY_BYTES) {
          await reader.cancel();
          return jsonResponse(413, { error: "PayloadTooLarge" });
        }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    return jsonResponse(400, { error: "BadRequest" });
  }

  const payload = parsePayload(body);
  if (!payload) {
    return jsonResponse(400, { error: "BadRequest" });
  }

  const text = buildTelegramText(payload);

  let telegramRes: Response;
  try {
    telegramRes = await fetch(
    `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
      signal: AbortSignal.timeout(10_000),
    },
  );
  } catch {
    // Exceptions can contain the token-bearing URL. Never log them.
    return jsonResponse(502, { error: "UpstreamError" });
  }

  if (!telegramRes.ok) {
    // Telegram's own response body is never surfaced to the client — only
    // its status, logged for whoever reads `wrangler tail`.
    console.log(
      JSON.stringify({
        level: "error",
        module: "feedback-worker",
        message: "telegram rejected the message",
        status: telegramRes.status,
      }),
    );
    return jsonResponse(502, { error: "UpstreamError" });
  }

  if (!payload.diagnostics) return jsonResponse(202, { delivered: true });

  // The report goes as a reply to the message it belongs to. If it cannot be
  // sent the message still was, so the answer is still 202, saying which.
  let replyTo: number | undefined;
  try {
    const sent = (await telegramRes.json()) as { result?: { message_id?: number } };
    replyTo = sent.result?.message_id;
  } catch {
    replyTo = undefined;
  }
  const form = new FormData();
  form.set("chat_id", env.TELEGRAM_CHAT_ID);
  if (replyTo !== undefined) form.set("reply_to_message_id", String(replyTo));
  form.set(
    "document",
    new Blob([payload.diagnostics], { type: "text/plain;charset=utf-8" }),
    "nex-diagnostics.txt",
  );
  let attached = false;
  try {
    const doc = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendDocument`,
      { method: "POST", body: form, signal: AbortSignal.timeout(10_000) },
    );
    attached = doc.ok;
    if (!doc.ok) {
      console.log(
        JSON.stringify({
          level: "error",
          module: "feedback-worker",
          message: "telegram rejected the diagnostics file",
          status: doc.status,
        }),
      );
    }
  } catch {
    // Never log the exception: it can carry the token-bearing URL.
    attached = false;
  }
  return jsonResponse(202, { delivered: true, diagnostics: attached });
}

export default {
  fetch: (request, env) => handleRequest(request, env),
} satisfies ExportedHandler<Env>;
