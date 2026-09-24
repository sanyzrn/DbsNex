# Nex independent pre-release audit

**Audit dates:** 2026-09-23–24. **Checkout:** `5753ac0` (working tree initially clean). **Shipping target:** Android. **Flutter:** 3.35.5, framework `ac4e799d23`, Dart 3.9.2. This report distinguishes tests run on Windows from Android runtime observations.

## Environment and commands

- **Android runtime:** available: Pixel 10 Pro Android emulator (`emulator-5554`, API 37, 1280 × 2856). Android build and touch results are recorded separately for the previously released APK and this checkout.
- **Outbound network:** available to some hosts. `storage.googleapis.com` denied the SDK download with `AccessDenied ... service is not available in your location`; `storage.flutter-io.cn` supplied the pinned SDK. `pub.dev` returned `authorization failed`; dependencies were resolved through `pub.flutter-io.cn`. This rewrote lockfile host URLs and updated some permitted package versions during `make bootstrap`; those generated changes are removed before delivery. Therefore test results do not prove the exact committed dependency graph.
- **AI provider credentials:** none supplied to this audit. Provider-backed requests, transcription, and rewriting are **UNVERIFIED** at runtime.
- **Host tools:** Windows had no `make` on PATH; I used a portable GNU Make 4.4.1 executable outside the repository. The Android SDK initially lacked NDK 28.2.13676358; I installed that exact version after verifying its published SHA-1. Gradle dependency resolution required a temporary user-level mirror configuration because Google Maven returned missing resources in this network. Local Gradle used Android Studio JDK 25; CI configures JDK 21, so a successful local APK would not reproduce CI's Java environment exactly.
- Commands used: `make bootstrap`; `make check`; `make check-backend check-worker` to run the targets skipped after `make check` stopped; `flutter build apk --debug --flavor standard` (the Android CI build command). Temporary tests under `*/test/` reproduced the defects described below and are removed before delivery. No application code or commit was changed.

### Actual command output

`make bootstrap` exited 0. Its final output included:

```text
cd apps/backend  && npm ci
added 190 packages, and audited 191 packages in 14s
1 moderate severity vulnerability
cd apps/feedback-worker && npm ci
added 39 packages, and audited 40 packages in 10s
4 high severity vulnerabilities
```

The first `make check` run stopped on an unnecessary import in the temporary audit test. I removed that import and reran the full target. The rerun output was:

```text
cd packages/core && dart analyze --fatal-infos && dart test
No issues found!
00:00 +175: All tests passed!
cd packages/data && dart analyze --fatal-infos && dart test
No issues found!
00:05 +136 ~13: All tests passed!
cd packages/ai && flutter analyze --fatal-infos && flutter test
No issues found! (ran in 24.1s)
00:00 +17: All tests passed!
cd packages/ui && flutter analyze --fatal-infos && flutter test
No issues found! (ran in 13.6s)
00:06 +156: All tests passed!
cd apps/client && flutter analyze --fatal-infos && flutter test
No issues found! (ran in 32.2s)
01:03 +635 ~2 -12: Some tests failed.
make: *** [Makefile:58: check-client] Error 1
```

The 12 client failures comprise eight Windows file-lock teardown errors (`PathAccessException`, errno 32) in `capture_never_waits_test.dart`, `db_worker_spawn_test.dart`, and `search_filter_test.dart`; two `os_capture_bridge_test.dart` assertions received no captured note; `version_test.dart` threw `Bad state: No element`; and `timeline_rebuild_test.dart` failed a pin-order geometry assertion (actual y=412, expected y<316). An isolated rerun of the bridge and timeline files reproduced the two bridge failures; the timeline file passed in that run. The bridge tests' fake native side calls `File(Uri.parse(uri).path)` on a Windows `file:///C:/...` URI, yielding `/C:/...` rather than a usable `C:\...` path; this explains the two empty-note assertions on this host, but is a test-harness defect, not proof that Android sharing fails. These failures were not reproduced on Android and should not be presented as Android behavior. Since `make check` stopped at `check-client`, I ran its remaining named targets:

```text
make check-backend check-worker
ℹ pass 51
ℹ fail 0
ℹ pass 9
ℹ fail 0
```

The backend run also printed `ERR_ERL_KEY_GEN_IPV6` diagnostics from `express-rate-limit` while returning exit 0. Those diagnostics need separate backend investigation; they are not evidence of a client-side exploit.

The Android CI command, `flutter build apk --debug --flavor standard`, did not initially reach compilation. Before and after installing the exact NDK and adding a temporary external Gradle mirror configuration, attempts reported these representative errors:

```text
> NDK not configured. Download it with SDK manager. Preferred NDK version is '28.2.13676358'.
> Could not find gradle-8.13.1.jar (com.android.tools.build:gradle:8.13.1).
  Searched in the following locations:
      https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/8.13.1/gradle-8.13.1.jar
> Could not GET 'https://maven.aliyun.com/repository/google/com/android/tools/build/gradle/8.6.0/gradle-8.6.0.pom'.
  > No such host is known (maven.aliyun.com)
```

These are build-host dependency failures, not evidence that the application source fails to compile. A final attempt through a reachable Google redirector remained in dependency setup for about seven minutes with no further build output or APK; I stopped it. **No Android APK was produced from this checkout, so current-version Android runtime behavior is UNVERIFIED.** This is a failure of audit coverage and local build verification, not a demonstrated application compiler defect.

Temporary reproductions run individually (all temporary files removed afterward):

| Working directory | Command | Result |
| --- | --- | --- |
| `packages/data` | `dart test test/audit_restore_atomicity_test.dart` | 1 passed; demonstrated a failed restore replacing the live note. |
| `packages/ui` | `flutter test test/audit_mixed_text_test.dart` | 2 passed; demonstrated mixed-line direction mismatch and bidi classifier cases. |
| `apps/client` | `flutter test test/audit_capture_retry_test.dart` | 1 passed; demonstrated no retry while an update is stalled. An earlier thrown-write variant intentionally failed with an unhandled `StateError`. |
| `packages/data` | `dart test test/checklist_link_title_test.dart` | 8 passed; exercised the old-schema migration fixture. |

## Confirmed findings, ordered by severity

### 1. Blocker (release verification) — the required `make check` gate exits nonzero on this host

**Problem:** `make check` ends at `check-client` with 12 failed client tests, so the local release gate is not green. **Location:** `Makefile:57-69`; representative failing assertions are `apps/client/test/os_capture_bridge_test.dart:218,341`, `apps/client/test/version_test.dart:43-47`, and `apps/client/test/timeline_rebuild_test.dart:388-444`.

**Root cause — confirmed in part:** Eight failures are Windows temporary-file deletion locks in test teardown; two are the fake native bridge's Windows URI-to-path conversion (`os_capture_bridge_test.dart:43-45`); and the version test's CRLF-sensitive regular expression matches no changelog heading. The one timeline pin-order failure was not reproduced when its file was rerun in isolation; its cause remains a **hypothesis/unresolved**, not a demonstrated product ordering defect.

**Reproduction:** After successful `make bootstrap`, `make check` reported `01:03 +635 ~2 -12: Some tests failed` and `make: *** [Makefile:58: check-client] Error 1`. `flutter test test/os_capture_bridge_test.dart test/timeline_rebuild_test.dart` reproduced both bridge failures (0 notes rather than 1) while the timeline file passed. Direct Dart URI inspection showed `File(Uri.parse('file:///C:/...').path)` yields `/C:/...` on Windows, while `File.fromUri` yields `C:\...`. The eight lock errors and the changelog failure are in the full command log.

**User impact:** The publisher cannot claim this checkout passed its required local verification target. These host-side failures do not by themselves show that the Android application fails to capture shares or order pinned notes.

**Recommended solution:** Fix the bridge test fake to construct a file with `File.fromUri`, normalize CRLF in `version_test.dart`, and make affected test teardowns release database and worker handles before deleting temp directories. Reproduce or dismiss the pin-order failure under CI's test host, then rerun the entire `make check` target; do not infer an Android share defect from the fake's Windows path.

**Verification:** `make check` exits 0 on Windows and the CI host with no test skips added; the bridge cases capture one file each, version parsing finds 1.21.0, pin order is deterministic, and the Android debug build succeeds independently.

### 2. Critical — a failed archive restore can replace the live database and then fail before restoring media

**Problem and location:** `packages/data/lib/schema/backup_archive.dart:166-199` deletes the live database, installs the staged database, then swaps the media directory. An exception during the second swap leaves the database from the backup installed while the old media directory remains. `packages/data/lib/schema/database.dart:456-460` has a similar delete-before-rename window for legacy `.sqlite` restores.

**Root cause — confirmed:** Database and media replacement are separate destructive operations without a rollback copy or recovery marker. Validation before the swap (`backup_archive.dart:146-163`) does not make the subsequent two-resource swap atomic.

**Reproduction:** A temporary `packages/data/test/audit_restore_atomicity_test.dart` created a backup with an earlier note and media file, changed the live note, placed a regular file at the reserved `media.incoming` path, then called `NexBackupArchive.restore`. The restore threw `FileSystemException` at the media rename. Reopening the live database returned the earlier note (`before backup`) instead of the live edit (`new live edit`). The test passed under Dart 3.9.2. This is an unavailable-destination case; a process interruption between the two swaps has the same inconsistent ordering, but interruption itself was not injected.

**User impact:** Restore reports failure while newer notes or edits are already overwritten. Media paths may point to files from a different snapshot. A user can lose work while believing the live library was left untouched.

**Recommended solution:** In `NexBackupArchive.restore`, stage and validate both resources, preserve the old `nex.sqlite` and `media/` as rollback siblings, perform the swaps with a recorded recovery state, then remove rollback copies only after `_remapMediaUris` and integrity checks succeed. Restore both old resources on any exception. Apply the same preserve-and-rollback rule to `NexDatabase.restoreFromBackup`.

**Verification:** Add a persistent test that injects failure at every file operation after validation and asserts the original database row, media bytes, and sidecars survive; then rerun restore after simulated interruption. Test both `.nexbak` and legacy `.sqlite` paths on Android as well as the host.

### 3. High — capture acknowledges an edit before its asynchronous write succeeds

**Problem and location:** `apps/client/lib/widgets/capture_sheet.dart:139-157,194-205`. `flush()` fires `services.updateNote` without awaiting it, then immediately sets `persisted = controller.text`. Closing or disposing the sheet calls `flush()` again, sees equal strings, and does not retry. The first-note creation path in the same file does not resolve this later-update case.

**Root cause — confirmed:** `persisted` tracks an enqueued write rather than a successful database commit. `NexServices.updateNote` awaits the worker (`apps/client/lib/platform/nex_services.dart:314-327`), but the sheet discards that future and has no failure state.

**Reproduction:** Temporary `apps/client/test/audit_capture_retry_test.dart` used the real in-process repository with an update operation that remained pending. After the first version saved, typing a replacement and disposing the sheet produced one update call, no retry, and the database still held the first version. A separate run with the update throwing `StateError` produced an unhandled test-framework exception with the stack at `capture_sheet.dart:154`; it did not produce a user-visible recovery path. The pending-operation test passed; the thrown-error run intentionally failed and is retained in the command evidence, not in the delivered tree.

**User impact:** If a slow device is closed or killed while the write remains pending, or storage/worker failure prevents the write from completing, text visible just before the sheet closes may never reach the library. The UI has already treated it as saved.

**Recommended solution:** Track the last committed text and the in-flight update separately in `CaptureSheet`. Await or explicitly reconcile the final write before closing; on failure, keep the draft and show a retryable error. Do not advance `persisted` until `NexServices.updateNote` completes. Ensure a reopened sheet can recover an interrupted draft.

**Verification:** Inject a delayed update, a thrown write, and closure while an update is pending; assert the final text survives restart or remains visibly retryable. Include the fast-typing path already exercised by `capture_sheet_draft_test.dart`.

### 4. Medium — mixed-language lines change direction between editing and reading

**Problem and location:** `apps/client/lib/widgets/note_editor_sheet.dart:213-245` and `apps/client/lib/widgets/capture_sheet.dart:261-280` give each editable `TextField` one direction from `NexAutoDirection`. `packages/ui/lib/tokens/nex_text_direction.dart:210-249` gives a mixed read-only body separate directional lines.

**Root cause — confirmed:** `nexDirectionOf` scans the full string for its first strong character (`nex_text_direction.dart:29-39`), and the editor applies that result to every newline-delimited line. The reader explicitly splits lines when their directions disagree. Temporary `packages/ui/test/audit_mixed_text_test.dart` passed with `English\nفارسی`: the editor field was LTR while the rendered Persian line was RTL. This proves the configuration difference; the extent of cursor and handle disruption for this case is **UNVERIFIED** on a device.

**User impact:** A Persian line after an English opening line is laid out under the English base direction while writing, then changes alignment on Save. The reverse order similarly affects English lines. This makes editing and reviewing the same note inconsistent.

**Recommended solution:** Give editable paragraphs independent base directions while preserving one continuous editing and selection model. The current single `TextField` cannot achieve that by changing only `NexAutoDirection`; evaluate a paragraph-aware editing implementation in `NoteEditorSheet` and `CaptureSheet`, then retain the same per-line rule in `NexBodyText`.

**Verification:** On Android, enter and edit `English\nفارسی` and `فارسی\nEnglish`, including punctuation and numbers; assert each line's alignment, caret movement, multiline selection, copy, and post-save layout. Keep a widget test comparing editable and read-only paragraph geometry.

### 5. Medium — neutral Arabic marks are treated as strong RTL characters

**Problem and location:** `packages/ui/lib/tokens/nex_text_direction.dart:42-83` classifies the whole `0x0590..0x08FF` range as RTL except a short digit and sign list. That includes Arabic comma U+060C (Unicode bidi class CS) and Arabic fatha U+064E (NSM), which are not strong directional characters. LRM U+200E is a strong L mark but is ignored by the classifier.

**Root cause — confirmed:** Broad code-point ranges substitute for bidi classes. Python's Unicode database returned `CS`, `NSM`, and `L` respectively; the temporary `audit_mixed_text_test.dart` confirmed the app returns RTL for `، hello`, `َ hello`, and `\u200Eمتن`.

**User impact:** Pasted mixed-script text or content beginning with an Arabic separator/combining mark can align to the wrong edge and move its caret and selection base. Direction may disagree with Unicode's first-strong rule documented in this file.

**Recommended solution:** Replace `_directionOfRune` with an actual Unicode bidi-class lookup that skips neutral and nonspacing marks and honors LRM/RLM, while preserving the first-strong policy. Add classifier cases for Arabic punctuation, combining marks, explicit direction marks, digits, and mixed text.

**Verification:** Compare `nexDirectionOf` to Unicode bidi classes for a curated corpus, then verify the corresponding Android editor and reader alignment and selection boundaries.

## Text selection investigation

**Previous-release Android baseline, runtime verified:** I installed the [published v1.20.1 x86_64 APK](https://github.com/sanyzrn/DbsNex-releases/releases/download/v1.20.1/Nex-1.20.1-x86_64.apk) on the API 37 emulator; its SHA-256 was `1fa9ecaad2d22e9b42a23d25024378af0b9d92781552195440a02685a9657cdc`, matching the published checksum. I shared `این یک یادداشت فارسی برای آزمایش انتخاب متن است` into Nex, opened the read-only note, double-tapped `یادداشت`, and dragged a handle using ADB touch input: the highlight extended across the expected adjacent words. A separate long press selected the same word and showed the Copy menu. In its **Edit note** sheet, a double-tap selected that word and dragging the left handle extended the selected span from `یادداشت` through `آزمایش`. These gestures were controllable in this emulator run of v1.20.1. This confirms the reported read-only baseline, but does not yet confirm the reported editable failure on a real device or in the current checkout. Screenshots were saved outside the repository under the system temp directory (`nex-audit-old-selection*.png`, `nex-audit-old-editor-*.png`, `nex-audit-old-longpress.png`).

**Current checkout's reported Persian handle reversal: UNVERIFIED because its Android build did not produce an APK.** The code sets both `Directionality` and `TextField.textDirection` in `NexAutoDirection` (`nex_text_direction.dart:370-384`, `note_editor_sheet.dart:213-245`). Flutter 3.35.5's `TextSelectionOverlay` chooses editable handle types from `RenderEditable.textDirection` (`packages/flutter/lib/src/widgets/text_selection.dart:541-555` in the pinned SDK). The read-only `SelectionArea` and editable `EditableText` use separate selection paths; success in one does not establish success in the other. The current tests check direction and widget identity, not a finger dragging an actual Android handle: `packages/ui/test/nex_text_direction_test.dart:249-262`, `apps/client/test/text_selection_test.dart:54-99`. The user's real-device report remains a release risk until reproduced or disproved in a current build.

The temporary mixed-text test verified the static editor/reader direction difference, not touch selection. The standard suite exercised save/cancel, fast capture, read-only `SelectionArea`, and selection-menu construction. It did not establish Persian handle drag, cross-line selection, copy/paste contents, IME composition, magnifier position, or scroll-during-selection behavior. Each is **UNVERIFIED** unless separately recorded below.

| Text behavior | Evidence and status |
| --- | --- |
| Persian, read-only, double-tap then handle drag | **Runtime verified only in v1.20.1 on API 37:** selected `یادداشت` and extended the expected span. |
| Persian, Edit note, double-tap then handle drag | **Runtime verified only in v1.20.1 on API 37:** selected `یادداشت` and extended through `آزمایش` in one gesture. The current-build and real-device reversal report are **UNVERIFIED**. |
| Mixed English/Persian newline layout | **Widget verified:** editor base direction LTR for `English\nفارسی`, reader's Persian line RTL. Android touch, caret, and saved layout are **UNVERIFIED**. |
| Initial Arabic punctuation, combining mark, LRM | **Unit verified:** classifier returns RTL for the three exact strings in finding 5. Android layout and handles are **UNVERIFIED**. |
| English words, numbers, and punctuation | Selection boundaries and caret positioning are **UNVERIFIED** at runtime in the current build. |
| Long press and handle drag | **Runtime verified in v1.20.1 read-only:** long press selected a Persian word and showed Copy. Long press in the current build is **UNVERIFIED**. |
| Multiline selection and scrolling while selecting | **UNVERIFIED** at runtime in the current build. |
| Copy and paste | The Android context menu was visible on v1.20.1; clipboard contents and pasted result are **UNVERIFIED**. |
| IME with a composing region | **UNVERIFIED** at runtime in the current build. |

## Upgrade, journeys, and adverse conditions

- **Upgrade method:** old-schema database fixture, not a previous APK. `packages/data/test/checklist_link_title_test.dart:129-188` builds a legacy `CHECK(type IN ('text','voice','photo','file'))` table, opens it through `NexDatabase`, checks the old text survives, inserts a checklist, and reopens successfully. That test passed in `make check`'s data target. It does not model every prior release or an interrupted migration. The migration and table rebuild are in `packages/data/lib/schema/database.dart:29-385`.
- **Create/edit/delete/restart:** repository tests passed for insert, soft delete, undo, FTS, backup, and restore; client tests for editor Save/Cancel and capture drafts passed. I launched the verified v1.20.1 APK on the emulator, skipped onboarding, shared a Persian note from Android, opened it and entered Edit note. After force-stopping and relaunching that version, the Persian note remained on the timeline. This is a previous-release baseline, not an end-to-end test of the current checkout. I did not execute delete on the emulator. The capture update failure and restore failure above are the adverse branches with concrete data risk.
- **Scale:** `packages/data/test/performance_budget_test.dart` exercised capture and search against its test corpus and passed. I did not load years of real user media or interrupt a physical device during migration; long-duration media, WAL, and backup growth are **UNVERIFIED**.
- **Accessibility best effort:** `packages/ui/test/accessibility_test.dart` exercised minimum filter target sizes; `note_card_text_scale_test.dart` exercised a scaled card. Screen reader traversal, high contrast, and reduced-motion behavior remain **UNVERIFIED** at runtime.
- **Privacy best effort:** Android manifest requests internet, audio, camera, media images, biometric, notifications, foreground service, boot, exact alarms, and install-packages permissions (`apps/client/android/app/src/main/AndroidManifest.xml:2-42`). `android:usesCleartextTraffic="false"` and `android:allowBackup="false"` are set at lines 68-69. API keys are written through `FlutterSecureStorage` (`apps/client/lib/platform/nex_preferences.dart:909-952`); no credential value is included here. The export backup is intentionally a plain, unencrypted ZIP containing SQLite and media (`packages/data/lib/schema/backup_archive.dart:13-31`). I found no embedded AI provider credential. Network traffic, log contents, platform backup behavior, and third-party SDK traffic were not captured on Android and are **UNVERIFIED**.
- **Publisher:** checked-in `apps/client/pubspec.yaml:6` and `apps/client/lib/app_version.dart:7` both say 1.21.0, matching `CHANGELOG.md:37`. `.github/workflows/release.yml` stamps from the tag, verifies CI, and builds an Android release. I did not sign, publish, or test rollback of a release artifact. The Android debug-build limitation is recorded above.

## Existing claims contradicted by investigation

- `Makefile:1` and `HANDOFF.md:31-36` say `make check` mirrors CI one-to-one and a pass means CI passes. `Makefile:57-69` has analyze and test, but `.github/workflows/ci.yml:292-330` also builds an Android debug APK; CI additionally runs boundary and merge-conformance jobs described in `HANDOFF.md:75-96`. The local target is useful, but it is not the whole pipeline. The current local run is red as shown above.
- `apps/client/test/version_test.dart:43-47` says it finds the newest `## vX.Y.Z` section. On this Windows checkout, `CHANGELOG.md` lines end in CRLF, and splitting on `\n` leaves `\r`; the `$`-anchored regular expression matches no line. The executed test fails with `Bad state: No element` even though the checked-in versions agree. This is a test portability defect, not a proven release version mismatch.
- `apps/client/test/os_capture_bridge_test.dart:182-190` claims matching hash and copied bytes can hold *only* if a file was streamed. A whole-file `readAsBytes` and `writeAsBytes` implementation would satisfy those same assertions. The two tests also fail on Windows because the fake native side converts `file:///C:/...` with `File(Uri.parse(uri).path)` (`os_capture_bridge_test.dart:43-45`). Thus these tests neither prove bounded memory nor currently pass on this host. The production `OsCaptureBridge._copyIntoMedia` uses `File.copy` (`os_capture_bridge.dart:557-573`), which is separate source evidence for streaming behavior.
- The audit brief names `docs/NEX_V2_ROADMAP.md` as a lead, but that file is absent from this checkout; `docs/08-roadmap.md` is present. No conclusion was drawn from the missing document.

## Unverified risks

- The v1.20.1 touch baseline is recorded above. No APK from the current checkout was produced, so whether it reproduces the real-device editable-handle reversal remains **UNVERIFIED**. Code and widget tests cannot substitute for that observation.
- `NexBackupArchive.restore` reads the entire `.nexbak` into a byte list before ZIP decoding (`packages/data/lib/schema/backup_archive.dart:131`), whereas creation uses a file encoder (`backup_archive.dart:69-96`). Peak memory and behavior with a multi-gigabyte media archive on an old Android device are **UNVERIFIED**; source review indicates memory consumption scales with archive size, but I did not force an out-of-memory restore.
- The `npm ci` audit counts and backend IPv6 limiter diagnostics are evidence to investigate, not a demonstrated exploitable path in this audit.

## Environmental limitations

- The full local gate is red on Windows. The 12 failures must be triaged on the CI host or reproduced in isolation before claiming release verification. `make check` did not reach backend and worker; their targets passed when invoked explicitly.
- An Android emulator was available and v1.20.1 ran on it, but the current checkout could not be installed because the Android build did not complete under this host's restricted and intermittent Maven access. No claim about a current-build gesture, startup, or migration was made from that previous APK.
- Dependencies came from a reachable mirror after the primary hosts denied access. The exact committed lockfile graph, signed release build, live provider calls, real prior APK upgrade, and actual multi-year library remain unverified.

## Release decision

**Report:** `C:\Github\DbsNex\NEX_RELEASE_AUDIT.md`

**Summary:** The required local gate fails, a restore failure can replace live notes, and capture can lose an uncommitted edit. Android v1.20.1 provided a touch baseline; the current-build result and remaining runtime limits are stated above.

**DO NOT SHIP** — a failed backup restore can overwrite newer live data without completing.
