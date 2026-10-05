# apps/backend — Nex sync API

Node.js + PostgreSQL REST/JSON API for cross-device sync. It is built and
tested — device auth (`/auth`), the sync exchange (`/sync`), read routes
(`/notes`, `/tags`), feedback (`/feedback`) and health checks
(`/health`, `/health/live`, `/health/ready`) — and CI runs the live
SyncClient against it with PostgreSQL. It is **not deployed and has no
pairing flow in the app yet**; that is release 2.0's work (Phase 2,
04-architecture.md → Sequencing, and items 9–12 in `docs/11-roadmap-2.0.md`).

## Run locally

```bash
cp .env.example .env
npm install
npm run dev        # http://localhost:4000/health
```

A local PostgreSQL instance is expected at `DATABASE_URL`. If it is not
running, the API still starts and `/health` reports `"database": "down"` —
reads fail open (06-development.md → Error Handling).

## Verify

```bash
npm run typecheck
npm run lint
```
