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

## Phase 1 — Complete NEX-010 in `packages/core` (blocking everything else)

`packages/core` does not compile. This is the root blocker: until it is fixed,
the analyzer output for `apps/client` is not trustworthy, because most of it is
an echo of core's failure.

1. **Create `packages/core/lib/models/`.** `nex_core.dart` exports
   `models/note.dart` and `models/tag.dart`; neither file exists. `Note`, `Tag`,
   `NoteType`, `SyncState` and `SearchFilters` still live in
   `packages/data/lib/schema/models.dart`. Move them to core and have
   `nex_data.dart` re-export them for compatibility.
2. **Remove `import 'package:nex_data/nex_data.dart'` from core.** Five files
   still import it while `core/pubspec.yaml` no longer declares the dependency:
   `capture/capture_service.dart`, `ai/enrichment_service.dart`,
   `ai/ai_adapter.dart`, `ai/on_device_ai_adapter.dart`,
   `sync/field_aware_merger.dart`. The `core-boundary` CI job now enforces this.
3. **Resolve the duplicate type names.** `NoteRepository` and `SyncResult` are
   each declared twice — once in core, once in data — and `apps/client` imports
   both, producing `ambiguous_import`.
4. **Reconcile the `NoteRepository` port with reality.** The port declares 7
   async methods. Core's own services call 15 methods on it, synchronously
   (`getById`, `listTimeline`, `attachTag`, `upsertTag`, `setEmbedding`,
   `listEmbeddings`, `setOcrText`, `setSummaryText`, `setTranscriptText`,
   `setTagColor`, `detachTag`, `listTags`, …). The port is currently fiction.

   Suggested shape, matching the intent already visible in `_DbCommand`:
   rename the concrete synchronous class in `packages/data` to something like
   `SqliteNoteStore` (it runs *inside* the isolate), and let `NexDbWorker`
   be the async implementation of the `NoteRepository` port.

5. Add `implements SyncPort` to `SyncClient`, then run `dart analyze` in
   `packages/data` to find the remaining references.

---

## Phase 2 — Unify the client (largest remaining chunk)

`apps/client` currently contains two incompatible generations of the same
architecture side by side:

- **worker-based** — `nex_services.dart`, `db_worker.dart`, `bootstrap_host.dart`
- **direct-repository** — `polish_service.dart`, every screen, `capture_sheet.dart`

They disagree even on constructor signatures: core declares
`EnrichmentService({required repo})`, the client calls
`EnrichmentService(worker: worker)`.

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

## Process

The single cause of this whole class of problem: **a bulk migration was
committed without ever being built.** Commits `up`, `0`, `1`, `1` went straight
to `main`.

Enable branch protection on `main` requiring CI to pass, and run `make check`
before committing any generated change.
