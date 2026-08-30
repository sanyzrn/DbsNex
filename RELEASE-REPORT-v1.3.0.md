# DbsNex / Nex — Product Evolution Release Report (v1.3.0)

Base: upstream `b029e4b` (v1.2.6). This tree is the evolved v1.3.0.
Every change below is implemented and covered by tests; nothing here is a
recommendation.

## What Was Fixed

Data integrity and recovery (the "can I trust this app with my notes" tier):

1. **Corrupt/locked database no longer hangs the app on the splash screen.**
   The DB isolate answered its boot port before opening the database and had
   no error/exit ports, so an open failure killed the isolate silently and
   left bootstrap waiting forever. The failure now surfaces as a named error
   screen with the real message, a Retry button, and a **Restore from backup**
   action that works without the app ever having to open
   (`db_worker.dart`, `bootstrap_host.dart`).
2. **"Delete forever" now deletes the attachment file too.** Purges removed
   only the DB row; photos, recordings and files stayed on disk forever (and
   rode every future backup). Purges now unlink media, guarded so a corrupted
   row can never delete outside the media root, and `sweepOrphanMedia`
   collects strays older than an hour (`library_maintenance.dart`).
3. **Restore sweeps `-journal` sidecars.** A stale rollback journal would be
   replayed over the freshly restored database. Both restore paths now clear
   `-wal`, `-shm` and `-journal` (`database.dart`, `backup_archive.dart`).
4. **Restore rewrites media paths.** A `.nexbak` restored onto a reinstall
   kept pointing rows at the old device's absolute paths — every attachment
   "restored" but unopenable. Rows are remapped to where files actually
   landed (`backup_archive.dart`).
5. **Restore media swap is atomic** (rename within the same filesystem) and
   **restore errors surface** in the backup screen instead of bricking the
   session silently. The restore itself runs off the UI isolate.
6. **Import is transactional.** A hand-edited or partial export used to
   throw mid-loop (FK on a dangling tag id) and leave half the archive
   imported, un-healable by re-import. All or nothing now, with dangling tag
   links skipped instead of fatal (`note_repository.dart`).
7. **Sync pull pages are transactional** — a poisoned page used to wedge the
   sync cursor permanently.
8. **Worker requests are serialized.** Async handlers used to interleave at
   their await points (a capture could land mid-import; a close could
   dispose the handle under a live handler).

## What Was Improved

- **SQLite runs in WAL mode** with `synchronous=NORMAL` — atomic commits,
  no reader/writer contention, and the crash story the backup code always
  assumed.
- **Hot paths indexed**: `notes(sync_state)` (outbox), `note_tags(tag_id)`
  (tag-filtered timeline), `notes(due_at)` (reminder rebuild) — placed after
  the legacy table rebuild so they survive migrations.
- **FTS search rows are consistent and repairable.** Every writer goes
  through one `_reindex` (editing a titled note no longer drops the title
  from search; transcripts no longer evict captions; restored-from-trash
  checklists/voice/photo notes are findable again), and `repairSearchIndex()`
  runs per open — cheap when healthy, self-healing when not.
- **Cached updater installers are SHA-256 verified** before being offered
  for install, not just size-checked.
- **Gradle heap reduced** 8G→4G (metaspace 4G→1G) so local builds don't OOM
  typical dev machines; stale workflow comment that could reintroduce the
  applicationId-suffix update-breaker fixed.

## New Features Added

- **Search filter sheet** — tag, type and date-window chips beside the
  search field, applied as tapped, with an active-count dot on the filter
  button. The controller had carried this state all along; only the buttons
  were missing.
- **Reminder test notification** in Settings: one notification now, one in
  ten seconds — the diagnostic that separates "Nex never sent it" from "my
  phone swallowed it".
- **Recovery from a dead library**: pick a `.nexbak` on the startup-failure
  screen; restore completes without the app ever opening.

## AI Improvements

- **No more fabricated transcripts.** The offline adapter answered voice and
  photo notes with seeded stub text that was stored, indexed and shown like
  a real transcript. It now honestly reports no capability.
- **Failure is retriable, absence is final.** A timed-out transcription, OCR
  call or embedding used to permanently close its slot (a rate-limited note
  became invisible to semantic search forever). Failures throw
  `AiUnavailableException` and the slot stays open; only a real answer —
  including a legitimate "nothing was heard" — closes it.
- **Freshly transcribed notes are embedded at capture time** (the stale
  in-memory copy used to embed nothing).
- **The local chat's scope ceiling actually reaches the model** (it used to
  be skipped whenever a system message existed — which the local path always
  supplies), and local conversation divergence is detected by content, not
  history length (thread B's tail no longer answers thread A's prefix).
- **Gemini API keys move to the `x-goog-api-key` header**, out of request
  URLs that land in proxy and server logs.
- **The sync bearer token lives in secure storage** (Keystore/DPAPI), same
  threat model as the API keys, with a one-time plaintext migration.

## UI/UX Improvements

- Timeline gains a genuine **error state with retry** for a failed first
  read (skeletons-that-never-resolve are gone).
- Trash rows show **when** a note was deleted (they used to repeat the note
  type), in the same relative-time vocabulary as the cards.
- The capture sheet's submit button meets the app's own **48px tap floor**;
  the tag row's inter-pill gaps are directional (RTL-correct); the settings
  close tooltip says "Close"; the update-available dot is labeled for screen
  readers; the AI recap says when its refresh failed; the filtered timeline
  says notes are hidden by filters instead of claiming an empty library.
- Three raw `showModalBottomSheet` call sites (reminder picker, chat
  history, translate) were folded into `nexShowSheet`, ending the
  sheet-chrome drift; the two DraggableScrollableSheet surfaces are a
  deliberate separate pattern and keep their shape.
- **Onboarding no longer demands your name** — finishing without one stores
  nothing, and Skip skips outright. The app's empty state always promised
  "nothing else is asked"; now onboarding does too.

## Reliability & Performance Improvements

- Delete/undelete/edit now reconcile OS alarms (`deleteNote` cancels,
  `undelete` re-arms, `updateNote` refreshes the notification's text), and
  `syncFromLibrary` **prunes alarms the library no longer asks for** —
  ghost alarms from a restore no longer fire and re-arm at every reboot.
- A repeating reminder's next occurrence is computed by arithmetic: a daily
  series older than ~26 months no longer retires itself at the old walk's
  guard limit. Alarm ids can no longer collide with the reserved daily/test
  ids (0/1/2).
- Timezone-init failure persists into the reminder error the user actually
  sees, instead of being overwritten by a clean schedule result.
- `allowBackup=false`: Android's Auto Backup silently uploaded the entire
  database (without its WAL — a classic corruption source) to Google Drive,
  contradicting the local-first promise. The app's own backups are the
  recovery path.

## Commercial / Store Readiness

- Version single-sourced at **1.3.0** (`pubspec.yaml` + `app_version.dart`),
  CHANGELOG cut per the release workflow's contract and the bundled asset
  copy synced (both are test-enforced).
- README updated to describe the shipping product (filters, diagnostics).
- Release-readiness unchanged where already strong: externalized signing,
  R8 + resource shrink with icon keep-rules verified in CI, tag-driven
  versioning, checksums published with every release, SCHEDULE_EXACT_ALARM
  (not the policy-restricted USE_EXACT_ALARM), no broad media/storage
  permissions, pinned action SHAs, and the AI package remains deletable
  (CI proves it).
- The Free/Premium seam the codebase already carries (`AiEntitlement`,
  gated tool executor) is untouched and clean — value first.

## Tests & Build Results

| Package | Analyze (`--fatal-infos`) | Tests |
|---|---|---|
| packages/core | clean | 60 passed |
| packages/data | clean | 110 passed, 13 skipped |
| packages/ai | clean | 17 passed |
| packages/ui | clean | 98 passed |
| apps/client | clean | 371 passed, 2 skipped |

656 tests passing (baseline was 629; 27 new tests cover purge file deletion,
FTS repair/consistency, restore remapping, journal sweep, reminder occurrence
math and id safety, filter-chip behavior, no-fabrication enrichment, and the
new onboarding contract). Four existing tests that pinned the removed
defects (stub transcripts, skipped scope ceiling, Gemini key-in-URL, name
gate) were updated to pin the new, intended contracts — no valid requirement
was weakened.

**Android release build**: verified in configuration, not run to completion
in this environment — a 10 GB sandbox cannot hold the Flutter SDK, the
Android SDK with the pinned NDK 28.2, and Gradle caches simultaneously
(ENOSPC during dependency transforms). The identical build
(`assembleAiRelease`, `--flavor ai`) is what the repository's own
`release.yml` runs on GitHub runners, and all Dart-side verification plus
the full static configuration (signing, R8, desugaring, keep-rules,
manifest) was validated here.

## Remaining Known Risks

- The Windows and iOS CI/build jobs remain paused upstream (`if: false`);
  Windows users currently have no update channel.
- Sync remains unreleased by design (no pairing flow); the tag-manager
  mutations that bypass the sync outbox are documented upstream behavior and
  were left as-is pending the v2 pairing design.
- The manual-arrangement `sort_order` column is still dead weight by choice
  (dropping it means a migration for zero user-visible gain).
- `READ_MEDIA_IMAGES` is declared but gallery reads go through the system
  picker; worth a check before a Play submission (a Play submission also
  needs a stance on the self-update path, which uses
  `REQUEST_INSTALL_PACKAGES`).

## Recommended Next Steps

1. Tag `v1.3.0` to let `release.yml` cut the signed AAB/APK set (the
   CHANGELOG section is in place; the workflow refuses to publish without
   it, so this is the whole mechanism).
2. Un-pause the Windows CI/build job or retire the Windows target
   deliberately, so the About screen's platform promise stays honest.
3. Watch the first release for the two behavior changes users will notice:
   restored-backup media paths and pruned ghost alarms.
4. When the v2 pairing flow lands, revisit the sync outbox coverage for
   tag-manager renames/merges (currently local-only by upstream design).
