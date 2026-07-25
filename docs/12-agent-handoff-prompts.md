# Nex — Agent Handoff Prompts

> Companion to [`11-build-prompt.md`](./11-build-prompt.md). That document defines *what* each phase must do; this document is the literal, paste-ready prompt text to hand to a GitHub-connected coding agent, one phase at a time.

**Status:** Living document · **Owner:** Engineering · **Last updated:** 2026

---

## How to use this

1. Paste **one prompt block below at a time** — do not paste the whole file at once.
2. Wait for the agent's phase-completion report after each one. Read it. Only paste the next block once you're satisfied the report shows real, executed evidence (command output, test results) — not just a claim that something "should work."
3. If the agent's report is vague ("Phase 0 is done ✅" with no detail), push back and ask it to show the actual command output for each Definition-of-Done item before you continue.
4. If at any point the agent proposes something not in `docs/`, stop and ask it to point to the exact doc section justifying it — per the rules embedded in every prompt below.

---

## Prompt 1 — Orientation + Phase 0 verification & correction

```
This repo already contains a Phase 0 scaffold (monorepo structure, empty Flutter
client, backend skeleton, CI config) written by an AI assistant that did NOT have
a real Flutter/Dart toolchain or CI runner available to it — so nothing in Phase 0
has actually been executed and confirmed yet, only authored. You do have real tool
access. Your first job is to verify it for real, not re-trust it.

Read, in this order, before doing anything else:
docs/01-product-vision.md, docs/02-product-specification.md, docs/03-readme.md,
docs/04-architecture.md, docs/05-design.md, docs/06-development.md,
docs/07-contributing.md, docs/08-roadmap.md, docs/09-ai.md, docs/10-decisions.md,
docs/11-build-prompt.md

Then, for the existing Phase 0 scaffold:

1. Known issue to check first: apps/backend/tsconfig.json may be missing
   "allowImportingTsExtensions": true. apps/backend/src/index.ts imports sibling
   modules using explicit .ts extensions (an ESM + node --experimental-strip-types
   pattern), which fails `tsc --noEmit` with error TS5097 unless that compiler
   option is set. Check for it; if missing, add it, then confirm
   `npm run typecheck` passes cleanly in apps/backend.

2. Actually run, and report real output for, every one of these:
   - apps/backend: npm install, npm run typecheck, npm run lint
   - packages/core, packages/data, packages/ai: dart pub get, dart analyze
     --fatal-infos, dart test — confirm these run with NO Flutter SDK involved,
     proving zero Flutter dependency structurally, not just by pubspec inspection
   - packages/ui, apps/client: flutter pub get, flutter analyze --fatal-infos,
     flutter test
   - apps/client: flutter build apk --debug (Android) and
     flutter build windows --debug (Windows) — or, if you can drive an actual
     emulator/device, flutter run on both and confirm a genuinely empty screen
     (no Timeline, no capture button behavior, no product UI — Phase 0 is a
     blank canvas per 11-build-prompt.md)
   - CI: confirm .github/workflows/ci.yml actually runs green on this state

3. Go through every item in 11-build-prompt.md's Phase 0 "Definition of Done" and
   "Stop-and-verify checklist" and report pass/fail against real executed evidence
   for each one individually. Fix anything that fails. Do not summarize with a
   single "all good" — list each checklist item with its actual result.

Do not start Phase 1 until you can show every Phase 0 checklist item genuinely
passing, with evidence, in this message or your next one.
```

---

## Prompt 2 — Phase 1: v1 MVP

*(paste only once Prompt 1's report shows every Phase 0 item genuinely passing)*

```
Phase 0 is verified. Proceed to Phase 1 exactly as specified in
docs/11-build-prompt.md (sections 1.1 through 1.10): data layer & schema, core
domain package, Timeline, Quick Capture, Tags, Search (including the Persian
FTS5 tokenizer requirement — do not skip the Persian search-correctness test),
visual design pass, offline verification, Export, and Backup & Restore.

Rules:
- Follow every FR and ADR referenced in each subsection exactly. If a task seems
  to need a decision the docs don't cover (a field, a confirmation step, a
  default), stop and ask me — do not invent something plausible-sounding.
- Re-read ADR-001 and ADR-002 before touching Quick Capture specifically — zero
  mandatory fields, no Save button, anywhere.
- After each subsection (1.1–1.10), run and report its stated acceptance check
  for real — actual test output, not a description of what the test would check.
- At the end, go through the "Stop-and-verify checklist before Phase 1.x" line
  by line with real evidence for each box.

Stop after that report and wait for my go-ahead before starting Phase 1.x.
```

---

## Prompt 3 — Phase 1.x: OS capture surfaces, swipe actions, Comfort Mode

```
Proceed to Phase 1.x exactly as specified in docs/11-build-prompt.md, in the
given order — this order is deliberate, not arbitrary:

1.x.1 OS-level capture surfaces (home-screen widget + Android share-intent) —
      build this first, it has the most leverage on the core capture-speed
      promise of anything in this phase.
1.x.2 Stability (performance, accessibility, CI budget hardening, localization
      groundwork).
1.x.3 Swipe actions — exactly two actions (Delete, Add Tag), direction mapping
      configurable in a new minimal Settings sheet. Do NOT build a general or
      extensible action framework, and do NOT add Pin/Archive as a third
      action — see ADR-022 for why that's explicitly ruled out.
1.x.4 Comfort Mode — an independent toggle from Light/Dark theme, not a third
      theme; use the exact token deltas in docs/05-design.md#comfort-mode.

Report the Phase 1.x Definition of Done with real evidence for each item. Stop
and wait for my go-ahead before Phase 2.
```

---

## Prompt 4 — Phase 2: Sync

```
Proceed to Phase 2 exactly as specified in docs/11-build-prompt.md and the Sync
section of docs/04-architecture.md.

This is the highest-scrutiny phase in the whole project. The conflict
resolution must be field-aware — last-writer-wins for scalar fields
(content, media_uri), UNION-MERGE for tags — never a simpler whole-record
last-writer-wins. Re-read ADR-020 before writing the merge logic. If you find
yourself tempted to simplify this to "just apply LWW to the whole note" because
it's easier to get tests passing, stop — that is the exact wrong shortcut this
phase exists to prevent, and it will silently lose tags in production.

The test matrix in 11-build-prompt.md §2.3 (six scenarios: concurrent content
edit, concurrent tag-add + content-edit, concurrent tag-add + tag-remove,
delete-vs-edit race, duplicate media dedupe, long-offline-then-reconnect) is
mandatory. Run every row for real as an integration test against the actual
sync client and backend — not mocked away — before marking this phase done.

Report the Phase 2 Definition of Done with real evidence per test-matrix row.
Stop and wait for my go-ahead before Phase 3.
```

---

## Prompt 5 — Phase 3: Intelligence Layer

```
Proceed to Phase 3 exactly as specified in docs/11-build-prompt.md and
docs/09-ai.md.

Implement the AIAdapter interface in packages/ai per docs/06-development.md's
AI Adapter Interface section, then transcription, then OCR, then (each
independently toggleable) tag suggestions, semantic search, summarization,
related notes.

The single required proof for this phase: packages/ai must be deletable from
the build entirely, with packages/core, packages/data, and apps/client still
compiling and the full v1 MVP still functional. Actually delete the package
directory in a scratch branch, run the full build and test suite, and report
the result — don't just assert the architecture supports it.

Report the Phase 3 Definition of Done, including the v3.0 exit criteria from
docs/02-product-specification.md, with real evidence.
```

---

## If the agent seems to drift (use any time, any phase)

```
Before continuing: re-check your last change against docs/10-decisions.md's
Decision-Making Heuristic and docs/07-contributing.md's "What We Will Not
Merge" list. Specifically confirm you have not added: a mandatory field, dialog,
or decision at capture time; a folder/notebook/hierarchy concept; pinning or
manual reordering in the Timeline; an open-ended or general-purpose
settings/action framework; or any AI call that blocks or delays capture. If any
of these crept in, remove it and explain what you replaced it with.
```
