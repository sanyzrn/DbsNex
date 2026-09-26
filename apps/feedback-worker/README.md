# nex-feedback (Cloudflare Worker)

A standalone Cloudflare Worker with exactly one job: receive `POST /feedback`
from the Nex app and forward it to a Telegram chat. It shares no code, no
infrastructure and no deployment with `apps/backend` — no Postgres, no
Express or purge schedule. Rate limiting uses a Worker binding. If this Worker disappeared
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
| 503 | Missing credentials or missing/unavailable rate limiter |
| 429 | Rate limit exceeded; retry after 60 seconds |
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

`wrangler.toml` binds `FEEDBACK_LIMITER`: 10 requests per minute per client IP.
Choose an account-unique namespace ID before deployment; bindings with the same
ID share counters. Limits are per Cloudflare location, not a global spending cap.
See [Cloudflare's binding contract](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).
The Worker fails closed with 503 if this binding is missing or fails, and 429
with Retry-After when the limit is exceeded. Only Cloudflare's CF-Connecting-IP
header is used; the app supplies no embedded authentication secret.

The request stream is bounded to 8 KiB even without Content-Length. Telegram
requests time out after 10 seconds, and errors never log a token-bearing URL.
Deployment remains pending: no bot/chat credentials, public URL or release
variable has been supplied. Unit tests mock Telegram and do not send messages.

## Testing

`npm test` runs `src/index.test.ts` against Node's own `fetch`/`Request`/
`Response` globals — `handleRequest` is a plain `(Request, Env) => Promise<Response>`
function, so it needs no Workers runtime or Miniflare to test the logic
itself; `wrangler dev` is only for exercising the real deployment shape.

## Release builds

After deploying, set the source repository Actions **variable**
`NEX_FEEDBACK_API_URL` to the HTTPS Worker base URL (without `/feedback` or a
trailing slash). `release.yml` passes it to every Android release artifact.
The bot token and chat ID belong only in Worker secrets; neither belongs in
this variable or in the APK. An unset URL keeps feedback unavailable and does
not imply the relay has been deployed.
