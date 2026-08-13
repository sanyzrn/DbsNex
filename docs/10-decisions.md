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
- **Status:** Accepted, v1. Superseded in part (not retroactively) by [ADR-021](#adr-021--optional-user-chosen-tag-accent-color) — the surface remains monochrome, but tags may carry a small, optional, user-chosen accent dot.

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

## ADR-021 — Optional, user-chosen tag accent color

- **Context:** [ADR-010](#adr-010--monochrome-minimal-visual-design-with-no-categorical-color-coding) established a strictly monochrome UI specifically to prevent color from becoming a system-imposed categorization scheme the user has to maintain. A visual mockup exploring a different direction (colored dots per tag) was reviewed and liked. On discussion, the actual desired behavior turned out to be narrower than "color-code every tag automatically": the person wants to *choose* which tags get color and which color, using it as a personal salience signal (e.g., marking important notes red, unimportant ones neutral) — not as a fixed, system-assigned category identity.
- **Decision:** Tags may optionally carry a single small accent color, rendered only as a small dot (6–8px) beside the tag label — never as a filled chip, colored card, or colored border. The color is chosen by the user when creating or editing a tag, from a small constrained palette, and defaults to neutral/no dot if unset. This assignment happens only during tagging (an Organize Later action), never during capture.
- **Rationale:** The concern behind ADR-010 was color becoming an *unwanted, system-imposed* decision at the point of interaction. A user-chosen, optional, capture-time-free accent dot doesn't reintroduce that problem — it adds a recognition aid the user opts into, on their own terms, for their own meaning (e.g., personal priority), fully consistent with "Organize Later" and with zero impact on the capture flow's zero-decision guarantee (ADR-001). Keeping the dot small and keeping everything else about the tag/card neutral preserves the calm, monochrome-at-a-glance feel the original rule was protecting.
- **Alternatives Considered:** (1) Fully automatic, system-assigned color per tag name/category — rejected, because it removes exactly the flexibility the person wanted (using color for cross-cutting priority, not fixed category identity) and reintroduces a system-imposed scheme. (2) Full-color chips/card backgrounds — rejected, reintroduces the visual noise and "categorization system to maintain" problem ADR-010 was written to avoid. (3) Leaving ADR-010 as an absolute, unmodified rule — rejected once it was clear the underlying concern (imposed, mandatory, capture-time color decisions) didn't actually apply to what was being asked for.
- **Status:** Accepted. See [`05-design.md`](./05-design.md#tag-accent-color) for the visual specification and [`02-product-specification.md`](./02-product-specification.md#data-model) for the schema change.

---

## ADR-022 — Swipe actions are configurable per edge, from an open set

- **Context:** Originally this ADR fixed the action set at exactly two — Delete and Add Tag — and allowed only swapping which edge carried which. The reasoning was that an open action framework invites a settings maze. In use, that produced a control that was a single "swap" button: it did not say what the choices were, and it could not express "I want one gesture, not two."
- **Decision:** Each edge is bound **independently** to an action from an open set, which currently holds `Delete`, `Add Tag`, and `None`. The two edges are not coupled: both may carry the same action, or neither may carry one.
- **Rationale:** The original constraint was defending a real thing — a preference surface that grows without limit — but it was defending it in the wrong place. The discipline belongs in *which actions exist*, not in whether the user can choose between the ones that do. `None` matters on its own: a swipe the user did not ask for is a swipe they will trigger by accident.
- **Consequences:** Adding an action means one enum entry, one case in the resolver, and one label. The picker, the storage and the gesture need no change. An edge bound to `None` does not move at all, so the gesture is genuinely absent rather than present-but-inert.
- **Supersedes:** the fixed two-action set and the swap-only control described in the original ADR-022. The swap button has since been removed outright rather than kept as a shortcut: with independent edges it could only mean "exchange these two", which is one of the states the per-edge pickers already reach, and leaving it there kept implying the edges were a pair.
- **Status:** Accepted, revised.

---

## ADR-023 — Comfort Mode as an independent axis from Light/Dark theme

- **Context:** A real usage pattern for Nex is capturing an idea in a fully dark room late at night — exactly the scenario the product exists to serve. Feedback surfaced that the existing Dark theme, used in an actually dark room, was itself uncomfortable: a pure-black background with pure-white text produces a high-contrast halation/glare effect that can be more fatiguing in total darkness than a normally-lit screen, and doesn't address blue-light exposure at all.
- **Decision:** Add **Comfort Mode**, a single toggle in Settings, independent of and layered on top of the existing Light/Dark theme choice (not a third theme). When on, in either theme, it lowers the contrast between background and text (pulling both away from pure black/white toward warm off-black/off-white) and shifts the palette's color temperature warmer. Default is off in both themes.
- **Rationale:** Treating this as a second, orthogonal axis (Theme × Comfort) rather than a new "Dark Comfort" theme keeps the mental model simple — two independent yes/no choices instead of an enumerated list of theme variants — and correctly reflects that the underlying problem (contrast/glare, blue light) is independent of which theme is active; a person reading in bright daylight can equally have a preference for lower contrast. Keeping it manual (not auto-scheduled by time) in v1.x avoids adding geolocation/scheduling complexity to a feature whose entire justification is reducing friction and strain, not adding a new subsystem.
- **Alternatives Considered:** (1) A third theme option ("Night Comfort") alongside Light/Dark — rejected, since it conflates two independent variables (which base palette vs. how much contrast/warmth) into one enumerated choice, and would silently prevent using low-contrast/warm colors in Light theme, which is equally useful in bright daylight. (2) Auto-enable Comfort Mode automatically whenever Dark theme is active — rejected, since the two problems (theme preference, contrast/glare preference) don't always correlate for a given person. (3) Automatic scheduling by sunset/sunrise from day one — deferred, not rejected outright; reasonable future v2 addition once the manual toggle has proven the underlying tokens are right.
- **Status:** Accepted, planned for v1.x (ships in the same Settings sheet introduced for [ADR-022](#adr-022--swipe-actions-are-configurable-per-edge-from-an-open-set)'s swipe-action mapping). See [`05-design.md`](./05-design.md#comfort-mode) for the token specification.

---

## ADR-024 — Flutter as the single cross-platform client framework

- **Context:** The original tech-stack recommendation split the client into two separate stacks sharing a JS/TypeScript "core" package: React Native for Android (and future iOS), and Tauri or Electron for Windows desktop. Revisiting this choice directly, given the product's actual requirements — a solo/small team building for Android first, Windows second, iOS later, all sync-connected, offline-first, with custom gestures (swipe actions, [ADR-022](#adr-022--swipe-actions-are-configurable-per-edge-from-an-open-set)), theming (Light/Dark/Comfort, [ADR-023](#adr-023--comfort-mode-as-an-independent-axis-from-lightdark-theme)), and mixed LTR/RTL text ([`05-design.md`](./05-design.md#tag-accent-color)) — surfaced a simpler option.
- **Decision:** Adopt **Flutter/Dart** as the single client framework for Android, Windows, and future iOS, replacing the React Native + Electron/Tauri split. `apps/client` is one Flutter app target; `packages/core` and `packages/data` are plain Dart with no Flutter dependency, so domain logic stays unit-testable without a UI runtime. The backend (Node.js + PostgreSQL) is unaffected — this decision is client-only.
- **Rationale:**
  - **One codebase, one language, for all three client platforms** — not two stacks (mobile JS runtime + desktop Chromium wrapper) sharing a logic package. For a small team, this halves the surface area that has to be built, tested, and kept in sync.
  - **Compiled, not webview-based.** Electron/Tauri desktop builds either bundle a full Chromium (Electron — directly in tension with the footprint NFR in [`02-product-specification.md`](./02-product-specification.md#non-functional-requirements)) or a system webview (Tauri — lighter, but still a browser engine mediating custom gestures and animation). Flutter compiles to native ARM/x64 code with its own rendering engine, which matters directly for the cold-start and capture-latency budgets in [`04-architecture.md`](./04-architecture.md#performance-principles).
  - **First-class custom gesture and animation control.** Swipe-to-reveal actions and sheet transitions are core, frequently-touched interactions, not chrome — Flutter's widget/animation system is built for exactly this, without fighting a browser's event and paint model.
  - **Built-in bidirectional text support.** Nex's UI is English/LTR by design, but must render user-authored Persian (and other RTL) content correctly inline ([`05-design.md`](./05-design.md)) — Flutter's text layout handles mixed-direction text natively, without extra libraries.
- **Alternatives Considered:** (1) Keep React Native + Electron/Tauri — rejected per the rationale above; it was the original default recommendation, not a considered decision, and doesn't hold up against Nex's actual constraints once examined directly. (2) Fully native (Kotlin + Swift + C#/WinUI) — rejected as three codebases to build and maintain, disproportionate for a small team and in direct tension with "small, legible system" ([`04-architecture.md`](./04-architecture.md#guiding-constraints)). (3) Kotlin Multiplatform / Compose Multiplatform — a reasonable alternative with a similar single-codebase pitch, but rejected for now on relative tooling/desktop maturity compared to Flutter; worth revisiting if Compose Multiplatform's desktop and iOS targets mature further.
- **Status:** Accepted. Supersedes the client portion of the original stack recommendation; the backend recommendation is unchanged.

---

## ADR-025 — Data export ships in v1, not after v3

- **Context:** [`01-product-vision.md`](./01-product-vision.md#core-values) states "data belongs to the user" as a core value, but export was originally deferred until "evaluated post-v3" (see the now-superseded [Future Features](./02-product-specification.md#future-features) list). Two independent external reviews of the documentation set flagged this as the single largest concrete contradiction in the project: a local-first app with no sync until v2 and no export at all leaves a v1 user's data effectively locked to one device for roughly two major versions, with no way out on their own terms.
- **Decision:** v1 ships a manual **Settings → Export** action producing a JSON dump (full fidelity, machine-readable) and a Markdown export (one file per note, human-readable) plus the referenced media files, bundled as a single archive the user saves wherever they choose. A lossless round-trip (export, then manually verify the data against the original) is part of the v1.0 release exit criteria.
- **Rationale:** This is the minimum viable trust posture for a tool whose entire premise is "capture first, trust that it's safe." It does not compromise Nex's identity as the inbox rather than the destination — if anything, a working export is the concrete mechanism behind the vision's own claim that Nex "feeds" other tools rather than trapping data (see [`01-product-vision.md`](./01-product-vision.md#vision)), a claim that had no actual mechanism behind it before this decision.
- **Alternatives Considered:** (1) Leave export deferred to post-v3 as originally planned — rejected; the cost of building a one-directional export is low and the trust cost of not having one for ~two major versions is high. (2) JSON-only export — rejected; a Markdown export honors the "front door to other tools" positioning more directly, since Markdown is what most note tools (Obsidian, plain filesystems) can actually ingest.
- **Revision — export is a round trip, not a write.** An export that nothing can read back is a file, not a way out: it protects the *format* of the user's data without protecting their ability to use it. v1 therefore also ships **import**, reading an archive back into a library with its media. Import is additive — a note already present is left as it is — so it can never roll a newer note back to an older archive's version, and re-importing the same file is a no-op. Two consequences follow. A user restoring onto a new device gets their library back without a server, which is the first real answer this project has had to a lost phone. And the round-trip check in FR-6.3 stops being a manual inspection and becomes an ordinary test: export, import into an empty library, compare.
- **Revision — the archive goes to the share sheet.** Writing it to an app-private temp path satisfied "an archive the user saves wherever they choose" only on desktop; on Android that directory is not reachable by any file manager, so the feature was, in practice, unavailable on the primary platform.
- **Status:** Accepted, revised. Supersedes the "Export evaluated only after v3" line in [`02-product-specification.md`](./02-product-specification.md#future-features) and [`08-roadmap.md`](./08-roadmap.md#explicitly-deferred--not-currently-planned).

---

## ADR-026 — Automatic local backup & restore ships in v1

- **Context:** Nex's storage is local-only until v2 sync. Alongside ADR-025 (export), the same external reviews pointed out that "a captured note must never be lost" ([`01-product-vision.md`](./01-product-vision.md#non-negotiable-principles)) currently has no protective mechanism behind it at all in v1 — a lost, stolen, or factory-reset device, or a corrupted local database, destroys 100% of a user's captures with no recovery path.
- **Decision:** v1 ships automatic, rotating local backups of the SQLite database (a small fixed number of recent snapshots, stored on-device) and a one-tap restore path. Surviving a simulated database-corruption scenario in testing is part of the v1.0 release exit criteria.
- **Rationale:** Export (ADR-025) protects against wanting to leave; backup protects against losing data by accident, which is a distinct and arguably more common failure mode (app crash mid-write, storage corruption, accidental deletion) than the deliberate device-loss scenario export doesn't fully cover either. Both are cheap relative to the cost of the promise they're backing.
- **Alternatives Considered:** Rely on the user's own OS-level device backup (e.g., Android's system backup) as the only safety net — rejected as a silent, unverified dependency Nex doesn't control and can't test against; an app-level backup guarantees the behavior regardless of OS backup settings the user may have disabled.
- **Status:** Accepted, v1.

---

## ADR-027 — OS-level capture surfaces (home-screen widget, share-intent) added to v1.x scope

- **Context:** Every functional requirement in [`02-product-specification.md`](./02-product-specification.md) assumes the user opens the Nex app before capturing. Both external reviews independently identified this as an unexamined gap of real consequence: for a product whose entire premise is minimizing the time between a thought and its capture, requiring an app-icon tap in every scenario concedes exactly the argument Nex is trying to win, at the OS-integration layer rather than inside its own app shell. This is a materially higher-leverage improvement to the "capture in under 3 seconds" promise than the swipe-action configurability or Comfort Mode already scheduled for v1.x.
- **Decision:** Add, to v1.x scope, ranked **above** swipe-action configuration and Comfort Mode: (a) a home-screen widget (Android first) that opens directly into text capture, and (b) an Android share-intent target, so text, a link, or a photo can be sent into Nex from any other app without opening Nex first. A desktop global-hotkey/system-tray quick-capture entry point is noted as a reasonable future addition once the Windows client exists, but is not required for this ADR's scope.
- **Rationale:** These entry points reduce the single largest remaining source of capture friction — opening the app at all — for the two platforms already in v1/v1.x scope, at a cost that's small relative to their leverage on the product's core promise.
- **Alternatives Considered:** Leave OS-level capture to a later version once the in-app experience is fully polished — rejected; the in-app polish items already scheduled (Comfort Mode, swipe config) are lower-leverage than this by the reviews' own reasoning and by direct comparison against the product's stated success metrics.
- **Status:** Accepted, v1.x. Re-ranks [`08-roadmap.md`](./08-roadmap.md#v1x--stability--polish) — this ships before, or at minimum alongside, ADR-022 and ADR-023, not after.

---

## ADR-028 — Explicit FTS5 tokenization strategy for multilingual (Persian-first) search

- **Context:** [`02-product-specification.md`](./02-product-specification.md) commits to full-text search via SQLite FTS5, and [ADR-015](#adr-015--persian-as-the-first-additional-language-target-kept-as-a-non-functional-requirement-rather-than-a-v1-feature) names Persian as the first planned additional language — but no document specifies which FTS5 tokenizer handles this correctly. Getting this wrong is a silent failure mode: search simply returns nothing for affected content, and to the user, Nex just looks broken, with no error to report.
- **Decision:** Use FTS5's `unicode61` tokenizer with explicit `remove_diacritics` and `tokenchars`/`separators` tuned for Persian script (Persian is space-delimited, unlike CJK, so word-based tokenization is viable, but Persian-specific characters like ZWNJ (zero-width non-joiner) and diacritics need explicit handling to avoid false-negative matches). A dedicated search-correctness test suite covering Persian sample content is added to the Phase 1 test plan, alongside the existing English-only test cases.
- **Rationale:** This is a cheap, specific fix once named, and expensive to debug later as a vague "search feels unreliable" bug report once real Persian content exists in the wild.
- **Alternatives Considered:** Bundle an ICU tokenizer for broader script coverage (CJK, etc.) — deferred, not rejected; not needed for Persian specifically (which is space-delimited), and adds a build dependency not currently justified until a CJK language is actually on the roadmap.
- **Status:** Accepted, v1.

---

## ADR-029 — Tool-calling contract and local memory schema live in `packages/core`, not `packages/ai`

- **Context:** [`09-ai.md`](./09-ai.md#offline-local-model-track) phases in a tool-calling contract (letting a local chat model invoke Nex's own capabilities) and a local memory/profile schema for the paid "personal assistant" tier. `packages/ai` is deletable by design — a CI job (`ai-deletion-proof`) deletes it wholesale and rebuilds the graph, proving AI is truly optional (see [Architectural Boundary](./09-ai.md#architectural-boundary)). Putting the tool-calling contract or the memory schema inside `packages/ai` would mean a user's saved memory records, and the very ability to define what a "tool" is, vanish along with the AI package — even though both are meaningful, inspectable domain data/contracts with no dependency on any model actually running.
- **Decision:** `ToolDefinition`/`ToolCall`/`ToolResult`/`NexToolRegistry`/`ToolExecutor`, the `AiEntitlement` gating hook, and the `MemoryRecord` model plus `MemoryRepository` port all live in `packages/core` (with the SQLite implementation of the repository in `packages/data`, alongside `SqliteNoteRepository`). Only the code that actually drives a model through the contract (the agent/chat loop) belongs in `packages/ai` or, per the existing `CloudAIAdapter` precedent, `apps/client`.
- **Rationale:** This is the same precedent `AIAdapter` and `AiCapabilities` already set by living in `packages/core/lib/ai/` rather than `packages/ai` — the *contract* and the *data* survive AI-package deletion; only a concrete model-backed implementation doesn't. A user should be able to view, edit, or delete their memory records, and the app should still know what "create a note" means as a callable action, with `packages/ai` absent — exactly as notes and tags already work today with AI off.
- **Alternatives Considered:** Put the contract and schema inside `packages/ai` alongside the runtime that will eventually drive them — rejected, breaks the deletability guarantee the whole architecture is built around and makes memory records an AI-package concern instead of a Core domain concept.
- **Status:** Accepted. Scaffolding lands ahead of the chat loop that will use it, per [`09-ai.md`](./09-ai.md#phase-2--personal-assistant-foundations-paid-built-modular-now).

---

## ADR-030 — Free/paid boundary for the personal-assistant tier, gated by a structural entitlement hook

- **Context:** The offline local-AI track's product vision splits into two tiers: general chat (free, for everyone) and a "personal assistant" layer — persistent memory, behavioral learning, task execution, deep tool-calling into Nex's own capabilities, and cross-AI context import — intended as paid/subscription. No entitlement, plan, or tier concept exists anywhere in the codebase today (client or backend), and a full payment/subscription system is explicitly not being built yet — only its structural hook needs to exist so the paid features can be gated correctly from the moment they're implemented, rather than retrofitted later.
- **Decision:** Add `AiEntitlement` (`free` / `personalAssistant`) and an `AiEntitlementProvider` interface to `packages/core/lib/ai/entitlement.dart`, defaulting everywhere to a `StaticEntitlementProvider` returning `free`. Every tool call in the [tool-calling contract](#adr-029--tool-calling-contract-and-local-memory-schema-live-in-packagescore-not-packagesai) declares `requiresEntitlement`, and `GatedToolExecutor` checks it before dispatch. No store/billing integration is wired up — `AiEntitlementProvider` is the seam a real subscription check replaces later without touching the tool-calling code that depends on it.
- **Rationale:** Building the gate now, even trivially, means every tool added during Phase 2 is correctly gated from its first commit rather than needing an audit later to find ungated paid features. Defaulting to `free` follows the same safe-default pattern already established by `NullAIAdapter` and `AiCapabilities.allOff` — nothing paid is ever accidentally on.
- **Alternatives Considered:** Defer any gating concept until real payment integration exists — rejected, because it risks paid features shipping ungated during Phase 2 and needing a retrofit; (2) Reuse `AiCapabilities` for this — rejected, `AiCapabilities` is an orthogonal on/off toggle per already-free capability, not a paid/free boundary, and conflating them would make a user's personal preference toggle double as a billing gate.
- **Status:** Accepted. See [`09-ai.md`](./09-ai.md#free-vs-paid-boundary) for the full free/paid feature table.

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
