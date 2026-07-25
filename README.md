# Nex

> **Capture in Seconds. Find in Seconds.**

Nex is a local-first, minimal capture tool — the inbox for your mind. Instead of asking you to choose a folder, a template, or hit "Save," Nex gets out of your way: tap, capture, done. Organize later, if you ever need to.

> Nex is not a knowledge base, not a project manager, not another Notion or Obsidian. It's the fastest possible front door into whatever system you use to think.

---

## What's here

| Feature (v1) | |
|---|---|
| ⚡ One-tap capture | text, voice, or photo — zero mandatory fields |
| 💾 No Save button | every capture persists automatically |
| 🕒 Unified timeline | reverse-chronological, no default folders |
| 🔍 Fast search | text, tag, date, and content-type filters |
| 📡 Offline-first | every core flow works with zero network connection |
| 📤 Export + 🛟 backup | your data is never locked in or unprotected, from day one |

Real cross-device sync (Android ⇄ Windows ⇄ iOS) lands in v2; speech-to-text, OCR, and semantic search land in v3. Full roadmap in the docs.

---

## Documentation

This repo's full product, design, and engineering documentation lives in [`docs/`](./docs) — that folder, not this file, is the source of truth for how Nex is built:

| Doc | Purpose |
|---|---|
| [`docs/01-product-vision.md`](./docs/01-product-vision.md) | Why Nex exists, mission, non-negotiable principles |
| [`docs/02-product-specification.md`](./docs/02-product-specification.md) | Functional requirements, data model |
| [`docs/03-readme.md`](./docs/03-readme.md) | The full-length version of this file |
| [`docs/04-architecture.md`](./docs/04-architecture.md) | Local-first architecture, sync design |
| [`docs/05-design.md`](./docs/05-design.md) | Design system, UI principles, accessibility |
| [`docs/06-development.md`](./docs/06-development.md) | Folder structure, conventions, testing strategy |
| [`docs/07-contributing.md`](./docs/07-contributing.md) | How to contribute |
| [`docs/08-roadmap.md`](./docs/08-roadmap.md) | v1 → v2 → v3 sequencing |
| [`docs/09-ai.md`](./docs/09-ai.md) | AI strategy and boundaries |
| [`docs/10-decisions.md`](./docs/10-decisions.md) | Decision log (ADRs) — why things are the way they are |
| [`docs/11-build-prompt.md`](./docs/11-build-prompt.md) | Phased, execution-ready build plan |
| [`docs/12-agent-handoff-prompts.md`](./docs/12-agent-handoff-prompts.md) | Paste-ready prompts per phase for a coding agent |

**If you're a contributor or a coding agent working in this repo, read `docs/10-decisions.md` and `docs/11-build-prompt.md` before writing code.** Most judgment calls you'd otherwise have to make are already decided and justified there.

---

## Tech Stack

Flutter/Dart client (Android, Windows, future iOS from one codebase) · Node.js + PostgreSQL backend (dormant until v2 sync) · SQLite/FTS5 local storage. Full rationale in [`docs/03-readme.md`](./docs/03-readme.md#tech-stack) and [ADR-024](./docs/10-decisions.md#adr-024--flutter-as-the-single-cross-platform-client-framework).

---

## Getting Started

```bash
# run the client on Android
cd apps/client && flutter run

# run the client as a Windows desktop app
cd apps/client && flutter run -d windows
```

---

## Contributing

Please read [`docs/07-contributing.md`](./docs/07-contributing.md) first — Nex has a narrow, deliberate identity, and the single most common reason a contribution is declined is that it adds friction to capture, however good the code is.

---

## License

MIT — see [`LICENSE`](./LICENSE).
