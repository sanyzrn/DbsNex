# Nex — Product Vision

> **Capture in Seconds. Find in Seconds.**

**Status:** Authoritative · **Owner:** Product & Design · **Last updated:** 2026
**Document set:** This is the merged, canonical version of the product vision, consolidating two independent advisory passes over the original concept. See [`10-decisions.md`](./10-decisions.md#adr-016--merging-the-two-advisory-document-sets) for how conflicts between the two sources were resolved.

---

## Executive Summary

Nex is a personal capture tool built around one conviction: **the friction of capturing an idea is usually greater than the friction of forgetting it.**

Most note-taking apps force you to open the app, create a note, give it a title, pick a folder, and press **Save**. By the time those steps are done, the idea is often gone. Nex removes that friction entirely — it is the **inbox for the human mind**, not another knowledge base, project manager, or second-brain platform. It is the doorway to a second brain, never the second brain itself.

---

## Why Nex Exists

To record an idea today you typically open an app, create a note, type a title, choose a folder, and press Save. That handful of seconds of friction causes many ideas to never be recorded at all. The failure mode is predictable:

1. A thought occurs.
2. The user hesitates — "Where should this go?"
3. The app asks too many questions before it lets them type.
4. The thought is gone, or captured somewhere worse (a chat message to themselves, a sticky note, nothing at all).

Nex interrupts this at step 2. **There is no "where." There is only "now."**

---

## Mission

> **Capture First. Organize Later. Find Instantly.**

---

## Vision

A world where no idea is lost to friction. Nex becomes the fastest, lightest, most obvious place to capture anything — on any device, online or offline — so the gap between *having* an idea and *keeping* it disappears. In five years, "just Nex it" should be the default reflex for capturing a thought, the way "just Google it" became the default reflex for a question.

Nex does not compete with Notion, Obsidian, or Evernote — it feeds them. What happens to a capture after it lands in Nex is up to the user, and eventually up to whatever tools consume Nex's data.

---

## Product Identity

**Nex is:**
- A personal capture tool
- An inbox for the human mind
- Local-first, offline-first
- Minimal, fast
- AI-optional

**Nex is NOT:**
- A knowledge management system
- A project management tool
- A "second brain" platform
- Another Notion, Obsidian, or Evernote

Every roadmap decision, feature request, and design review is checked against this identity. If a proposed feature makes Nex look more like a knowledge base or a project tool, it does not belong in Nex — regardless of how useful it might be in isolation.

---

## Target Users

| Persona | Motivation | How they use Nex |
|---|---|---|
| **The Idea Hoarder** | Constant bursts of ideas throughout the day | Capture before the idea disappears |
| **The Mobile-First / Voice-First Thinker** | Best ideas arrive on the move, or while hands are busy | One-tap audio and photo capture |
| **The Cross-Device Worker** | Lives across phone, laptop, desktop | Timeline today; seamless sync from v2 |
| **The Visual Note-Taker** | Captures whiteboards, receipts, screens | One-tap photo capture |
| **The Overwhelmed Organizer** | Tried Notion/Obsidian, abandoned them — setup felt like a chore | A tool that asks nothing up front |

Nex is single-player by design in its first versions. Multi-user, sharing, and collaboration are explicitly out of scope.

---

## Core Values

1. **Speed over structure/features.** A fast, unorganized capture beats a slow, perfectly organized one. If a feature slows down capture, it does not belong in Nex.
2. **Zero decisions at capture time.** Every prompt, dialog, or required field is a tax on memory.
3. **Trust through reliability and simplicity.** Users must never wonder "did that save?" — it always does, silently, and a captured note must never be lost.
4. **Honesty in the UI.** Show limitations plainly (e.g., unindexed audio in v1) rather than hiding them.
5. **Restraint.** Say no to feature creep; fewer concepts, learned in seconds.
6. **Data belongs to the user.** Local-first by default; sync and cloud features are additive, never mandatory.

---

## Design Philosophy

### Capture First
Capturing must be faster than thinking. At the moment of capture, the user makes **zero** decisions: no folder, no title, no template, no Save button. Just capture.

### Organize Later
Everything lands in a single, unified timeline first. Tagging and categorization are optional actions the user can take *after* the fact, never a precondition for saving.

### Find Instantly
A capture tool nobody can search is worthless. Search is the second pillar of the product, on equal footing with capture itself.

---

## UX Philosophy

- The interface should feel like a blank page waiting for you, not a form to fill out.
- Every screen is understandable in under 30 seconds, with no onboarding tour required.
- Motion is brief and purposeful — confirming an action, never decorating it.
- The product should feel "light," like a notepad in your pocket — never enterprise software.
- Silence is a feature: no notifications, no gamification, no engagement loops. Nex is a tool, not a habit-forming app.

---

## Non-Negotiable Principles

These constraints apply to every version of Nex, forever:

- Capture feels instantaneous to the user (**user-facing target: under 3 seconds**, app-open to stored note).
- Finding information feels instantaneous to the user (**user-facing target: under 3 seconds**).
- Zero friction and zero mandatory fields at capture time — no title, no folder, no Save button.
- The Timeline is the default home screen; organization always happens later.
- AI never interrupts or delays capture.
- The architecture is local-first; cloud sync is optional, never required for core functionality.
- Every feature is learnable in under 30 seconds.

> **A note on targets:** "under 3 seconds" is the user-facing promise and the north star for product decisions. It is deliberately distinct from the internal engineering performance budgets (e.g., search query latency) defined in [`02-product-specification.md`](./02-product-specification.md#non-functional-requirements) and [`04-architecture.md`](./04-architecture.md#performance-principles). Keeping the two separate lets engineering hold itself to a stricter, machine-measurable bar than the promise itself requires — see [ADR-017](./10-decisions.md#adr-017--separate-user-facing-goals-from-engineering-performance-budgets).

---

## Success Metrics

| Metric | Target | Why It Matters |
|---|---|---|
| Time-to-first-capture (new user) | < 10 s from install | Validates zero-friction onboarding |
| Median capture duration (user-facing) | < 3 s | Core product promise |
| Median search-to-result duration (user-facing) | < 3 s | Core product promise |
| % of captures with no tag/title added | Expected high (60–80%) | Confirms "capture first" is actually happening |
| Search success rate | > 90% of searches result in a click/open | Confirms retrieval is trustworthy |
| Crash-free capture sessions | > 99.9% | A lost capture is a broken promise |
| Sync convergence (v2+) | > 99.9% of changes converge across devices | Confirms cross-device coherence |

Metrics Nex explicitly does **not** optimize for: daily session count, time spent in app, streaks, or notification open rate — these directly contradict the mission.

---

## Product Boundaries

Nex deliberately stays out of:
- Rich document editing (no nested pages, no databases, no complex formatting)
- Project/task management (no deadlines, no assignees, no boards)
- Team collaboration
- Being a destination for long-term structured knowledge work

Nex is the **front door**, not the house.

---

## AI Philosophy

AI is a layer above capture, never a gate in front of it. Full detail in [`09-ai.md`](./09-ai.md).

- Entirely optional; the product is fully usable with zero AI.
- Never blocks, delays, or requires confirmation during capture.
- Assists with tagging, transcription, OCR, semantic search, summarization, and related notes — always after the fact, in the background.
- Suggestions are always dismissible and never silently alter original content.

---

## Long-Term Vision

1. **v1:** Establish Nex as the fastest capture tool available on mobile and desktop, with a rock-solid timeline and search experience.
2. **v2:** Make capture ubiquitous across devices through real, reliable sync — without ever compromising local-first guarantees or offline reliability.
3. **v3+:** Layer intelligence on top of the capture graph — transcription, OCR, semantic search, summarization — so everything ever captured becomes effortlessly retrievable, regardless of its original format.

> **Capture First. Organize Later. Find Instantly.**
