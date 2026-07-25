# apps/backend — Nex sync API (dormant in v1)

Minimal Node.js + PostgreSQL REST/JSON API. Present from v1 as infrastructure
so the contract is proven early; **not exercised by the client until v2 sync**
(04-architecture.md → Sequencing).

Phase 0 status: every product route (`/notes`, `/tags`, `/sync`) is a stub that
returns `501 Not Implemented`. Only `/health` does real work.

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
