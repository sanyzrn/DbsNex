# Nex — Phased Build Prompt

> This document is a task-executable companion to the rest of `/docs`. It exists so a junior developer **or** a mid-level AI coding agent (e.g., Claude Code) can build Nex phase by phase, with minimal ambiguity and a clear stopping point after each phase.

**Status:** Authoritative · **Owner:** Engineering · **Last updated:** 2026

---

## How to Use This Document

1. **The linked docs are the source of truth, not this file.** Every task below points to the specific doc section that defines it in full. If this prompt and a linked doc ever disagree, the doc wins — stop and flag it rather than guessing which is right.
2. **Read before writing code.** Before Phase 1, read in full: [`01-product-vision.md`](./01-product-vision.md), [`02-product-specification.md`](./02-product-specification.md), [`04-architecture.md`](./04-architecture.md), [`05-design.md`](./05-design.md), [`06-development.md`](./06-development.md), [`10-decisions.md`](./10-decisions.md). This is not optional preamble — most "obvious-seeming" features that would normally require a judgment call are already decided in these docs (see the [Decision-Making Heuristic](./10-decisions.md#decision-making-heuristic)).
3. **Phases are sequential gates, not suggestions.** Do not start Phase *N+1* until Phase *N*'s Definition of Done is fully met and verified. Sync (Phase 2) in particular must not begin on top of a shaky Phase 1 — the whole point of the roadmap's sequencing is that each phase proves itself before the next is layered on.
4. **When in doubt, stop and ask — do not invent a plausible-sounding feature.** This project's single most common failure mode, per [`07-contributing.md`](./07-contributing.md#what-we-will-not-merge), is well-intentioned scope creep: a required field, a folder, a confirmation dialog, a pinning feature. If a task feels like it needs one of these to "feel complete," that feeling is the signal to stop, not to proceed.
5. **Every PR/commit is checked against the [Non-Negotiable Principles](./01-product-vision.md#non-negotiable-principles)** before it's considered done, regardless of which phase it belongs to.

---

## Phase 0 — Project Setup & Environment

**Goal:** An empty-but-correct skeleton that builds, runs, and matches the documented structure exactly — nothing product-specific yet.

**Tasks:**
- [ ] Scaffold the monorepo exactly per [`06-development.md`](./06-development.md#folder-structure): `apps/client` (Flutter), `apps/backend` (Node.js + PostgreSQL), `packages/core`, `packages/data`, `packages/ui`, `packages/ai`.
- [ ] `packages/core` and `packages/data` must have **zero Flutter dependency** — pure Dart packages, verified by the fact that `dart test` runs them without a Flutter SDK or widget test harness.
- [ ] `apps/client` builds and launches an empty screen on both an Android emulator and Windows desktop from the same codebase (this is the whole point of [ADR-024](./10-decisions.md#adr-024--flutter-as-the-single-cross-platform-client-framework) — verify it early, not after a lot of code depends on it).
- [ ] `apps/backend` runs locally (even if every route is a stub) against a local PostgreSQL instance.
- [ ] CI wired for: Dart analyze/lint, `dart test` for `packages/*`, Flutter build check for `apps/client`, backend lint/typecheck. It's fine if there are no real tests yet — the pipeline itself must exist before Phase 1 code lands.

**Definition of Done:** A fresh clone can run `flutter run` on Android and `flutter run -d windows` from `apps/client` and see an empty app; `apps/backend` starts locally; CI is green on an empty/skeleton commit.

---

## Phase 1 — v1 MVP: the two core promises

**Goal:** Capture feels instant. Finding feels instant. Nothing else exists yet.

**Primary references:** [`02-product-specification.md`](./02-product-specification.md) FR-1 through FR-5, [`01-product-vision.md`](./01-product-vision.md#non-negotiable-principles), [`04-architecture.md`](./04-architecture.md), [`05-design.md`](./05-design.md).

### 1.1 — Data layer & schema
- Implement the `Note` and `Tag` schema exactly as specified in [Data Model](./02-product-specification.md#data-model): `id` as **UUIDv7** (not v4, not auto-increment — see [ADR-018](./10-decisions.md#adr-018--uuidv7-as-the-note-identifier)), `created_at`/`updated_at`, `deleted_at` (soft delete), `device_id`, `rev`, `media_hash` (nullable, computed for voice/photo notes even though unused until Phase 2 — see [ADR-019](./10-decisions.md#adr-019--content-addressed-media-for-dedupe)).
- SQLite via `drift` or `sqflite`; FTS5 index on `content` for text notes only.
- `Tag.color` is present in the schema now (nullable) even though the tag-color UI ships slightly later in this phase — see [ADR-021](./10-decisions.md#adr-021--optional-user-chosen-tag-accent-color).
- **Acceptance:** repository-level integration tests against a real (temp) SQLite DB for insert, soft-delete, tag attach/detach, and FTS query — per the [Testing Strategy](./06-development.md#testing-strategy) priority table (Data layer = Critical).

### 1.2 — Core domain package
- Pure-Dart use cases in `packages/core`: `submitCapture`, `addTag`/`removeTag`, `search(query, filters)`. No storage or UI code here — these call `packages/data` repository interfaces.
- **Acceptance:** high-coverage unit tests with no DB or widget dependency (per Testing Strategy, Core = Highest priority).

### 1.3 — Timeline
- Reverse-chronological, newest first, per [FR-2.1–2.5](./02-product-specification.md#fr-2--timeline). No default folders, no pinning, no manual reordering.
- Card rendering adapts to type (text snippet / voice waveform+duration / photo thumbnail) per [`05-design.md`](./05-design.md#components).
- Infinite scroll/virtualized list for large note counts.

### 1.4 — Quick Capture
- The `+` action, exactly per [FR-1.1–1.9](./02-product-specification.md#fr-1--capture): three types only (Text, Voice, Photo), **zero mandatory fields**, auto-save on first content, no Save button anywhere, direct return to Timeline, silent discard of an empty capture.
- This is the highest-scrutiny part of the whole codebase — re-read [ADR-001](./10-decisions.md#adr-001--capture-has-zero-mandatory-fields) and [ADR-002](./10-decisions.md#adr-002--no-save-button-auto-save-on-content-presence) before implementing. If a reviewer (human or AI) finds themselves adding a confirmation step, a title field, or a folder picker "just in case," that is a direct regression of this phase's entire purpose.

### 1.5 — Tags
- Optional, freeform, many-to-many, per [FR-3](./02-product-specification.md#fr-3--tags). Suggested starter tags offered, never enforced.
- Optional per-tag accent color (small dot only, user-chosen from a constrained palette, never during capture) per [Tag Accent Color](./05-design.md#tag-accent-color).

### 1.6 — Search
- Text/tag/date/type-filter per [FR-4](./02-product-specification.md#fr-4--search), content-type as a filter layered on the same surface, **not** a separate mode ([ADR-011](./10-decisions.md#adr-011--content-type-filter-is-part-of-the-single-search-surface-not-a-separate-mode)).
- Voice notes excluded from keyword match in this phase; UI must label them "searchable by tag/date only" (FR-4.6).

### 1.7 — Visual design pass
- Implement the Light/Dark token pairs from [`05-design.md`](./05-design.md#color-philosophy) — monochrome surface, no categorical color anywhere except the tag accent dot.
- Typography, spacing, and motion per the same doc. Respect the 44×44pt tap target and WCAG AA contrast requirements now, not as a later retrofit.

### 1.8 — Offline verification
- Manually (and then automatically, in CI) verify every Phase 1 flow works with the network fully disabled. There is no code path in this phase that should touch the network at all.

**Definition of Done (Phase 1):** matches the [v1.0 Release Plan exit criteria](./02-product-specification.md#release-plan) — all FR-1 through FR-5 pass, capture and search both consistently *feel* instant in manual testing, and the engineering budgets in [Non-Functional Requirements](./02-product-specification.md#non-functional-requirements) (cold start < 1.5s, capture-ready < 1s, search query < 200ms) are met, not just "close."

**Stop-and-verify checklist before Phase 1.x:**
- [ ] Every capture type reachable in one tap from Timeline, with zero fields.
- [ ] No Save button exists anywhere in the codebase.
- [ ] No folders, pinning, or manual reordering exist anywhere in the codebase.
- [ ] All Phase 1 flows pass with airplane mode on.

---

## Phase 1.x — Stability, Polish, Swipe Actions, Comfort Mode

**Goal:** Harden what Phase 1 shipped, then add the two scoped quality-of-life features that don't touch capture.

**Primary references:** [`08-roadmap.md`](./08-roadmap.md#v1x--stability--polish), [ADR-022](./10-decisions.md#adr-022--configurable-swipe-actions-limited-to-a-fixed-two-action-set), [ADR-023](./10-decisions.md#adr-023--comfort-mode-as-an-independent-axis-from-lightdark-theme).

### 1.x.1 — Stability
- Performance tuning for large timelines (thousands of notes).
- WCAG 2.1 AA accessibility audit and fixes.
- Expanded automated performance-budget tests in CI (make the Phase 1 budgets regression-proof, not just met once).
- Localization groundwork: externalize all UI strings now, even though the UI ships English-only; Persian is the first planned language pack ([ADR-015](./10-decisions.md#adr-015--persian-as-the-first-additional-language-target-kept-as-a-non-functional-requirement-rather-than-a-v1-feature)). Note the app shell stays English/LTR while note **content** must render correctly for RTL scripts via `dir`-equivalent (Flutter's `Directionality`/bidi text handling) — this is already exercised in the mockup and must hold in the real client.

### 1.x.2 — Swipe actions
- Implement exactly two swipe-revealed actions on Timeline cards — **Delete** (soft-delete, undoable via toast) and **Add Tag** — per [FR-2.6–2.8](./02-product-specification.md#fr-2--timeline). Do **not** build a general/extensible action framework; the set is deliberately closed at two.
- Direction-to-action mapping is a local, user-configurable preference (not synced in this phase), exposed from a new, minimal **Settings** sheet reached by tapping the avatar — not a nested settings app.
- Visual spec (threshold, reveal color for Delete vs. neutral for Add Tag, one-open-card-at-a-time) is in [Swipe Actions](./05-design.md#swipe-actions).
- **Do not add Pin/Archive as a third swipe action** — Nex has already ruled out pinning and manual reordering in the Timeline; re-adding it here through swipe would quietly reverse that decision.

### 1.x.3 — Comfort Mode
- Implement as an independent toggle from Light/Dark theme (not a third theme) per [Comfort Mode](./05-design.md#comfort-mode) — same Settings sheet as the swipe mapping.
- Use the exact token deltas in the doc's table; verify WCAG AA is still met for both Comfort on/off in both themes.
- Default off in both themes.

**Definition of Done (Phase 1.x):** Settings sheet exists with exactly two preference groups (swipe mapping, appearance incl. Comfort Mode); swipe actions work with the fixed two-action set and configurable mapping; Comfort Mode token swap verified in both themes; accessibility audit passed; all Phase 1 performance budgets still hold.

---

## Phase 2 — v2: Sync & Continuity

**Goal:** A user's captures are never stranded on one device. This is the phase most likely to introduce subtle, silent bugs — treat the testing requirements below as non-negotiable, not aspirational.

**Primary references:** [Sync Strategy](./02-product-specification.md#sync-strategy), [`04-architecture.md`](./04-architecture.md#sync), [ADR-007](./10-decisions.md#adr-007--sync-ships-as-the-first-item-of-v2-not-the-last), [ADR-018](./10-decisions.md#adr-018--uuidv7-as-the-note-identifier), [ADR-019](./10-decisions.md#adr-019--content-addressed-media-for-dedupe), [ADR-020](./10-decisions.md#adr-020--union-merge-for-concurrent-tag-edits-not-whole-record-last-writer-wins).

### 2.1 — Backend
- Implement the real REST/JSON API in `apps/backend` (routes for notes, tags, sync) against PostgreSQL, matching the local schema per [`04-architecture.md`](./04-architecture.md#storage).
- Push/pull endpoints using `updated_at`/`rev`-based delta sync.

### 2.2 — Sync client & conflict resolution — the highest-scrutiny part of this phase
- Implement the **field-aware** conflict resolution exactly as documented, not a simpler whole-record last-writer-wins:
  - Scalar fields (`content`, `media_uri`): last-writer-wins by `updated_at`/`rev`.
  - **Tags: union-merge.** The result is the union of both devices' tag sets. A tag must never be silently dropped because it lost a whole-record race. This is the single most likely place for a plausible-looking-but-wrong implementation to slip through review — an implementer defaulting to "just apply LWW to the whole note" will pass naive tests and silently lose tags in production. Do not do this.
  - Media: deduplicated by `media_hash`, never re-uploaded if already present.
  - Deletions: soft, replicated as tombstones, garbage-collected after a retention window once all known devices acknowledge them.
- Offline-tolerant outbox: a device offline for weeks must reconcile cleanly on reconnect.

### 2.3 — Required test matrix (do not skip any row)
| Scenario | Must verify |
|---|---|
| Same note, `content` edited on two devices before either syncs | Later `updated_at` wins; no crash, no duplicate |
| Same note, tag added on Device A, `content` edited on Device B, both offline, then both sync | **Both changes survive** — the tag is not lost |
| Same note, tag added on Device A, a different tag removed on Device B, both offline | Union-merge resolves correctly; no tag silently reappears or vanishes incorrectly |
| Note deleted on Device A, edited on Device B, before either syncs | Deletion wins (tombstone); the edit is recoverable from history, not silently destroyed |
| Identical photo/voice file captured or already present on two devices | Deduplicated by `media_hash`; not uploaded or stored twice |
| Device offline for an extended period, then reconnects | Outbox flushes cleanly; no data loss; no duplicate notes |

### 2.4 — Also in this phase
- Generic file attachments (4th capture type) — deliberately deferred until now specifically so its UX (preview, size limits, file types) can be designed properly, not rushed into Phase 1 (see [ADR-008](./10-decisions.md#adr-008--generic-file-attachments-deferred-out-of-v1)).
- iOS client target enabled from the same Flutter codebase.

**Definition of Done (Phase 2):** matches the [v2.0 Release Plan exit criteria](./02-product-specification.md#release-plan) — every row in the test matrix above passes, sync convergence ≥ 99.9% in testing, capture remains fully offline-capable and under budget throughout.

---

## Phase 3 — v3: The Intelligence Layer

**Goal:** Everything captured becomes as findable as typed text — using AI that never once touches the capture path.

**Primary references:** [`09-ai.md`](./09-ai.md), [ADR-009](./10-decisions.md#adr-009--ai-capabilities-deferred-to-v3-after-capture-v1-and-sync-v2-are-solid).

### 3.1 — AI adapter layer
- Implement `AIAdapter` in `packages/ai` exactly as specified in [AI Adapter Interface](./06-development.md#ai-adapter-interface) — every capability nullable/optional, so a partial adapter is not an error state.
- `packages/ai` must be deletable from the build entirely with `packages/core`, `packages/data`, and `apps/client` still compiling and the v1 MVP still fully functional — this is a build-time test, not just a design intention (see [`09-ai.md`](./09-ai.md#architectural-boundary)).

### 3.2 — Capabilities, in this order
1. **Transcription** — resolves the standing voice-search limitation from Phase 1; once available, voice notes join full-text search.
2. **OCR** — photo notes become text-searchable.
3. **Tag suggestions, semantic search, summarization, related notes** — each shipped independently, each independently toggleable off with zero loss of v1 functionality.

### 3.3 — Non-negotiables for this phase
- Every capability is post-capture, asynchronous, dismissible, and non-destructive (derived data like `transcript_text` stored alongside, never overwriting original content).
- No note content leaves the device by default; any cloud-backed capability is opt-in and disclosed per capability, not a blanket toggle.
- No AI content in logs, ever (per [Logging](./06-development.md#logging)).

**Definition of Done (Phase 3):** matches the [v3.0 Release Plan exit criteria](./02-product-specification.md#release-plan) — voice/photo notes fully searchable without any regression to capture speed; every AI feature independently toggleable with zero loss of core functionality when off; `packages/ai` deletion test passes.

---

## Cross-Phase Rules (apply at every phase, not just once)

- **Run every change through the [Decision-Making Heuristic](./10-decisions.md#decision-making-heuristic)** before considering it done: protects the capture/find performance promise; preserves local-first/offline; adds no decision at capture time; learnable in under 30 seconds; reinforces "inbox, not system."
- **Testing priorities** follow the table in [`06-development.md`](./06-development.md#testing-strategy) — Core domain and Data layer are the highest-scrutiny areas in every phase, not just Phase 1.
- **Error handling and logging** rules in [`06-development.md`](./06-development.md#error-handling) apply from Phase 0 onward — no raw exceptions surfaced to the UI, no note content in logs, ever.
- **What never gets built, at any phase**, per [`07-contributing.md`](./07-contributing.md#what-we-will-not-merge): a required field/dialog/decision at capture time; folders, notebooks, or hierarchies; a general-purpose knowledge-base or project-management feature; an open-ended swipe-action framework; AI as a blocking step in capture.
- **If a task in this document seems to conflict with a linked doc, or seems to require inventing a decision the docs don't cover, stop and surface the ambiguity explicitly rather than resolving it silently.** A wrong guess that "looks reasonable" is far more costly to catch later than a paused task with a clear question attached.
