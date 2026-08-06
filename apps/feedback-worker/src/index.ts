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
}

// Telegram's own ceiling for a sendMessage text — reject past this rather
// than let Telegram truncate it silently on the other end.
const MAX_MESSAGE = 4000;
const MAX_CONTEXT_FIELD = 40;

// A generous cap on the request body itself, checked before it's ever
// parsed — mirrors apps/backend's `express.json({ limit: "8kb" })`. Workers
// have their own platform-level request size ceiling too; this just fails
// fast and cheaply for the common case of an oversized payload.
const MAX_BODY_BYTES = 8 * 1024;

interface FeedbackPayload {
  message: string;
  appVersion?: string;
  platform?: string;
}

function parsePayload(body: unknown): FeedbackPayload | null {
  if (typeof body !== "object" || body === null) return null;
  const { message, appVersion, platform } = body as Record<string, unknown>;

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

  return {
    message: trimmed,
    appVersion: appVersion as string | undefined,
    platform: platform as string | undefined,
  };
}

// Both optional context, never trusted for anything beyond the message text
// appended below — this is a feedback note, not a diagnostic report.
function buildTelegramText(payload: FeedbackPayload): string {
  const context = [
    payload.appVersion ? `v${payload.appVersion}` : null,
    payload.platform ?? null,
  ]
    .filter(Boolean)
    .join(" · ");
  return context ? `${payload.message}\n\n— ${context}` : payload.message;
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

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: "PayloadTooLarge" });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "BadRequest" });
  }

  const payload = parsePayload(body);
  if (!payload) {
    return jsonResponse(400, { error: "BadRequest" });
  }

  const text = buildTelegramText(payload);

  const telegramRes = await fetch(
    `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
    },
  );

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

  return jsonResponse(202, { delivered: true });
}

export default {
  fetch: (request, env) => handleRequest(request, env),
} satisfies ExportedHandler<Env>;
