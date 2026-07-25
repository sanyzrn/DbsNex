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
- 🔇 **Zero-friction recording** — voice capture starts immediately, no "press to start" step. *Voice (and photo) notes are searchable by tag/date in v1, not by keyword — full transcription/OCR search lands in v3 (see [`09-ai.md`](./09-ai.md)).*
- 🖼️ **Instant photo capture** — camera or gallery, two taps max.
- 💾 **No Save button** — every capture persists automatically the moment it has content.
- 🗂️ **Optional tags** — the only organizational tool, entirely opt-in, applied after the fact.
- 🕒 **Unified timeline** — every capture lands in one reverse-chronological stream, no default folders.
- 🔍 **Fast search** — full-text search on text notes, plus tag / date / content-type filters.
- 📡 **Offline-first** — every core flow works with zero network connection.
- 🧬 **Sync-ready by design** — every record carries a time-ordered UUIDv7, revision, and content hash from day one, so v2 sync arrives without a rewrite.
- 📤 **Data export** — one-tap JSON + Markdown + media export, fully offline. Data belongs to the user from day one, not from v2 or v3.
- 🛟 **Automatic backup + restore** — rotating local backups protect against device loss or corruption, independent of sync.

### Also in v1.x
- 🏠 **Home-screen widget + share-intent capture** — capture without opening the app at all; see [ADR-027](./10-decisions.md#adr-027--os-level-capture-surfaces-home-screen-widget-share-intent-added-to-v1x-scope).

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
| **Client (Android, Windows, future iOS)** | **Flutter / Dart** — one codebase for all three | A single language and rendering engine across mobile and desktop, compiled to native (not a webview), avoids maintaining a separate mobile stack and a separate Electron/Tauri desktop stack in parallel. Built-in bidirectional text support handles Persian content inside an English/LTR shell (see [`05-design.md`](./05-design.md)) without extra plugins. Full control over custom gestures and transitions (Capture Sheet, swipe actions — see [ADR-022](./10-decisions.md#adr-022--configurable-swipe-actions-limited-to-a-fixed-two-action-set)) without wrestling a browser engine for animation performance. |
| **Local storage** | SQLite via `sqflite`/`drift` | Durable, transactional, queryable local-first storage; FTS5 for full-text search, matching the data model in [`02-product-specification.md`](./02-product-specification.md#data-model) |
| **State management** | Reactive repository + a lightweight Flutter state layer (`Provider`/`Riverpod`) | Predictable, minimal, no over-engineering — see [`06-development.md`](./06-development.md) |
| **Backend (minimal, v1 dormant)** | Node.js + PostgreSQL, exposed via a small REST/JSON API | Client language choice doesn't constrain the backend; provides the sync-ready contract described in [`04-architecture.md`](./04-architecture.md) without being load-bearing in v1 |
| **Sync transport (v2)** | HTTPS + incremental delta sync | Simple, debuggable; pairs naturally with `updated_at`/`rev`-based conflict resolution and content-hash media dedupe |
| **AI services (v3, optional)** | On-device or server-side speech-to-text/OCR, pluggable via a provider-agnostic adapter interface | Keeps AI optional and swappable; never blocks capture — see [`09-ai.md`](./09-ai.md) |

This is a recommendation, not a hard requirement — any substitution must preserve local-first, offline-first, and minimal-footprint constraints. See [ADR-024](./10-decisions.md#adr-024--flutter-as-the-single-cross-platform-client-framework) for why Flutter was chosen over a React Native + Electron/Tauri split.

---

## Project Structure

Nex is organized as a monorepo so that mobile, desktop, and backend shells can share the same core logic and data layer — essential given the product's cross-platform, sync-ready requirement from day one:

```
nex/
├── apps/
│   ├── client/             # Single Flutter app target — builds to Android, Windows, future iOS
│   └── backend/            # Minimal Node.js + PostgreSQL API (dormant in v1)
├── packages/
│   ├── core/                # Shared Dart package: capture, search, tags, sync orchestration
│   ├── data/                 # Local-first storage layer (SQLite), schema, sync-ready models
│   ├── ui/                   # Shared Flutter widget/design-system package
│   └── ai/                   # Optional AI adapters (transcription, OCR, tagging) — v3+
├── docs/                    # This documentation set
└── README.md
```

Unlike a React Native + Electron split, Flutter builds Android, Windows, and iOS from the **same app target** (`apps/client`), so there is one client app, not two — see [ADR-024](./10-decisions.md#adr-024--flutter-as-the-single-cross-platform-client-framework). `packages/core` and `packages/data` are plain Dart, with no Flutter/UI dependency, so they stay fully unit-testable in isolation.

See [`06-development.md`](./06-development.md) for full folder conventions inside each package.

---

## Getting Started

> Nex ships per-platform (Android, Windows, future iOS) from one Flutter app target, plus a backend. Refer to each package's own setup instructions once scaffolded.

```bash
# fetch dependencies for the client app
cd apps/client && flutter pub get

# run the shared core package's tests
cd packages/core && dart test

# run the client on a connected Android device or emulator
cd apps/client && flutter run

# run the client as a Windows desktop app
cd apps/client && flutter run -d windows
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
| [`11-build-prompt.md`](./11-build-prompt.md) | Phased, execution-ready build prompt for a developer or AI coding agent |
| [`12-agent-handoff-prompts.md`](./12-agent-handoff-prompts.md) | Literal, paste-ready prompts per phase for a GitHub-connected coding agent |

---

## Contribution

Contributions are welcome. Please read [`07-contributing.md`](./07-contributing.md) before opening a pull request — any contribution must preserve Nex's core identity (see [Philosophy](#philosophy)). Features that add friction to capture will not be accepted, regardless of technical quality.

---

## License

Nex is released under the [MIT License](./LICENSE).
