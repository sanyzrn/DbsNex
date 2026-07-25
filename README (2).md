# Nex

> **Capture in Seconds. Find in Seconds.**

Local-first personal capture tool. The documentation set in the upstream
repository (`/doc`) is the source of truth for this build; this repository is
the phased implementation of it.

**Current phase: Phase 0 — Project Setup & Environment.** Nothing
product-specific exists yet, by design.

---

## Repository layout

The monorepo mirrors `06-development.md` → Folder Structure. Dart requires
package code to live under `lib/`, so each documented module folder appears one
level down inside its package's `lib/` — the folder names themselves are
unchanged.

```
nex/
├── apps/
│   ├── client/                    # Single Flutter app — Android, Windows, future iOS (ADR-024)
│   │   ├── lib/
│   │   │   ├── main.dart          # Phase 0 entry point
│   │   │   ├── app.dart           # Empty screen
│   │   │   ├── screens/           # Timeline, Capture, Search, NoteDetail, Settings (Phase 1)
│   │   │   ├── navigation/
│   │   │   └── platform/          # platform channels (camera, mic, filesystem)
│   │   └── test/
│   └── backend/                   # Minimal Node.js + PostgreSQL sync API (dormant in v1)
│       └── src/
│           ├── routes/            # notes, tags, sync — all stubs in Phase 0
│           ├── db/                # schema + migrations (Phase 2)
│           └── services/
├── packages/
│   ├── core/                      # Pure Dart domain logic — zero Flutter dependency
│   │   └── lib/{capture,search,tags,sync}/
│   ├── data/                      # Pure Dart local-first storage layer
│   │   └── lib/{schema,repositories,sync_client}/
│   ├── ui/                        # Shared Flutter widget/design-system package
│   │   └── lib/{widgets,tokens}/
│   └── ai/                        # Optional AI adapters (v3+) — never on the capture path
│       └── lib/{transcription,ocr,tagging}/
├── src/                           # TEMPORARY React prototype shell (see below)
└── .github/workflows/ci.yml
```

**Dependency rule:** `apps/* → packages/core → packages/data`. `packages/ui`
depends on Flutter; `packages/ai` and the sync client are optional leaves —
nothing in the capture path may import them.

`packages/core`, `packages/data` and `packages/ai` are plain Dart and run under
`dart test` with no Flutter SDK, emulator or widget-test harness.

---

## The React prototype layer (`src/`)

The target client is Flutter. `src/` exists only because this working
environment executes React/Vite, and is used to make each phase visually and
behaviourally inspectable. It is **not** a product target, it does not define
architecture, and it never overrides the documentation.

Mapping:

| React prototype | Flutter target |
|---|---|
| `src/main.tsx` | `apps/client/lib/main.dart` |
| `src/app/NexApp.tsx` | `apps/client/lib/app.dart` |

In Phase 0 the prototype renders the same thing the Flutter app renders: an
empty screen, plus a scaffold/environment status panel that reports which
Phase 0 verifications actually ran here and which are blocked.

---

## Getting started

```bash
# Flutter client (Android / Windows)
cd apps/client && flutter pub get
flutter run
flutter run -d windows

# Pure Dart packages
cd packages/core && dart pub get && dart test

# Backend
cd apps/backend && cp .env.example .env && npm install && npm run dev

# React prototype
npm install && npm run dev
```

`apps/client/android/` and `apps/client/windows/` are generated once with
`flutter create --platforms=android,windows --project-name nex_client .` — see
`apps/client/README.md`.
