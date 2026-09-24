# Handoff

Written for the next agent session — specifically one running in Claude Code
desktop, with a real machine underneath it. It assumes you have never seen this
repository.

Read `README.md` for what the product is and `docs/` for how it is built. This
file holds what neither of those can: how the work has actually been going, what
the pipeline will and will not catch for you, and the specific traps that have
cost real time. Where this file and `docs/` disagree, `docs/` is the spec and
this is the field report.

Current state: **v1.21.0 is released; v1.21.1 is prepared** on the working
branch — the fixes for an independent audit's findings, recorded in §8. The
audit itself is `NEX_RELEASE_AUDIT.md` in the repository root.

---

## 1. The one thing that changes for you

Every session up to this point ran in a cloud container **with no Flutter SDK,
no Dart SDK and no Android SDK**. Nothing could be compiled, analysed or tested
locally. The only compiler the work ever met was GitHub Actions, and CI runs on
`pull_request` only — so the loop was: write, read the diff back adversarially,
push, open a PR, wait five to seven minutes, read the log.

You almost certainly do not have that constraint. Install the pinned SDK and
run the checks locally:

```bash
cat .fvmrc          # {"flutter": "3.35.5"} — use exactly this
make bootstrap      # pub get / npm ci for all seven packages
make check          # analyze + test for every package
```

`make check` runs analyze and tests for every package: `check-dart` (core,
data — pure Dart, no Flutter), `check-ai`, `check-ui`, `check-client`,
`check-backend`, `check-worker`. **It is not the whole pipeline**, and an
earlier version of this file said it was. CI additionally builds the Android
debug APK (`flutter build apk --debug --flavor standard` in `apps/client`),
runs the four boundary proofs and the `packages/ai` deletion proof, the
TypeScript/Dart merge-conformance job, and the Phase 2 sync matrix against a
live PostgreSQL. A green `make check` means the code analyses and its tests
pass; it does not mean CI will be green. An independent audit caught the
overclaim.

**On Windows:** the suite was red on a clean Windows checkout until v1.21.1, for
reasons unrelated to the app — CRLF line endings, a test fake that built paths
from `Uri.path`, and a worker that answered `close` before releasing the
database file, which Windows will not let anyone delete. All three are fixed.
If you cloned before `.gitattributes` existed, your working files may still
be CRLF. With nothing uncommitted (commit or stash first — the second command
discards local changes), re-checkout once: `git rm --cached -r -q .` then
`git reset --hard`.

**Run it before every push.** Most of the incidents in §7 would have been caught
in ten seconds by a local analyzer.

---

## 2. Layout

```
apps/client            the Flutter app (Android; a Windows target still builds
                       locally but its CI and release jobs are paused)
apps/backend           NestJS + PostgreSQL sync server (Phase 2)
apps/feedback-worker   small TS worker, deployed separately
packages/core          pure Dart: models, text rules, merge semantics. No Flutter.
packages/data          pure Dart: SQLite storage, FTS. No Flutter.
packages/ui            the design system (nex_ui): tokens, widgets, theme
packages/ai            optional AI package, kept deletable — see below
spec/                  merge-conformance.json: the cross-language sync contract
docs/                  01 vision … 10 decisions (ADRs), 13 sponsor card
tools/                 checkers CI runs
```

Boundaries CI actively enforces, not just documents:

- `packages/core` must not import, depend on, or re-export `packages/data`.
- `packages/ui` must have no storage dependency.
- `packages/ai` must be deletable: a CI job **deletes it** along with its two
  integration points in `apps/client` and proves the rest still resolves and
  analyses. If you add an import of `nex_ai` anywhere but `packages/ai` and the
  ai-flavor entry point, that job fails.
- Android widget layouts may only name `@RemoteView` classes.
- The TypeScript and Dart merge implementations must agree on
  `spec/merge-conformance.json`.

Each package resolves independently and **every lockfile is committed**. A root
pub workspace was tried twice and reverted twice; the long comment at the top of
`Makefile` explains why it cannot work here. Don't try it a third time.

---

## 3. Verification: what runs, and when

`.github/workflows/ci.yml` triggers on:

- `pull_request` — checks out `refs/pull/N/merge`, i.e. what main will become
- `workflow_call` — invoked by `release.yml` so a tag cannot ship unverified code

There is **deliberately no `push: main`** trigger. The reasoning is in a comment
at the top of the file (it was half the repository's billed minutes). The
practical consequence for you: **a commit pushed straight to a branch with no PR
is never compiled by anything.** Every release so far has gone through a pull
request for exactly this reason — the PR *is* the build.

Jobs, roughly: pure-Dart packages (core, data) analysed and tested with a
standalone Dart SDK — that job never installs Flutter, and that *is* the
assertion that those two carry no Flutter dependency; `packages/ai`;
`packages/ui`; `apps/client` (analyze + test + Android debug build);
`apps/backend`; `apps/feedback-worker`; the four boundary proofs above; the
merge-conformance job; the Phase 2 sync matrix against a live PostgreSQL; and an
aggregate **CI green** job.

Note on the aggregate: when a run is superseded by a newer push, GitHub cancels
it and **CI green reports failure**. Check the run's actual conclusion before
believing a red aggregate.

---

## 4. Lint rules that will bite you

`analysis_options.yaml` in each Flutter package:

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

and every CI job runs `analyze --fatal-infos`. **An info fails the build.** Two
lint infos in one file have taken down an entire job here.

Things that have actually broken builds in this repository:

- **`use_key_in_widget_constructors`** applies to *public* widget classes only.
  Making a private `_Thing` public means it now needs `super.key`. This cost a
  CI round.
- **`unnecessary_import`**: adding `import 'package:flutter/material.dart'`
  beside an existing `import 'package:flutter/widgets.dart'` makes the latter
  unnecessary — replace, don't add. Conversely, `BoxWidthStyle` is **not**
  exported by material; it needs `import 'dart:ui' show BoxWidthStyle;`, and
  that import is genuinely necessary (it passes `unnecessary_import`).
  `TextInputAction` *is* available from material alone.
- **`unused_element` / `unused_import`** are fatal. Deleting the last caller of
  a private helper means deleting the helper, and then checking whether an
  import became unused.
- **`prefer_single_quotes`** — so a test name containing an apostrophe cannot be
  wrapped in double quotes to escape it. Reword it.
- **`library;` must be the first directive**, above the imports. A file-level
  doc comment attaches to it. One misplaced `library;` produced
  `library_directive_not_first`, which took down `packages/core`'s analyze, all
  22 of `packages/data`'s test files, and the merge-conformance job — from one
  line.
- **A `const false` flag folds guarded code into dead code**, which the analyzer
  rejects. `bool nexFirstRunTourEnabled = false;` is deliberately not `const`
  for exactly this reason; the doc comment on it says so.
- **Named arguments must follow positional ones.** `SelectableText(named: x,
  positional)` does not parse.

There is **no `dart format --set-exit-if-changed` check in CI.** Formatting will
not fail a build. `make fmt` exists if you want it, but do not expect the
pipeline to enforce house style — it enforces lints.

---

## 5. Releases

`release.yml` triggers on tags matching `v*.*.*` (or manual dispatch). The
**tag is the single source of truth**:

1. It stamps `apps/client/pubspec.yaml` and `apps/client/lib/app_version.dart`
   from the tag before building, so what is checked in never reaches a user.
2. It computes the Android `versionCode` by packing the version — **minor and
   patch must each stay under 100**, or the job errors out.
3. It finds the release notes by **section name**: the `## vX.Y.Z` heading in
   `CHANGELOG.md` matching the tag. Not by position — `CHANGELOG.md` opens with
   a prose section and carries a `## Unreleased` heading above the newest
   release, and both position-based rules were tried and were wrong.
4. It publishes to a **separate public repo** (`RELEASES_REPO`), not this one,
   because this repo is private and the in-app updater cannot hold a credential.
5. It calls the whole of `ci.yml` through its `verify` job first.

Because the workflow stamps the version, the checked-in numbers used to drift —
they sat at 1.3.2 for nine releases. So `apps/client/test/version_test.dart`
now asserts a **version triple**:

```
nexAppVersion  ==  pubspec.yaml version  ==  newest ## vX.Y.Z in CHANGELOG.md
```

plus a byte-for-byte check that `apps/client/assets/CHANGELOG.md` mirrors the
root `CHANGELOG.md` (the in-app update sheet reads the asset copy).

**So cutting a release is four edits, always together:**

```bash
# 1. apps/client/pubspec.yaml      version: X.Y.Z
# 2. apps/client/lib/app_version.dart   const nexAppVersion = 'X.Y.Z';
# 3. CHANGELOG.md                  new "## vX.Y.Z" section under "## Unreleased"
# 4. cp CHANGELOG.md apps/client/assets/CHANGELOG.md
```

Changelog entries are written for the person tapping "Check for update" — not
PR titles, not commit hashes, no internal refactors. See the file's own "How
this file is used" section.

The owner publishes outside GitHub Releases as well, and tags by hand after CI
is green. **Do not nag about missing tags or releases.**

---

## 6. How the work has been running

- All development happens on the branch `claude/project-status-review-jqgb5i`,
  pushed with `git push -u origin <branch>`. Never push to `main`.
- A pull request is opened only when the owner explicitly asks. There is a PR
  template at `.github/pull_request_template.md`; mirror its headings.
- The owner reviews on a real Android device, in Persian, and reports back in
  Persian. Their reports are precise and worth taking literally.
- When a PR is merged, the branch is restarted from the new `main`
  (`git fetch origin main && git checkout -B <branch> origin/main`) rather than
  stacking new commits on merged history.
- Commits are written as prose that explains the *reasoning*, not the diff. Code
  comments in this repo do the same — they say why, and they are expected to
  stay honest when the code changes under them. Match that register; it is the
  house style and the owner notices.

---

## 7. The traps that have actually cost time

This is the part you cannot get from the code.

**Things only a compiler or a device can tell you.** The recurring failure mode
across this whole project has been confident reasoning about runtime behaviour
that turned out to be wrong. Specific instances:

1. **A gesture diagnosis from a screenshot was wrong twice.** Guessing at
   gesture-arena behaviour or handle geometry by reading pixels produced two
   confident, wrong root causes in a row. Do not do it. Build a harness.
2. **`pumpAndSettle` pumps while frames are scheduled.** A long-running
   animation (`NexBorderBeam`, 4 × 2200 ms) runs the fake clock past the life of
   a transient widget, so a banner with a 3400 ms life was gone before the
   assertions ran. Fix: hand-pumped counted frames, settle only at the end. This
   one cost five CI rounds.
3. **A mock-HTTP "fake async" diagnosis was also wrong** — the mock client is
   microtask-driven. Stated out loud and corrected.
4. **`ListView(children:)` builds lazily; `SingleChildScrollView` builds
   everything.** A test that found a widget fine inside a scroll view found
   nothing after the screen became a `ListView`. Use `scrollUntilVisible`, not
   `ensureVisible`, on a lazy list.
5. **Pre-CI self-review caught two real defects** that no test would have: file
   text being read synchronously for twenty notes on sheet open, and a `const`
   flag that would have made guarded code dead. Re-reading your own diff
   adversarially before pushing is worth the minutes.

**Flutter behaviours that have caused real bugs here:**

6. **`EditableText.didUpdateWidget` compares `contextMenuBuilder` by identity.**
   A fresh closure per build reads as a changed menu, and the answer is to
   dispose the selection overlay and rebuild it after the next frame. The
   handles, magnifier and toolbar live in that overlay *with their gesture
   recognizers* — so a rebuild mid-drag cancels the drag and the replacement
   handle never saw the pointer. Both writing surfaces were minting a closure
   inside `build`. Fixed in v1.20.0 by hoisting to `late final`.
7. **`TextEditingController` notifies when the selection moves, not only when
   the text changes.** `controller.addListener(() => setState(() {}))` therefore
   rebuilds the whole sheet on every frame of a handle drag. The guarded shape
   (`if (text == _lastText) return;`) is in `note_editor_sheet.dart` and is the
   one to copy. This bug has been fixed three separate times, in three separate
   waves, as new sheets grew the same pattern.
8. **A `Text` cannot be selected at all.** No long press, no double tap, no
   handles. Nex renders nearly everything a person *reads* through
   `NexBodyText`, so until v1.20.0 most of the app answered no selection
   gesture — which users read as "selection is broken", not "unimplemented".
9. **`SelectionArea` claims taps.** It sits deeper than any `InkWell` or
   `GestureDetector` wrapped around it, so making the text inside a button
   selectable stops the button working. Three surfaces deliberately keep
   selection **off** for this reason, each with the reasoning written at the
   call site: the timeline card (opens its note), the checklist row (ticks its
   item), the daily brief card (folds away). Do not "fix" those.
10. **`textDirection` alone is not enough for RTL.** The argument places the
    glyphs; the selection handles, the magnifier and the context menu are
    resolved against the **ambient `Directionality`**. A right-to-left paragraph
    under a left-to-right overlay puts the handles on the wrong ends and drags
    the selection from the wrong side. `NexAutoDirection` exists to supply a real
    `Directionality` for fields; `NexBodyText`, the assistant's replies, the
    translation result and the code block each needed the same treatment, one
    wave at a time.
11. **Android's `ACTION_PROCESS_TEXT`** lets any installed app put its name on
    every selection menu on the phone, and Flutter forwards all of them (Ask
    Copilot, Ask ChatGPT, Read aloud…). They are told apart by
    `ContextMenuButtonType.custom`. The filter now lives once in
    `packages/ui/lib/widgets/nex_selection_menu.dart` — `nexOwnMenuItems`,
    `nexSelectionMenu`, `nexReadingMenu`. **Any new selectable surface or text
    field must pass one of those two builders**, or the names come back. They
    came back once already, exactly this way.
12. **`InteractiveViewer`**: `boundaryMargin` defaults to `EdgeInsets.zero`,
    which pins the child to its original bounds — the photo shoved back the
    moment you let go. And any wrapping drag recognizer fights it in the arena.
13. **Gesture arena**: a tap goes to the **deepest** recognizer that wants it
    (hit-test order is deepest-first, and the first member added wins the
    sweep). `NexKeyboardDismisser` is a single app-wide tap target that relies
    on exactly this — it only ever sees the taps nothing else claimed.
14. **The full-width swipe-back recognizer** (`nex_swipe_back.dart`,
    `HitTestBehavior.translucent`) wraps every pushed page. It was audited when
    read-only text became selectable and judged safe: on Android, selection
    begins on a long press, so a plain horizontal drag is still a swipe back.
    If you change selection gestures, re-check this.
15. **Android intent filters**: `ACTION_SEND` carries the URI in `EXTRA_STREAM`,
    `ACTION_VIEW` in `data`; a filter with `pathPattern` only matches when
    `mimeType` matches too.

**Process traps:**

16. **Scheduled check-ins carrying stale diagnoses.** Three fired at once with
    reasoning that had already been disproved. If you arm a follow-up, write it
    to re-read the current state rather than to act on a remembered conclusion —
    and delete it when it is superseded.
17. **A cancelled CI run reports as a failed aggregate.** Verify before reacting.

---

## 8. Where things stand

**Released and on `main`:** through **v1.21.0** (merged as #233, with this
handoff following as #234). CI was green on it. Nothing is outstanding on the
branch — it sits exactly on `main`.

What v1.21.0 contained, since it is the most recent work and the most likely
thing to need a follow-up:

- `packages/ui/lib/widgets/nex_selection_menu.dart` — new. The one filter, plus
  the two builder shapes Flutter asks for.
- Every selectable surface and all 27 text fields now pass one of them.
- `nexFormatContextMenuBuilder` refactored to start from `nexOwnMenuItems`
  instead of carrying its own copy of the rule.
- `NexMarkdown` brings its own `SelectionArea` when `selectable: true` instead
  of handing `selectable: true` to the markdown body (a `SelectableText`
  underneath, which swallowed link and code-span taps).
- `Directionality` added around the translation result and the code block.
- Four new tests in `packages/ui/test/nex_selection_menu_test.dart`.

### The one open bug

**Selection handles in a *text field* are wrong in Persian.** Reported with
screenshots after v1.20.1. Read-only text is now correct; the editor is not.
Symptom: double-tap selects a word correctly, then dragging a handle to extend
misbehaves — in the screenshot the two handles do not bracket the selection,
and the owner describes them as swapping.

What is already ruled out: the editor's field **does** have a real
`Directionality` (via `NexAutoDirection`, since v1.13.0), so this is not the
missing-structure problem that read-only text had. The app sets no
`TextSelectionThemeData` and no custom `selectionControls`. Nothing in the sheet
chain imposes a competing `Directionality`.

What is not known: whether this is something the app configures or a framework
behaviour in `EditableText`'s RTL handle dragging. **Read-only text
(`SelectableRegion`) and editable text (`EditableText` + `TextSelectionOverlay`)
are two completely separate implementations in Flutter** — fixing one never
fixes the other, which is precisely what the owner observed.

The proposed next step, not yet taken: write a widget test that drives the real
gesture — Persian text, double-tap a word, then drag a handle — against a
`TextField` and against a `SelectionArea`, and read what the selection actually
becomes. With a local Flutter SDK you can iterate on this in seconds instead of
CI rounds. If it turns out to be framework-side, the app-level lever is a custom
`TextSelectionControls` on the fields; that is real work and should not start
before the bug is reproduced in a harness.

**New evidence from the independent audit** (`NEX_RELEASE_AUDIT.md`, run on
Windows with an Android API 37 emulator): on the *published v1.20.1 APK*, a
double-tap and handle drag in the Edit note sheet **worked** — on a
**single-line** Persian note. The owner's failing screenshot was a
**three-line** note with the selection on the middle line, and the audit marked
multiline selection UNVERIFIED. The editor field is `minLines: 3` inside a
`ConstrainedBox(maxHeight: 220)`, so it can scroll internally. Reproduce with a
multiline note first; that is the strongest lead so far, not a diagnosis.

### Findings from the independent audit

Fixed in v1.21.1: the non-atomic restore (now `RestoreTransaction`, recovered on
the next `NexDatabase.open` if the app died mid-restore); the capture sheet
marking a failed write as saved; the direction classifier treating Arabic
neutrals as strong and ignoring LRM/RLM; and the three causes of a red
`make check` on Windows.

Also fixed in v1.21.1, from the audit's secondary items:

- **Restore and the Keep/Takeout import both streamed.** Each read the whole
  archive into memory before decoding; both now decode from an
  `InputFileStream` and write each entry out with `writeContent`.
- **Timeline and search ordering are deterministic.** A tie on the timestamp
  was left to SQLite; `n.rowid DESC` now breaks it in write order. This was
  the Windows-only pin-order "flake" — Windows' coarse clock gives two
  consecutive captures the same timestamp. Note the tagged timeline query is a
  join, so the tie-break must be qualified: a bare `rowid` there is an error.
- **npm advisories.** Backend: `qs` moved to 6.16.0 (a runtime dependency via
  Express). Worker: all four "high" findings were in `wrangler`'s dev
  toolchain (miniflare, sharp, undici), not the deployed worker; `wrangler`
  is now 4.137.0 with `@cloudflare/workers-types` bumped to satisfy its peer.
  Both report 0 vulnerabilities; both test suites pass.
- **The backend's IPv6 rate-limit bypass.** The sync and read limiters fell
  back to the raw request IP, which lets one IPv6 client rotate through its
  /64 and never meet the limit; `express-rate-limit` said so on every boot
  (`ERR_ERL_KEY_GEN_IPV6`). They now key through `ipKeyGenerator`.
- **A test that claimed more than it proved.** `os_capture_bridge_test`'s
  "a shared file is never read into memory" passes for a buffered
  implementation too; its comment now says what it does prove, and where the
  streaming is actually held.

Still open, deliberately:

- **Mixed-direction lines change direction between editing and reading.** One
  `TextField` has one base direction; the reader splits lines that disagree. A
  real fix is a paragraph-aware editor — `docs/NEX_V2_ROADMAP.md` territory,
  not a patch.
- **The Persian text-field handle bug** (above) — needs an Android runtime or
  at least a local Flutter SDK to reproduce; this session has neither.

### Smaller things left open

- **Scrolling screenshot** — asked for long ago, never built. Needs a native
  `ScrollCaptureCallback` plus Dart plumbing. Awaiting a decision.
- **A privacy ADR was offered and not written.** Since v1.17.0 the assistant can
  read a focused note's file text and images, so that content leaves the device
  when a cloud provider is configured. `docs/10-decisions.md` should carry an
  ADR for it, or it should sit behind a settings switch. The owner has not
  ruled.
- **`NexMarkdown`'s `selectable` default is `true`.** After v1.21.0 that means
  "wrap myself in a `SelectionArea`". Only the guide relies on the default;
  everything else passes `false` because it owns a wider area. Worth knowing
  before changing the default.

---

## 9. Conventions worth matching

- Comments explain **why**, in prose, and are maintained as first-class content.
  A comment that has gone stale is treated as a bug.
- Tests are named as sentences and carry a comment saying which bug they hold
  down. Several in `apps/client/test/` are characterisation tests written so
  that a future "simplification" cannot silently undo a fix — for example
  `text_selection_test.dart`, which asserts that a rebuild *actually happens*
  before asserting that the menu builder survived it.
- l10n lives in `apps/client/lib/l10n/app_en.arb` and `app_fa.arb`.
  `l10n_test.dart` guards parity: a key added to one and not the other, or
  "translated" by pasting the English back in, fails.
- The in-app guide is `apps/client/assets/guide/en.md` and `fa.md`.
  `guide_screen_test.dart` asserts the two have the **same number of sections**
  and that every Persian heading actually contains Persian. The owner asks for
  it to be kept current when features land.
- Persian and English are both first-class. Direction comes from the *text*, not
  from the interface language — see `packages/ui/lib/tokens/nex_text_direction.dart`,
  which is the single most load-bearing file for RTL correctness.

---

## 10. First hour

```bash
git fetch origin
git checkout claude/project-status-review-jqgb5i   # sits on main, v1.21.0
make bootstrap
make check                                          # confirm a clean baseline
```

`make check` should pass on a clean checkout. If it does not, that is a finding
in itself — every session before yours was flying blind, and a green CI run does
not prove `make check` is green (the two have drifted before; see the comment
above `check-ai` in the `Makefile`).

Then, in order:

1. Reproduce the Persian text-field handle bug in a widget test (§8). It is the
   only known open defect, the owner has hit it twice, and it is the one thing
   a local SDK makes tractable that the cloud sessions could not touch.
2. Read `docs/NEX_V2_ROADMAP.md` — the plan for the next major version, written
   at the end of the 1.21 cycle. It sequences the work and names what has to be
   decided before any of it starts.
3. Ask before opening a pull request, and ask before tagging.
