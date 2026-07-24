# Nex

> **Capture in Seconds. Find in Seconds.**

**Status:** Authoritative · **Owner:** Product & Engineering · **Last updated:** 2026

Nex is a local-first, minimal capture tool — the inbox for your mind. Instead of asking you to choose a folder, a template, or hit "Save," Nex gets out of your way: tap, capture, done. Organize later, if you ever need to.

> Nex is not a knowledge base, not a project manager, not another Notion or Obsidian. It's the fastest possible front door into whatever system you use to think.

---

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Philosophy](#philosophy)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Contribution](#contribution)
- [License](#license)

---

## Introduction

Every second between having a thought and capturing it is a second in which that thought might disappear. Most note-taking apps optimize for organizing information well — Nex optimizes for capturing it *fast*.

- **Capture feels instant** — the product promise is under 3 seconds.
- **Finding a capture feels instant** — same promise, same 3 seconds.

Everything else — tags, filters, sync, AI — exists only to serve those two guarantees, never to compete with them. Read the full story in [`01-product-vision.md`](./01-product-vision.md).

---

## Features

### Available in v1 (MVP)

- ⚡ **One-tap capture** — a single `+` button branches into three capture types: text, voice, photo.
- 🔇 **Zero-friction recording** — voice capture starts immediately, no "press to start" step.
- 🖼️ **Instant photo capture** — camera or gallery, two taps max.
- 💾 **No Save button** — every capture persists automatically the moment it has content.
- 🗂️ **Optional tags** — the only organizational tool, entirely opt-in, applied after the fact.
- 🕒 **Unified timeline** — every capture lands in one reverse-chronological stream, no default folders.
- 🔍 **Fast search** — full-text search on text notes, plus tag / date / content-type filters.
- 📡 **Offline-first** — every core flow works with zero network connection.
- 🧬 **Sync-ready by design** — every record carries a time-ordered UUIDv7, revision, and content hash from day one, so v2 sync arrives without a rewrite.

### Planned

- 🔄 Real cross-device sync (Android ⇄ Windows, then iOS) — [`v2`](./08-roadmap.md#v2--sync--continuity)
- 🎙️ Speech-to-text transcription for voice notes — [`v3`](./08-roadmap.md#v3--the-intelligence-layer)
- 🔡 OCR for photo notes
- 🏷️ AI-assisted tag suggestions
- 🧠 Semantic search
- ✂️ Summarization & related notes

---

## Philosophy

1. **Capture First** — the user never decides *where* something goes while capturing; they just capture.
2. **Organize Later** — everything enters a single timeline; tagging is optional and deferred.
3. **Find Instantly** — search is a first-class pillar, not an afterthought.

See [`01-product-vision.md`](./01-product-vision.md) for the full philosophy and non-negotiable principles.

---

## Tech Stack

Chosen to support a **local-first, offline-first, cross-platform** product without locking the architecture into a rewrite when sync ships in v2.

| Layer | Recommendation | Why |
|---|---|---|
| **Mobile (Android, future iOS)** | React Native | Single codebase across mobile platforms; mature offline storage ecosystem |
| **Desktop (Windows)** | Tauri (preferred) or Electron | Reuses the shared UI layer; Tauri preferred long-term for footprint/performance |
| **Shared UI core** | React + TypeScript | One component/business-logic layer shared across desktop and (via React Native) mobile |
| **Local storage** | SQLite (via a platform-appropriate driver) | Durable, transactional, queryable; trivial full-text search via FTS5 |
| **State management** | Repository + reactive subscriptions; lightweight local UI state | Predictable, minimal, no over-engineering — see [`06-development.md`](./06-development.md) |
| **Backend (minimal, v1 dormant)** | Node.js + PostgreSQL, small REST/JSON API | Provides the sync-ready contract described in [`04-architecture.md`](./04-architecture.md) without being load-bearing in v1 |
| **Sync transport (v2)** | HTTPS + incremental delta sync | Simple, debuggable; pairs naturally with `updated_at`/`rev`-based conflict resolution and content-hash media dedupe |
| **AI services (v3, optional)** | On-device or server-side speech-to-text/OCR, pluggable via a provider-agnostic adapter interface | Keeps AI optional and swappable; never blocks capture — see [`09-ai.md`](./09-ai.md) |

This is a recommendation, not a hard requirement — any substitution must preserve local-first, offline-first, and minimal-footprint constraints.

---

## Project Structure

Nex is organized as a monorepo so that mobile, desktop, and backend shells can share the same core logic and data layer — essential given the product's cross-platform, sync-ready requirement from day one:

```
nex/
├── apps/
│   ├── mobile/            # React Native shell (Android, future iOS)
│   ├── desktop/           # Tauri/Electron shell (Windows)
│   └── backend/           # Minimal Node.js + PostgreSQL API (dormant in v1)
├── packages/
│   ├── core/              # Shared business logic (capture, search, tags, sync orchestration)
│   ├── data/              # Local-first storage layer, schema, sync-ready models
│   ├── ui/                # Shared design system components
│   └── ai/                # Optional AI adapters (transcription, OCR, tagging) — v3+
├── docs/                  # This documentation set
└── README.md
```

See [`06-development.md`](./06-development.md) for full folder conventions inside each package.

---

## Getting Started

> Nex ships per-platform (mobile/desktop clients + backend). Refer to each app package's own setup instructions once those packages are scaffolded.

```bash
# install dependencies at the workspace root
npm install

# run the shared core's tests
npm run test --workspace=packages/core

# start the desktop shell in development mode
npm run dev --workspace=apps/desktop
```

See [`06-development.md`](./06-development.md) for coding standards and testing strategy.

---

## Roadmap

| Version | Focus |
|---|---|
| **v1** | Fastest capture experience: timeline, text/voice/photo capture, tags, search |
| **v2** | Sync & continuity: real Android ⇄ Windows sync, generic file attachments, iOS |
| **v3** | Intelligence layer: speech-to-text, OCR, tag suggestions, semantic search, summarization, related notes |

Full detail in [`08-roadmap.md`](./08-roadmap.md).

---

## Documentation

| Document | Purpose |
|---|---|
| [`01-product-vision.md`](./01-product-vision.md) | Why Nex exists, mission, principles |
| [`02-product-specification.md`](./02-product-specification.md) | What is being built, requirements, data model |
| [`04-architecture.md`](./04-architecture.md) | Technical architecture, local-first design, sync |
| [`05-design.md`](./05-design.md) | Design language, UI principles, accessibility |
| [`06-development.md`](./06-development.md) | Developer guide, conventions, testing |
| [`07-contributing.md`](./07-contributing.md) | How to contribute |
| [`08-roadmap.md`](./08-roadmap.md) | Version plan, MVP through v3 |
| [`09-ai.md`](./09-ai.md) | AI strategy and boundaries |
| [`10-decisions.md`](./10-decisions.md) | Architectural and product decision log (ADRs) |

---

## Contribution

Contributions are welcome. Please read [`07-contributing.md`](./07-contributing.md) before opening a pull request — any contribution must preserve Nex's core identity (see [Philosophy](#philosophy)). Features that add friction to capture will not be accepted, regardless of technical quality.

---

## License

Nex is released under the [MIT License](./LICENSE).
