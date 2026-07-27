# Outstanding Work

A 42-issue audit was applied to this repository by a generator script
(`apply_nex_fixes.py` + `nex_fixes_data.json`, both removed in the Phase 0
cleanup — see git history at `6d42b04` if you need the originals).

The script wrote every **file** change. It did not, and could not, perform the
follow-up steps the audit itself listed as manual. **None of the code-level
manual steps were done, and the tree was never built afterwards**, which is why
every CI job on `main` was failing before Phase 0.

This file is the surviving record of that remaining work. It replaces the
`manualSteps` array that used to live in `nex_fixes_data.json`.

---

## Phase 0 — CI restoration (done)

| Item | Resolution |
|---|---|
| Backend lockfile out of sync | `package-lock.json` regenerated; `npm ci` green |
| `exactOptionalPropertyTypes` vs zod output | Optional fields on `IncomingNote` / `IncomingTag` widened with `\| undefined` |
| ESLint vs Express error middleware arity | `argsIgnorePattern: "^_"`, matching what `noUnusedParameters` already allows |
| `core-boundary` job matched its own comments | Guards anchored to real declarations; an import guard added |
| Root pub workspace broke 3 jobs | Workspace removed; `make bootstrap` is the orchestration layer |
| `.flutter-version` pin was inert | Replaced by `.fvmrc` — `flutter-version-file` only accepts `pubspec.yaml`, `.fvmrc` or `.fvm/fvm_config.json`, so CI had been silently running latest stable (3.44.8 instead of 3.35.5) |
| Migration artifacts committed to `main` | `apply_nex_fixes.py`, `nex_fixes_data.json`, `.nex-fix-backups/` removed |

---

## Phase 1 — Complete NEX-010 in `packages/core` (done)

`packages/core`, `packages/data` and `packages/ai` now analyze clean under
`dart analyze --fatal-infos` and their suites pass (9, 23 + 6 skipped, and 10
tests respectively), verified against Dart 3.9.0 — the SDK CI pins.

1. **Domain models moved to `packages/core/lib/models/`.** `Note`, `NoteType`,
   `SyncState`, `Tag`, `SearchFilters` and `NoteEmbedding` now live in core, and
   `nex_data.dart` re-exports them so storage-layer callers keep one import.
   That direction is legal — data depends on core.
2. **`newUuidV7`, `sha256OfBytes`, `sha256OfFile` moved to `core/lib/ids.dart`.**
   They only ever needed `uuid` and `crypto`, both already core dependencies;
   living in the repository file was what forced core's capture service to
   import the storage layer just to mint an id.
3. **All five `import 'package:nex_data/…'` lines removed from core.** The
   `core-boundary` CI job enforces this now.
4. **Duplicate type names resolved.** The concrete repository is
   `SqliteNoteRepository implements NoteRepository`; `SyncResult` has a single
   definition in core.
5. **The `NoteRepository` port now describes what the code actually does.** It
   declared seven `Future`-returning methods on the grounds that the
   implementation "runs on a worker isolate". The real topology is the reverse:
   `package:sqlite3` is a synchronous FFI binding, so the repository is
   synchronous and runs *inside* the isolate next to the domain services. The
   port is synchronous, carries the 15 methods core actually calls, and
   `NexDbWorker` is a client of it rather than an implementation.
6. **`SyncClient implements SyncPort`.**

### Two defects this surfaced

- **The Dart merge conformance test had never compiled.** It was written
  against an API that does not exist (`MergeableNote`, a static
  `FieldAwareMerger.merge`, `MergedNote.toJson`). Repairing it immediately
  found a **real cross-language divergence**: on a tombstone the server erases
  the payload and empties the tag set (NEX-035), while the Dart merger kept the
  tombstone's `content`/`mediaUri` and *unioned* the tags. Dart also emitted
  `tag_ids` in `Set` insertion order, so the same pair merged in opposite
  argument order serialised differently and broke the commutativity ADR-020
  requires. Both are fixed; all 12 corpus cases now pass in both languages and
  both argument orders.
- **Two "core" tests were storage integration tests.** `capture_service_test`
  and `ai_suggestions_test` construct a real `NexDatabase`, which core is not
  allowed to depend on. They moved to `packages/data/test/`, where that
  dependency is legal, and they still exercise the same behaviour.

---

## Phase 2 — Unify the client (largest remaining chunk)

`apps/client` currently contains two incompatible generations of the same
architecture side by side:

- **worker-based** — `nex_services.dart`, `db_worker.dart`, `bootstrap_host.dart`
- **direct-repository** — `polish_service.dart`, every screen, `capture_sheet.dart`

They disagree even on constructor signatures: core declares
`EnrichmentService({required repo})`, the client calls
`EnrichmentService(worker: worker)`.

Measured with Flutter 3.35.5: **116 analyzer issues** — 68 in `lib/`, 48 in
`test/app_smoke_test.dart`. (It was 141 before `LibraryMaintenance` moved to the
storage layer.) `packages/ui` is done and green.

### The design decision this hinges on

`NexServices` runs on the UI isolate and holds a `NexDbWorker`, which is
asynchronous. The `NoteRepository` port is synchronous, because the repository
lives *inside* the isolate. So the UI cannot hold a repository, and every screen
that touches the database has to go through the worker and become asynchronous.

That is the whole remaining job, and it is **not a rename**: the screens are
written synchronously today —

```dart
late List<Note> notes = widget.services.search.timeline(limit: 50);
setState(() => _note = widget.services.repo.getById(widget.noteId));
```

— so each one needs a state-management conversion (async init + `setState`, or
`FutureBuilder`), across eight stateful widgets.

`EnrichmentService` has the same constraint and the same answer: it takes a
synchronous `NoteRepository`, so it must be constructed **inside** the worker
isolate, not on the UI isolate as `nex_services.dart` currently tries to. This
is fortunate rather than awkward — `main.dart` binds `const OnDeviceAIAdapter()`,
which is pure Dart in `packages/core` and therefore isolate-sendable, and it
moves AI work off the UI thread, which is what 09-ai.md wants anyway.

### Remaining steps

- Extend `_DbCommand` and `NexDbWorker` to cover every call site: capture
  (text/voice/photo/file), `getById`, `updateContent`, `softDelete`, `undelete`,
  `setCaption`, `addTag`, `removeTag`, `listTags`, `search`, `timeline`, the
  `LibraryMaintenance` operations, and the enrichment entry points
  (`enrichNote`, `suggestTags`, `summarizeOnDemand`, `relatedNotes`,
  capability updates). The worker's request handler must become `async` —
  `exportArchive` returns a `Future` today and a `Future` cannot cross a
  `SendPort`.
- Turn `NexServices` into the async façade over those commands, and fix the two
  constructor calls Phase 1 exposed: `EnrichmentService(worker:)` and
  `SyncClient(worker:, bearerToken:)` do not match the real signatures.
- Convert the eight screens.
- Fix the independent bugs that are not part of the split:
  `nex_bidi.dart` uses `TextDirection.rtl/ltr` from the wrong `TextDirection`
  (`dart:ui` vs `package:flutter`); `listBackups()` is used without `await` in
  three places; `useResult` is not imported; `DetailResult` is referenced but
  never declared.
- Rewrite `test/app_smoke_test.dart` (48 issues) against the new façade.

6. **NEX-020 — route all SQLite I/O through the worker.** Grep
   `apps/client/lib` for `services.repo.` — every hit must become a worker call.
   Three commands are missing from `_DbCommand`: `undelete`, `setCaption`,
   `getById`.
7. **`polish_service.dart` (29 analyzer errors).** It runs raw SQL against
   `repo.db` on the UI isolate. That SQL belongs in `packages/data`, reached
   through the worker.
8. **NEX-023 — media capture.** `timeline_screen.dart:72` still calls
   `ImagePicker().pickImage(...)` directly. Replace with `services.mediaPicker`
   and drive button visibility from `mediaPicker.supportsCamera` rather than
   `Platform.is*`.
9. **NEX-014 — commit `apps/client/pubspec.lock`.** `.gitignore` now un-ignores
   it, but the file still has to be generated with the SDK pinned in `.fvmrc`
   and committed. Requires a machine with the Flutter SDK.

---

## Phase 3 — Sync correctness

10a. **Done: the client never authenticated.** `SyncClient` sent no
    `Authorization` header at all, while the API stopped being open when
    tenancy landed — so every push and pull against a real server returned 401.
    It now takes a bearer token, `NexPreferences` persists it beside the
    endpoint, and the CI sync matrix seeds both simulated devices with their own
    tokens (it previously seeded one device under an id the suite never used,
    and the suite never sent a token anyway).


10. **NEX-004 — tag identity remap is unimplemented on the client.** The server
    returns a `tag_remap` array from `/sync/push`; `SyncClient` ignores it. It
    must rewrite local `note_tags` rows from `client_id` to `canonical_id`
    inside one local transaction, then delete the orphaned local tag row.

---

## Operational steps (no code change)

11. **NEX-017 — Android signing.** Generate the upload keystore
    (`keytool -genkeypair -v -keystore nex-release.keystore -alias nex -keyalg RSA -keysize 4096 -validity 10000`),
    base64-encode it, and add `ANDROID_KEYSTORE_BASE64`,
    `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`
    as GitHub Actions secrets. Never commit the keystore.
12. **NEX-015 — versionCode.** Confirm no previously published Play build used a
    versionCode above `MAJOR*1000000 + MINOR*1000 + PATCH` for the current
    version. If one did, add a constant offset in the release workflow.
13. **NEX-002 — provision accounts.** Insert a row into `users` per person, call
    `POST /auth/pairing-code` from an already-trusted device, redeem via
    `POST /auth/pair`. Set `ALLOWED_ORIGINS` and `DATABASE_URL` in the
    deployment environment.
14. **NEX-039 — monochrome launcher icon.** Replace the placeholder `pathData`
    in `nex_icon_monochrome.xml` with the real single-colour Nex silhouette,
    then verify under themed icons in light and dark mode.

---

## Already satisfied

`NEX-009` (Dart conformance test present at
`packages/core/test/merge_conformance_test.dart`, reading the shared corpus at
`spec/merge-conformance.json`) and `NEX-035` (tombstone assertions updated —
the backend suite passes 25/25) were listed as manual steps but are done.

---

## Dependency policy

Dependabot opens **at most two PRs per ecosystem per month**: one grouped
minor+patch, one grouped major. Majors are surfaced rather than pinned away —
silent drift is what this repo already paid for once — but they arrive together
instead of one PR per package.

Security advisories ignore all of that: Dependabot raises them from the advisory
database regardless of schedule, grouping or limits. Merge those promptly.

Deliberately **not** taken, because the backend's automated coverage is the merge
suite plus a `/health/live` smoke boot — nothing exercises the routes, so a
major with breaking route semantics would not be caught:

| Update | Why it needs a human |
|---|---|
| `express` 4 → 5 | Routing, `req.query` becomes a getter, async error handling changes. Would also make `express-async-errors` removable. |
| `express-rate-limit` 7 → 8 | Breaking option/store changes on a security control. |
| `zod` 3 → 4 | Rewritten inference; `sync.ts` already sits on an `exactOptionalPropertyTypes` edge. |
| `typescript` 5.7 → 7 | Compiler major. |
| `eslint` 9 → 10 | Config/rule major, paired with `@eslint/js`. |
| `dotenv` 16 → 17 | Changed default load behaviour. |
| Kotlin, AGP, Gradle wrapper | Cannot be verified without the Android toolchain. |

Route-level tests for the backend are the prerequisite for taking the express
and zod majors with any confidence.

## Process

The single cause of this whole class of problem: **a bulk migration was
committed without ever being built.** Commits `up`, `0`, `1`, `1` went straight
to `main`.

Enable branch protection on `main` requiring CI to pass, and run `make check`
before committing any generated change.
