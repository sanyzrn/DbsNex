# nex-feedback (Cloudflare Worker)

A standalone Cloudflare Worker with exactly one job: receive `POST /feedback`
from the Nex app and forward it to a Telegram chat. It shares no code, no
infrastructure and no deployment with `apps/backend` — no Postgres, no
Express, no rate limiter, no purge schedule. If this Worker disappeared
tomorrow, nothing else in the repo would notice.

It exists because `apps/backend` is not deployed anywhere, and standing up
Postgres + Express just to relay a short text message to Telegram is the
wrong tool for that job. A single edge function is the right size for it.

## API

`POST /feedback` — matches `apps/client/lib/platform/feedback_service.dart`'s
contract exactly, so the app needs **no code changes**, only a build-time URL
(see below).

Request body:

```json
{ "message": "string, 1-4000 chars", "appVersion": "optional, ≤40 chars", "platform": "optional, ≤20 chars" }
```

Responses:

| Status | Meaning |
|---|---|
| 202 | Delivered to Telegram |
| 400 | Bad payload (empty/too-long message, malformed JSON, wrong shape) |
| 413 | Body too large |
| 404 | Wrong method or path |
| 503 | `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` not configured |
| 502 | Telegram itself rejected the message |

The client only distinguishes 202 from everything else, so the exact
non-202 code is for humans reading logs, not for the app's own logic.

## Setup

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather) and get
   its token. Get your chat id by messaging the bot once and checking
   `https://api.telegram.org/bot<TOKEN>/getUpdates`.
2. Install dependencies: `npm install` (from this directory).
3. Local dev: copy `.dev.vars.example` to `.dev.vars`, fill in both values,
   then `npm run dev`.
4. Deploy: `npx wrangler login` once, then:
   ```
   wrangler secret put TELEGRAM_BOT_TOKEN
   wrangler secret put TELEGRAM_CHAT_ID
   npm run deploy
   ```
   Wrangler prints the deployed URL (`https://nex-feedback.<subdomain>.workers.dev`
   by default, or a custom domain if one is configured in the Cloudflare
   dashboard).
5. Build the Flutter app with that URL:
   ```
   flutter build apk --dart-define=NEX_FEEDBACK_API_URL=https://nex-feedback.<subdomain>.workers.dev
   ```
   Nothing else changes — `FeedbackService` already reads this constant and
   already handles every status code above.

## Rate limiting

Not implemented in code on purpose — Cloudflare's own dashboard-level
**Security → WAF → Rate limiting rules** covers this for a single endpoint
without adding a dependency, a binding, or a Durable Object to a worker this
small. A rule like "more than 10 requests/minute per IP to `/feedback` →
block" is the recommended equivalent of `apps/backend`'s `authLimiter`, and
it costs no code.

## Testing

`npm test` runs `src/index.test.ts` against Node's own `fetch`/`Request`/
`Response` globals — `handleRequest` is a plain `(Request, Env) => Promise<Response>`
function, so it needs no Workers runtime or Miniflare to test the logic
itself; `wrangler dev` is only for exercising the real deployment shape.
