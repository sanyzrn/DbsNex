# Nex — Roadmap

> Sequencing detail for [`02-product-specification.md`](./02-product-specification.md#roadmap-summary). Every item below is checked against the [Non-Negotiable Principles](./01-product-vision.md#non-negotiable-principles) before it ships.

**Status:** Living document · **Owner:** Product & Engineering · **Last updated:** 2026

```mermaid
timeline
    title Nex Roadmap
    v1 - MVP : Timeline : Text/Voice/Photo Capture : Tags : Search (text/tag/date/type)
    v2 - Sync & Continuity : Android <-> Windows Sync : Generic File Attachments : iOS Client
    v3 - Intelligence Layer : Speech-to-Text : OCR : Tag Suggestions : Semantic Search : Summarization : Related Notes
```

---

## Guiding Rules

1. **The capture budget is fixed.** Every version must keep capture feeling instant and offline-capable.
2. **Organize later, always.** New organization never moves into the capture flow.
3. **AI is additive.** Intelligence assists after capture; it never gates or interrupts it.
4. **Sync is the v2 headline.** Cross-device sync is the first item of v2, not the last — scattered ideas are the core problem.
5. **Scope is defended.** Features are version-gated to keep v1 light.

---

## v1 — Fastest Capture Experience (MVP)

**Theme:** Prove the two core promises — capture and find both feel instant — with the smallest possible feature set.

| Feature | Notes |
|---|---|
| Timeline (reverse-chronological, no folders) | See [Spec §Timeline](./02-product-specification.md) |
| Text capture | Zero-field entry, auto-save |
| Voice capture | Instant-start recording |
| Photo capture | Camera + gallery, two taps |
| Auto-save (no Save button) | Core non-negotiable principle |
| Tags (optional, freeform) | Only organizational primitive |
| Search — keyword, tag, date, content-type filter | Content-type layered onto the same search surface, not a separate mode |
| Local-first storage, sync-ready schema | UUIDv7 ids, `rev`, `device_id`, `media_hash`, soft delete — see [`04-architecture.md`](./04-architecture.md) |
| Minimal dormant backend | Proves the sync contract early without being load-bearing |

**Exit criteria:** Usability testing shows capture and find both feel instant (< 3 s) across all three content types; engineering performance budgets met in CI; crash-free session rate > 99.9%.

### v1.x — Stability & Polish

- Performance tuning for large timelines (thousands of notes).
- WCAG 2.1 AA accessibility audit and fixes.
- Expanded automated performance budget tests in CI.
- Localization groundwork (externalized strings; Persian as the first additional language).

---

## v2 — Sync & Continuity

**Theme:** Solve the original motivating problem in full — a user's captures should never be stranded on a single device. Sync ships as the **first** item of v2, not the last.

| Feature | Notes |
|---|---|
| **Real Android ⇄ Windows sync** | First item shipped in v2. Field-aware conflict resolution: LWW by `updated_at`/`rev` for scalar fields, **union-merge for tags** — see [`04-architecture.md`](./04-architecture.md#sync) |
| Media sync | Content-addressed uploads keyed by `media_hash`, deduplicated across devices |
| Generic file attachments (4th capture type) | Deferred from v1 specifically because of the UX decisions it requires (preview, size limits, file types) |
| iOS client | Joins the same sync backend and shared Core/Data packages |
| Backend hardening | Multi-device conflict test suite, delta-sync efficiency, deletion propagation and tombstone garbage collection |

**Exit criteria:** A user can capture offline on Android and see the same note — including tag and content edits made concurrently on both devices — converge correctly on Windows once both are online; deletion, conflict, and dedupe test suites pass.

---

## v3 — The Intelligence Layer

**Theme:** Make everything captured — regardless of original format — as findable as typed text, using AI that never interrupts capture. Full detail in [`09-ai.md`](./09-ai.md).

| Feature | Notes |
|---|---|
| **Speech-to-text transcription** | Resolves the voice-search limitation noted since v1; voice notes join full-text search |
| **OCR** | Photo notes become text-searchable |
| **Tag suggestions** | AI proposes tags post-capture; always optional, always dismissible, never auto-applied silently |
| **Semantic search** | Search by meaning, not just keyword match |
| **Summarization** | On-demand summaries for long text notes or clusters of related notes |
| **Related notes** | Surfaces connections between notes without requiring manual organization |

**Exit criteria:** Voice and photo notes are fully part of unified search without any regression to capture speed; every AI feature is independently toggleable off with zero loss of core (v1) functionality.

---

## Explicitly Deferred / Not Currently Planned

- **Export** — evaluated only after v3 stabilizes; must not imply Nex becomes a long-term storage/organization system.
- **Team/multi-user collaboration** — out of scope indefinitely; contradicts the single-player, personal-inbox identity.
- **Complex organizational features** (nested tags, folders, databases) — would contradict "Organize Later" as a philosophy, not just a feature gap.

---

## Versioning Policy

- **Major versions (v1, v2, v3)** correspond to the thematic phases above and may include platform-level or architectural shifts.
- **Minor versions** ship incremental features within an already-active theme.
- **Patch versions** are reserved for fixes and do not introduce new user-facing behavior.

Any roadmap change (addition, removal, re-sequencing) must be recorded in [`10-decisions.md`](./10-decisions.md) with rationale.
