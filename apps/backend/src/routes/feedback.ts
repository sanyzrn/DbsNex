import type { Request, Response, Router } from "express";
import { Router as createRouter } from "express";
import { z } from "zod";

import { env } from "../env.ts";
import { AppError, BadRequest } from "../http/errors.ts";

export const feedbackRouter: Router = createRouter();

/// Long enough that a slow-but-working Telegram still gets through, short
/// enough that a hung one does not become this server's problem.
const TELEGRAM_TIMEOUT_MS = 10_000;

// Telegram's own ceiling for a sendMessage text. Anything past this is
// rejected here rather than truncated silently by Telegram on the other end.
const bodySchema = z.object({
  message: z.string().trim().min(1).max(4000),
  // Both optional context, never trusted for anything beyond the message
  // text appended below — this is a feedback note, not a diagnostic report.
  appVersion: z.string().max(40).optional(),
  platform: z.string().max(20).optional(),
});

feedbackRouter.post("/", async (req: Request, res: Response) => {
  if (!env.feedbackConfigured) {
    throw new AppError(
      503,
      "FeedbackNotConfigured",
      "feedback is not configured on this server",
    );
  }

  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) {
    throw new BadRequest(
      "invalid feedback payload",
      parsed.error.flatten().fieldErrors,
    );
  }
  const { message, appVersion, platform } = parsed.data;

  const context = [
    appVersion ? `v${appVersion}` : null,
    platform,
  ].filter(Boolean).join(" · ");
  const text = context ? `${message}\n\n— ${context}` : message;

  // Not `Response`: that name is Express's in this file.
  let telegramRes: Awaited<ReturnType<typeof fetch>>;
  try {
    telegramRes = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
        // Node's fetch has no timeout of its own. This route is
        // unauthenticated and reachable by anyone, so an upstream that
        // accepts the connection and then goes quiet would hold this request
        // — and a socket, and a slot in the rate limiter's window — open for
        // as long as the peer felt like it.
        signal: AbortSignal.timeout(TELEGRAM_TIMEOUT_MS),
      },
    );
  } catch (e) {
    // A refused connection, a DNS failure, or the timeout above. All three
    // used to escape as a 500, which says "this server is broken" about a
    // problem at the other end of a call the caller never made.
    console.log(
      JSON.stringify({
        level: "error",
        module: "backend.feedback",
        message: "telegram could not be reached",
        context: { error: e instanceof Error ? e.name : String(e) },
      }),
    );
    throw new AppError(502, "UpstreamError", "feedback could not be delivered");
  }

  if (!telegramRes.ok) {
    // Telegram's own body, not surfaced to the client — same reasoning as the
    // terminal error middleware in index.ts: an upstream's error shape is not
    // something to leak, only to log.
    console.log(
      JSON.stringify({
        level: "error",
        module: "backend.feedback",
        message: "telegram rejected the message",
        context: { status: telegramRes.status },
      }),
    );
    throw new AppError(502, "UpstreamError", "feedback could not be delivered");
  }

  res.status(202).json({ delivered: true });
});
