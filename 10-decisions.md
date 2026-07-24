# Nex — Decision Log

> A running record of significant product and architectural decisions, with rationale. New entries are appended chronologically; existing entries are never edited retroactively — superseding decisions reference the ones they replace.

**Status:** Living document · **Owner:** Product & Engineering · **Last updated:** 2026

Each entry follows a lightweight ADR format: **Context → Decision → Rationale → Alternatives Considered → Status.**

---

## ADR-001 — Capture has zero mandatory fields

- **Context:** Traditional note apps require a title, folder, or category before saving, introducing friction and causing ideas to be lost.
- **Decision:** No field is ever mandatory during capture. Title, folder, and tags are all optional and can be added later, if at all.
- **Rationale:** Directly serves the "Capture First" pillar; friction at capture time is the core problem Nex exists to solve.
- **Alternatives Considered:** Optional-but-suggested title field pre-filled with a timestamp — rejected because even a pre-filled field invites a decision ("should I change this?").
- **Status:** Accepted, v1.

---

## ADR-002 — No Save button; auto-save on content presence

- **Context:** A visible Save button implies the possibility of losing unsaved work and adds one more required action to capture.
- **Decision:** Notes persist automatically as soon as they contain content (first keystroke, recording stop, confirmed photo). There is no Save action anywhere in the capture flow.
- **Rationale:** Removes both the interaction cost and the cognitive overhead of wondering "did I save that?" — supporting user trust as a core value.
- **Alternatives Considered:** Debounced auto-save with a visible "Saved" indicator — partially adopted (brief confirmation animation) but without ever exposing a manual Save control.
- **Status:** Accepted, v1.

---

## ADR-003 — Timeline as the only home screen, no default folders

- **Context:** Folder-first organization forces a categorization decision before or during capture.
- **Decision:** All notes land in a single, reverse-chronological Timeline. No default or system-created folders exist.
- **Rationale:** Encodes "Organize Later" structurally — there is no organizational scaffold to interact with unless the user creates one via tags.
- **Alternatives Considered:** A default "Inbox" folder with the option to create others — rejected as functionally redundant with the Timeline itself and a source of confusion.
- **Status:** Accepted, v1.

---

## ADR-004 — Tags are the only organizational primitive in v1

- **Context:** Users will eventually want some way to group related captures, but structure added at v1 risks recreating folder-like complexity.
- **Decision:** Tags — flat, freeform, optional, many-to-many — are the sole organizational tool in the MVP. No folders, notebooks, nested tags, or projects.
- **Rationale:** Tags can be applied after the fact with zero impact on capture speed, satisfying "Organize Later" while giving users a lightweight structuring option.
- **Alternatives Considered:** Nested/hierarchical tags — rejected for v1 as unnecessary complexity relative to the MVP's scale and philosophy of simplicity.
- **Status:** Accepted, v1. Revisit only if user research at scale demonstrates flat tags are insufficient.

---

## ADR-005 — Voice notes are searchable only by tag/date/type in v1, not by keyword

- **Context:** The original concept introduced full-text search as a core pillar while simultaneously excluding speech-to-text from MVP scope — a direct contradiction, since a voice note has no text body without transcription.
- **Decision:** In v1 and v2, voice notes are excluded from keyword search and discoverable only via tag, date, and content-type filters. The UI explicitly labels voice notes as "searchable by tag/date only."
- **Rationale:** Resolves the contradiction honestly rather than silently shipping broken search expectations or inflating MVP scope with early speech-to-text.
- **Alternatives Considered:** (1) Include basic on-device speech-to-text in v1 — rejected, scope creep and quality risk. (2) Silently omit the limitation from the UI — rejected as a trust violation.
- **Status:** Accepted, v1. Superseded in effect (not retroactively) by transcription shipping in v3 (see [`09-ai.md`](./09-ai.md)).

---

## ADR-006 — Local-first architecture with sync-ready schema from day one

- **Context:** The user's original need (Android + Windows, later iOS, with full sync) is a v2 goal, but retrofitting sync onto a schema not designed for it typically requires a costly rewrite.
- **Decision:** Every record — from v1 — carries a stable identifier, `created_at`/`updated_at` timestamps, `device_id`, a revision counter, and a soft-delete field, even though sync is inactive until v2. A minimal backend exists from v1 as dormant infrastructure.
- **Rationale:** Ensures v2 sync is additive — new capability, same schema — rather than a breaking migration.
- **Alternatives Considered:** Ship v1 with a simple auto-increment schema and migrate later — rejected because migrating existing user data to sync-compatible identifiers post-hoc is materially riskier and more expensive.
- **Status:** Accepted, v1. Refined by [ADR-018](#adr-018--uuidv7-as-the-note-identifier) (identifier choice) and [ADR-019](#adr-019--content-addressed-media-for-dedupe) (media field).

---

## ADR-007 — Sync ships as the first item of v2, not the last

- **Context:** Sync is often deprioritized to the end of a release because it's technically complex, but for Nex, unsynced multi-device use directly perpetuates the product's founding problem (scattered, lost ideas).
- **Decision:** Real Android ⇄ Windows sync is the first feature delivered in v2, ahead of generic file attachments and the iOS client.
- **Rationale:** Without sync, a user who captures on their phone and needs it on their desktop is exactly as stuck as before adopting Nex.
- **Alternatives Considered:** Ship generic file attachments first as a "quick win" — rejected because it doesn't address the more foundational gap.
- **Status:** Accepted, planned for v2.

---

## ADR-008 — Generic file attachments deferred out of v1

- **Context:** A fourth capture type ("generic file") requires UX decisions (preview strategy, size limits, supported file types) that conflict with "zero decisions at capture time" if rushed.
- **Decision:** Generic file attachments move to v2, to be designed deliberately.
- **Rationale:** Protects v1 scope and velocity; avoids shipping a capture type whose UX would require exactly the kind of in-the-moment decision-making Nex is built to eliminate.
- **Alternatives Considered:** Ship a minimal, size-capped generic file type in v1 — rejected as poor cost/benefit relative to the MVP's two core goals.
- **Status:** Accepted, deferred to v2.

---

## ADR-009 — AI capabilities deferred to v3, after capture (v1) and sync (v2) are solid

- **Context:** AI could plausibly be introduced earlier, but doing so risks distracting from proving core, non-AI product value first.
- **Decision:** All AI capabilities ship in v3, sequenced after the Timeline/capture/search MVP (v1) and cross-device sync (v2) are both stable.
- **Rationale:** Speed and reliability of capture and sync are the product's foundation; AI is explicitly optional and additive and should be layered onto a proven base.
- **Alternatives Considered:** Introduce lightweight on-device tag suggestions earlier (e.g., v1.x) — rejected to keep milestones focused and avoid partial, inconsistent AI coverage before the intelligence layer is designed holistically.
- **Status:** Accepted, planned for v3.

---

## ADR-010 — Monochrome, minimal visual design with no categorical color coding

- **Context:** Many note/task apps use color to encode categories, priorities, or tags, which can subtly reintroduce organizational decision-making at the point of interaction.
- **Decision:** Nex's UI uses a strictly black-and-white (plus grayscale) palette in both light and dark modes; tags and content types are never color-coded.
- **Rationale:** Reinforces the "light," non-software feeling described in the UX philosophy, and prevents color from becoming an implicit, uncontrolled categorization system.
- **Alternatives Considered:** A small palette of accent colors for tags — rejected as inconsistent with the minimal, decision-free design philosophy.
- **Status:** Accepted, v1.

---

## ADR-011 — Content-type filter is part of the single search surface, not a separate mode

- **Context:** A distinct search mode per content type would fragment the search UI into multiple screens/flows.
- **Decision:** Content-type (text/voice/photo) is implemented as a filter layered onto the same tag/date search screen, not a separate search mode.
- **Rationale:** Keeps the v1 search UI to a single, learnable surface, consistent with "every feature learnable in under 30 seconds," and reduces implementation and maintenance complexity.
- **Alternatives Considered:** Separate top-level tabs per content type — rejected as unnecessary UI fragmentation for what is, functionally, just another filter.
- **Status:** Accepted, v1.

---

## ADR-012 — Monorepo structure (`apps/*` + `packages/*`) over a flat `src/` layout

- **Context:** Two independent documentation drafts proposed different project layouts: one a monorepo with separate `apps/mobile`, `apps/desktop`, `apps/backend` shells around shared `packages/core`, `packages/data`, `packages/ui`, and `packages/ai`; the other a single flat `src/` tree with `app/`, `capture/`, `search/`, `store/`, `sync/`, `ai/`, `ui/`, `shared/`.
- **Decision:** Adopt the monorepo structure (`apps/*` + `packages/*`) as canonical.
- **Rationale:** Nex's own requirement — one codebase logic shared across Android, Windows, and eventually iOS, plus a dormant backend from v1 — is precisely the scenario monorepos with app shells and shared packages are built for. A flat `src/` tree implicitly assumes a single deployable target, which does not match a product that ships to three client platforms and one backend from the same Core and Data layers.
- **Alternatives Considered:** Flat `src/` layout — simpler for a single-platform MVP, but would require a structural migration the moment the desktop or backend shell is scaffolded, which is known to happen as early as v1.
- **Status:** Accepted.

---

## ADR-013 — ADR format retains explicit "Alternatives Considered"

- **Context:** One documentation draft's decision log used a lighter **Context → Decision → Consequences** format; the other used **Context → Decision → Rationale → Alternatives Considered → Status**.
- **Decision:** Retain the fuller format, including an explicit "Alternatives Considered" section on every entry.
- **Rationale:** For a product whose whole identity rests on saying "no" to plausible-sounding features (see [`07-contributing.md`](./07-contributing.md#what-we-will-not-merge)), recording *why the alternative was rejected* is at least as valuable as recording the decision itself — it pre-empts future contributors re-proposing the same rejected idea without context.
- **Alternatives Considered:** The lighter Context/Decision/Consequences format — rejected only for this document; it remains a reasonable lightweight default for less contentious, purely technical call.
- **Status:** Accepted.

---

## ADR-014 — Metadata header (`Status` / `Owner` / `Last updated`) on every document

- **Context:** Only one of the two drafts consistently opened each document with a `Status / Owner / Last updated` header.
- **Decision:** Adopt this header convention across the entire merged documentation set.
- **Rationale:** Makes document authority and freshness legible at a glance, which matters once ten interlinked documents exist and contributors need to know which are still living and which are frozen references.
- **Alternatives Considered:** No standard header — rejected as it left document authority ambiguous in the source drafts.
- **Status:** Accepted.

---

## ADR-015 — Persian as the first additional language target, kept as a non-functional requirement rather than a v1 feature

- **Context:** The product concept originates from a Persian-speaking user's own note-taking problem, but v1 scope is explicitly English-only to protect MVP focus.
- **Decision:** UI text is externalized from day one (a non-functional requirement, see [`02-product-specification.md`](./02-product-specification.md#non-functional-requirements)), with Persian named explicitly as the first language pack target post-v1 — but no Persian UI ships as part of the v1 MVP feature set itself.
- **Rationale:** Guarantees the door stays open for the product's own origin language without inflating v1 scope or delaying the core capture/find promise.
- **Alternatives Considered:** Ship Persian alongside English in v1 — rejected as scope creep unrelated to the two core MVP goals; localization work competes for the same engineering time as capture/search polish.
- **Status:** Accepted, v1 (infrastructure only); language pack itself unscheduled, tracked post-v1.

---

## ADR-016 — Merging the two advisory document sets

- **Context:** Two independent advisors each produced a full ten-document set (vision, specification, README, architecture, design, development, contributing, roadmap, AI strategy, decisions) covering the same product concept, without knowledge of each other's work. The two sets agreed on product identity, philosophy, and phasing (v1/v2/v3), but diverged on several concrete technical and structural choices.
- **Decision:** Produce a single merged document set (this set) as the canonical one going forward, rather than maintaining both in parallel or picking one wholesale.
- **Rationale:** The agreement between two independently-arrived-at analyses is itself evidence the core philosophy is sound and doesn't need re-litigating. The divergences were narrow enough and each individually well-reasoned enough that a superset — keeping the stronger choice from each side — produces a better document set than either original, at a modest editorial cost.
- **Alternatives Considered:** (1) Keep both sets and let readers reconcile them — rejected, guarantees future confusion about which is authoritative. (2) Pick one set wholesale — rejected, each set had at least one meaningfully better technical decision the other lacked (see ADR-012 through ADR-020).
- **Status:** Accepted. This document set supersedes both source drafts.

---

## ADR-017 — Separate user-facing goals from engineering performance budgets

- **Context:** Both source drafts stated "under 3 seconds" as the target for both capture and search, but one draft additionally specified a stricter, separate 200ms engineering budget for search query latency, while the other used the 3-second figure for both the product promise and (implicitly) the engineering target.
- **Decision:** Treat "under 3 seconds" as the user-facing product promise (validated via usability testing) and define separate, stricter, machine-measurable engineering budgets — e.g., local search query latency under 200ms — enforced in CI.
- **Rationale:** Collapsing the two into one number either sets engineering a target too loose to reliably deliver a promise that *feels* instant (3 seconds of query time would not feel instant), or forces product to justify a CI-gate number to end users in ways that don't map onto their actual experience. Separating them lets engineering hold itself to a bar with margin for real-world device and data variance, while product keeps a single clean, testable promise.
- **Alternatives Considered:** One shared number for both audiences — rejected per above; simpler to write down, but weaker as either a product promise or an engineering contract.
- **Status:** Accepted. See [`02-product-specification.md`](./02-product-specification.md#non-functional-requirements) for the concrete budgets.

---

## ADR-018 — UUIDv7 as the note identifier

- **Context:** One source draft specified a generic UUID (unspecified version) as the note primary key; the other specified UUIDv7 explicitly. Both agreed a client-generated stable identifier was required for offline-first, multi-device sync.
- **Decision:** Use UUIDv7 specifically as every note's `id`, generated client-side at capture time.
- **Rationale:** UUIDv7 embeds a millisecond-precision timestamp in its most significant bits, so IDs sort chronologically. Because the Timeline's dominant query pattern is "newest first," this gives natural index locality for the single most common query in the product — a plain random UUIDv4 would fragment that index and cause worse write amplification at scale, for no offsetting benefit over v7 (which is equally collision-resistant and coordination-free across offline devices).
- **Alternatives Considered:** (1) UUIDv4 — rejected, no ordering benefit and worse index locality. (2) Auto-increment integer — rejected, requires central coordination and cannot be generated offline across independent devices before sync.
- **Status:** Accepted, v1. See [`02-product-specification.md`](./02-product-specification.md#data-model) and [`04-architecture.md`](./04-architecture.md#why-uuidv7).

---

## ADR-019 — Content-addressed media for dedupe

- **Context:** One source draft's data model included a `media_hash` field on media notes and described content-addressed sync for photo/voice files; the other draft's data model omitted this field entirely, relying only on a media URI reference.
- **Decision:** Every media note (voice, photo) carries a content hash of its underlying file, computed at capture time, and this hash is the key used for deduplication during v2 sync.
- **Rationale:** Without a content hash, the same photo or voice memo captured on — or synced to — two devices has no cheap way to be recognized as identical, leading to duplicate storage and duplicate uploads. A hash computed once, locally, at capture time costs nothing on the capture hot path (it can be computed just after the write, off the critical path) and pays for itself the first time two devices reconcile the same file.
- **Alternatives Considered:** Dedupe by filename/size heuristics at sync time — rejected as unreliable and only discoverable after the fact, when both files may have already been uploaded.
- **Status:** Accepted, v1 (field present, unused until v2 sync activates dedupe logic).

---

## ADR-020 — Union-merge for concurrent tag edits, not whole-record last-writer-wins

- **Context:** One source draft specified last-writer-wins (LWW) at the whole-record level for all sync conflicts, including tags. The other draft specified LWW for scalar fields but a union-merge specifically for concurrently-edited tags.
- **Decision:** Adopt field-aware conflict resolution: scalar fields (`content`, `media_uri`) resolve by LWW keyed on `updated_at`/`rev`; the tag set resolves by **union-merge** — the result contains every tag present on either device's version, never a tag silently dropped because it lost a whole-record race.
- **Rationale:** Tags and note bodies are edited independently and asynchronously in ordinary use — e.g., a user tags a note on their phone while separately editing its text on desktop. Whole-record LWW means whichever edit's `updated_at` is later wins *entirely*, silently discarding the other device's tag change. Since tags are additive, low-conflict-risk metadata by nature, a union-merge is both safe (it can never "corrupt" a note, only add tags) and strictly more correct than LWW for this specific field.
- **Alternatives Considered:** Whole-record LWW for everything, including tags — rejected as the simpler option, but one that would produce a genuinely confusing, silent data-loss experience the first time a user tags on one device while editing on another before both sync.
- **Status:** Accepted, planned for v2. See [`04-architecture.md`](./04-architecture.md#conflict-resolution).

---

## Decision-Making Heuristic

When facing a new choice, run it through the product's filter:

1. **Does it protect the capture and find performance promise?** If not, reject or rework.
2. **Does it preserve local-first and offline?** If not, justify heavily.
3. **Does it add a decision at capture time?** If yes, reject.
4. **Is it learnable in under 30 seconds?** If not, simplify.
5. **Does it reinforce "inbox, not system"?** If it pushes toward a second-brain platform, defer.

If a proposal fails this filter, the answer is no — regardless of how interesting the feature is.

> Nex's decisions are easy to predict: **choose whatever keeps capture effortless and find instant.**
