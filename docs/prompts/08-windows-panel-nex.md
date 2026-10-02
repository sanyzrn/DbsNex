# Task: Take Nex for Windows from preview to a dependable everyday app

You are continuing work on **Nex for Windows**, the Windows counterpart of the
Nex Android app. A previous agent built it as a Flutter port of the Right
Panel edge panel (`github.com/raminturne/right-panel`, MIT), then wired in
Nex's own packages. The current state lives in a standalone repository:

- **Windows working repository:** `github.com/sanyzrn/Nex_windows_test`,
  branch `main`, release `v0.10.0` (desktop app version `0.10.0+6`).
- **Nex upstream (the source of truth):** `github.com/sanyzrn/DbsNex`, branch
  `main`. At the time of writing, `main` is commit
  `7741fb2b912aa241627d5c695d1c4d94bfab03ed`, and the Android app is
  version **1.93.0**.

Nex is a local-first, Persian-first capture and notes app. Android ships;
Windows is a preview. Your job in this round is to make the Windows app
**current with upstream, structurally clean, closer to Android parity and
measurably dependable**, so the Nex maintainers can move it into the main
repository as `apps/desktop` and finish it there.

Structure, correctness and honest hand-off notes matter more than the
number of features. A smaller set of finished, tested work is worth more than
a long list of half-done items.

---

## 1. Access and how you work

- You have **read-only** access to both repositories. You can clone and
  browse them. You **cannot** push, open branches, pull requests, issues or
  comments, run their CI, or publish releases. You cannot reach the
  maintainers during the task.
- Clone both. Record both starting commit SHAs. Everything you deliver is
  based on those two commits.
- If you cannot read `Nex_windows_test`, stop and say so. If you cannot read
  `DbsNex`, continue on the packages vendored in `Nex_windows_test`, skip
  work package 1, and say so at the top of `HANDOFF.md`. Do not guess at
  upstream APIs.
- You deliver **one zip file** (section 8). The owner unpacks it, builds it
  on Windows and decides what to keep.
- Write all documentation, code comments, commit-style notes and reports in
  **English**. User-visible strings go through the ARB files in both `en` and
  `fa` (section 4).

---

## 2. What you are starting from

Read this section, then confirm it against the code. If the code and this
section disagree, **the code wins**, and you note the difference in
`HANDOFF.md`.

### 2.1 Layout of `Nex_windows_test`

| Path | Contents |
| --- | --- |
| `apps/desktop/` | The Flutter app. The Dart package is still named `right_panel`; the product, window and executable are "Nex" / `nex_desktop.exe`. |
| `apps/desktop/lib/core/` | Shell: `controller.dart` (about 1,600 lines; `PanelController`), springs, native FFI/method-channel wrapper (`native.dart`), shell settings storage, utility registry, world clock. |
| `apps/desktop/lib/nex/` | The Nex layer. `store.dart` runs one database isolate with a FIFO command queue over `NexDatabase`, `SqliteNoteRepository`, `SqliteThreadRepository`, `CaptureService`, `TagService` and `LibraryMaintenance`. `features.dart` (about 1,400 lines) holds `NexFeatures`, the capture view, the library view and note detail. `settings.dart` holds Nex settings. |
| `apps/desktop/lib/ui/` | `shell.dart` (the edge panel), `window_shell.dart` (the full desktop window, main mode since 0.10.0), dock, flyout, widgets and utility views. |
| `apps/desktop/windows/runner/` | The C++ runner. `native_bridge.cpp` (about 1,450 lines) covers tray, hotkeys, edge watch, window mode, clipboard, pickers, startup, single instance and display changes. |
| `apps/desktop/installer/` | Inno Setup script (`nex.iss`), Persian messages and README. |
| `apps/desktop/tools/` | `build_installer.ps1`, `windows_smoke.ps1`, `generate_utility_strings.py`. |
| `apps/desktop/test/` | Widget, regression, store, window-shell and golden tests, plus 10 golden PNGs. |
| `packages/{core,data,ui,ai}` | Copies of the Nex packages from upstream commit `4861feac41530c951cb9e637ff921c6472d7de58` (Android 1.92.1). They carry two shared changes: `FullBackup` moved into `packages/data/lib/schema/full_backup.dart`, and the theme presets moved into `packages/ui/lib/tokens/nex_theme_presets.dart`. Their pubspec SDK constraints were loosened to `>=3.9.0` with no upper bound. |
| `patches/` | The two shared changes as diffs against upstream `4861fea`, kept for integration into `DbsNex`. |
| `README.md` (Persian), `HANDOFF.md`, `TEST_RESULTS.md` | Owner-facing notes, agent hand-off and validation history. |

### 2.2 What already works (per the previous hand-off)

- **Two interface modes over one app:**
  - the window mode (main): resizable, with a navigation rail for Capture,
    Library, Tools and Settings, and a persisted frame;
  - the original liquid edge panel (optional, switchable at runtime).

  Both modes share one controller, one store, one capture session and one
  settings file.
- **Capture:** immediate text and checklist capture saved on every change
  (no Save button), image, audio and file choosers, clipboard image paste,
  drag and drop, and content-addressed media copy.
- **Library:** a lazy timeline (50 rows per page) with day headers and Nex
  `NoteCard`s; pin, delete with undo, and trash; an inline reader with an
  explicit edit mode.
- **Search, tags and threads:** search uses the Nex query parser and FTS,
  with type, tag and thread filters. Tags and threads can be created,
  attached and browsed.
- **Appearance and language:** Nex theme presets and tokens; Persian (the
  default) and English; Vazirmatn and Inter fonts; the Persian calendar.
- **Backup:** full-backup export in Nex's format. There is no restore UI.
- **Voice:** WAV recording and playback. Microphone recording has not been
  tested on hardware.
- **Shell:**
  - tray, global hotkeys and start with Windows;
  - single instance and edge or monitor selection;
  - DPI and display-change handling;
  - owned native workers and a clean shutdown.

  The spring constants are preserved.
- **Repairs to keep:** the 0.9.0 and 0.10.0 fixes must not regress:
  - an invisible panel;
  - dead clicks under a transformed flyout;
  - unwanted auto-hide while typing, reading, using pickers or recording;
  - honest messages for cancel and failure;
  - clipboard Clear keeping pinned entries;
  - failed voice import keeping the WAV.

### 2.3 What is missing or weak (per the previous hand-off, plus a surface review)

- **Parity gaps:**
  - reminders and Windows toasts;
  - a backup restore UI;
  - link notes with page preview;
  - recurring items (commitments);
  - import (Google Keep, a folder of `.md`/`.txt`);
  - draft recovery parity;
  - vault, assistant, sync, OCR and on-device AI.
- **The vendored packages are stale.** Upstream has moved from 1.92.1 to
  1.93.0 in eight commits, several of which change `packages/*` (section 5,
  work package 1).
- **Shared patch 02 will no longer apply cleanly** to upstream `main`:
  `apps/client/lib/platform/theme_presets.dart` changed in 1.93.0 (it gained
  a `textButtonTheme`).
- **Naming and version strings disagree** across the docs:
  - the Dart package is still `right_panel`;
  - `TEST_RESULTS.md` and the desktop README mix installer names `1.92.1.x`,
    `0.9.0` and `0.10.0`.
- **Three files are too large to review safely:** `controller.dart`,
  `features.dart` and `native_bridge.cpp`.
- **Golden tests fail on Linux** because of font rasterisation. They are only
  meaningful on Windows, which no automated check enforces.
- **Not measured or not validated:**
  - hotkey-to-usable latency;
  - smooth scrolling with 10,000 notes;
  - mixed-DPI and hot-plug;
  - live microphone;
  - clipboard image formats other than CF_DIB and CF_DIBV5;
  - picker shutdown races;
  - the window-mode C++ changes, which were reviewed but not compiled by the
    previous agent.

---

## 3. Read before you write any code

In `Nex_windows_test`:

1. `README.md`, `HANDOFF.md`, `TEST_RESULTS.md`.
2. `apps/desktop/README.md` (architecture, parity matrix, limits).
3. `apps/desktop/lib/main.dart`, `lib/nex/store.dart`, `lib/nex/features.dart`,
   `lib/ui/window_shell.dart`, `lib/core/controller.dart`,
   `lib/core/native.dart`, `windows/runner/native_bridge.cpp`.
4. `apps/desktop/test/*` and `apps/desktop/installer/nex.iss`.

In `DbsNex` at `main`:

1. `README.md`.
2. `docs/04-architecture.md`, `docs/05-design.md`, `docs/09-ai.md`.
3. `docs/10-decisions.md`. These are the ADRs. **They are binding.** ADR-001,
   ADR-002 and ADR-035 matter most here, plus every ADR on storage, media,
   sync readiness and the vault.
4. The package entry points: `packages/core/lib/nex_core.dart`,
   `packages/data/lib/nex_data.dart`, `packages/ui/lib/nex_ui.dart`,
   `packages/ai/lib/nex_ai.dart`.
5. How Android uses them: `apps/client/lib/app.dart`,
   `apps/client/lib/platform/nex_services.dart`,
   `apps/client/lib/platform/db_worker.dart`,
   `apps/client/lib/platform/reminders.dart`,
   `apps/client/lib/platform/full_backup.dart`,
   `apps/client/lib/platform/link_reader.dart`,
   `apps/client/lib/platform/note_copy.dart`,
   `apps/client/lib/platform/editor_drafts.dart`,
   `apps/client/lib/platform/capture_journal.dart`.
6. `CHANGELOG.md` entries `v1.92.2` through `v1.93.0`. They list what Android
   gained since the Windows base.

Then, before you implement anything, write a short **Plan** section at the
top of `apps/desktop/README.md`. It contains:

- the upstream changes that affect the desktop app and how you will absorb
  them;
- the work packages you will do, in order, each with its acceptance check;
- what you will deliberately **not** do this round, and why.

---

## 4. Rules you must not break

### Nex rules (from the ADRs; the repository wins on any conflict)

1. **Local-first, one store.**
   - SQLite through `nex_data`'s repositories is the only note store: same
     schema, same migrations and the same note model as Android (UUIDv7 ids,
     content-addressed media, revisions, tombstones and change tracking).
   - Do not create JSON note files, a second database or a parallel note
     model. Shell preferences, utility snippets and clipboard history stay
     separate from notes and never become notes implicitly.
   - Data written by Windows must be syncable later over Nex's existing
     push/pull protocol without migration.
2. **Capture never waits.**
   - No mandatory fields and no Save button for quick capture.
   - A note exists as soon as it has content (ADR-001, ADR-002).
   - No capture path waits on the network, AI or a dialog.
3. **AI is optional and removable** (ADR-035).
   - At most **one** file in `apps/desktop/lib` may import `nex_ai`.
   - The app must build, test and run with that file and the `nex_ai`
     dependency removed. Prove it with a test or a script.
4. **Persian first.**
   - Every user-visible string goes in `apps/desktop/lib/l10n/app_en.arb` and
     `app_fa.arb`, then through `flutter gen-l10n`.
   - Use Vazirmatn and Inter as in Nex.
   - User text takes its direction from its content (`nexDirectionOf`,
     `NexTextSurface`).
   - The whole UI mirrors in RTL, while a physical panel edge stays the edge
     the user chose.
   - Persian copy uses the polite «شما» register and Nex's terms: «یادداشت»,
     «برچسب», «رشته», «یادآور», «عقب‌افتاده», «سرویس».
   - Persian digits appear wherever the Persian UI shows numbers (`nexDigits`).
5. **The vault's data never enters** the notes database, search, AI context,
   clipboard history, notifications or logs.
6. **No secrets in the binary.** Any key comes from the user and goes to
   Windows secure storage.
7. **One source of domain truth.**
   - Do not copy Nex schema, search, merge, backup codec or theme tokens into
     `apps/desktop`.
   - If the desktop needs something that lives only in `apps/client`, prefer
     moving it into a package (delivered as a patch, section 8). Re-implement
     only a thin UI piece locally, and list it under "Duplication to resolve".

### Windows app rules

8. **The spring constants and the liquid shell stay** in panel mode: slide
   `320/38`, grow `340/24`, vertical flyout `380/30`, pill travel `420/26`,
   pill stretch `380/22`, icons `380/25`, hover `500/30`, press `700/28`.
9. **Do not regress the 0.9.0 and 0.10.0 repairs** (section 2.2). Each has a
   test. Keep those tests and keep them meaningful.
10. **The Windows version is independent of Android.**
    - This round produces **`0.11.0+7`**. Never use the Android version
      number for Windows.
    - The version must be identical in these five places:
      - `pubspec.yaml`;
      - the About screen;
      - the executable's version resource (`Runner.rc`);
      - the installer (`nex.iss`, output file name);
      - `README.md`.
11. **Keep the installer's AppId and the data paths unchanged**, so an update
    keeps existing notes, media and settings. If a migration of shell
    settings is needed, it must read the old format.
12. **Honesty.** Never report a check you did not run as passed. Keep
    historical results as history, clearly labelled with the version and
    toolchain they belong to. "Not run", "not measured" and "compiled by
    review only" are acceptable answers. A wrong PASS is not.

---

## 5. Work packages, in priority order

Do them in this order. Finish and test each before starting the next. If
time runs out, stop at a clean boundary and say where you stopped.

### WP1. Bring the app onto current upstream (DbsNex `main`, 1.93.0)

**Goal:** the desktop app builds and passes its tests on the packages exactly
as they are on upstream `main`, plus only the shared moves it needs.

1. Replace `packages/core`, `packages/data`, `packages/ui` and `packages/ai`
   with upstream `main`'s versions verbatim. Then re-apply only the two
   shared moves (backup and theme presets).
2. Restore upstream's pubspec SDK constraints (`sdk: ^3.9.0`,
   `flutter: ">=3.35.0 <4.0.0"`). They already allow the owner's Dart 3.12
   and Flutter 3.44; loosening them is unnecessary drift. If something truly
   requires a change, deliver it as a patch with the reason.
3. Regenerate both shared patches against upstream `main` so that
   `git apply --check` passes from the `DbsNex` root at your recorded SHA.
   - Patch 02 must keep the `textButtonTheme` that 1.93.0 added to
     `nex_theme_presets`. Patch 02 will otherwise conflict.
   - Keep Android behaviour identical: `apps/client` re-exports or imports
     the moved files, and Android tests must not need changes.
4. Absorb each upstream change below and record in the Plan what you did
   about each. Verify each one in the code; this list is a guide, not a
   specification.

   | Upstream change | What the desktop must do |
   | --- | --- |
   | Persian search folding (`nexSearchFold`, `nexSearchIndexText` in `packages/core/lib/search/search_fold.dart`; folded FTS index in `packages/data`, rebuilt once on first open) | Opening an existing 0.10.0 database must run the migration once and keep every note searchable. Test with a database created by the 0.10.0 code path. Search for «كتاب» and «کتاب», with and without the ZWNJ, must find the same notes. The old README's "ي/ك not normalized" limitation goes away; update the docs. |
   | Transactional write pairs (`together` in `packages/data/lib/schema/write_lock.dart`), export v2 with reminders, recurring items and threads, `idx_notes_timeline` | Use the repository APIs as Android does. Do not open your own transactions around them. Export from Windows must include reminders, recurring items and threads, and must import on Android. |
   | `Note.displayText`: a link's caption now outranks the page title | No desktop work beyond using `displayText`. Verify that link cards follow it. |
   | `nex_ui` contrast work: `nexContrast`, `nexReadableOn`, dark error colour, text-button and link contrast, accent clamping, `fontFamilyFallback` Inter↔Vazirmatn | Use the themes from `nexLightTheme` / `nexDarkTheme` plus presets. Do not override `textButtonTheme`, error colours or font fallback in the desktop. Delete desktop overrides that fight them. |
   | `ChatAdapter.release()` in `packages/core` (and its LiteRT implementation) | Only relevant if you add the AI integration point. Any `ChatAdapter` you implement must implement it. |
   | ZIP extraction bounded by the declared entry size (`BoundedOutputFileStream`) | Restore (WP3.2) must go through Nex's extraction helpers, not its own unzip loop. |

5. Acceptance:
   - `flutter analyze` is clean for `apps/desktop`;
   - all non-golden tests pass on the new packages;
   - a test opens a database produced by the 0.10.0 store, upgrades it and
     finds every note by search;
   - both patches apply with `git apply --check` against `DbsNex` at your
     recorded SHA.

### WP2. Make the codebase reviewable

**Goal:** a maintainer can read, review and move the app without archaeology.
**There must be no behaviour change** in this package. Your tests prove it.

1. Rename the Dart package `right_panel` to `nex_desktop`. Update every
   import, test and generated file. Keep the executable name
   `nex_desktop.exe` and all data paths.
2. Split the three large files along their real seams, keeping public
   behaviour identical:
   - `lib/core/controller.dart`: panel geometry and springs, holds and
     auto-hide, utility state, hotkeys and tray events, window mode;
   - `lib/nex/features.dart`: capture, library and timeline, detail and
     reader, media import, and the `NexFeatures` state object;
   - `windows/runner/native_bridge.cpp`: tray, hotkeys, edge and placement,
     window mode, clipboard, pickers and dialogs, startup and single
     instance, worker lifetime. One `.cpp`/`.h` pair per concern, plus a
     thin dispatcher. Update `CMakeLists.txt`.

   Aim for files under about 500 lines, with a short header comment saying
   what each file owns.
3. Fix every current statement in the docs so names and versions agree with
   section 4, rule 10. Move old release narratives in `TEST_RESULTS.md` under
   a dated **History** heading, labelled with their own version and
   toolchain. Do not delete them.
4. Goldens:
   - keep them;
   - tag them so the default `flutter test` on non-Windows hosts skips them
     with a visible reason;
   - document the Windows-only command that runs and, deliberately,
     regenerates them;
   - never relax tolerances to make them pass.
5. Add `.github/workflows/desktop.yml` for the standalone repository
   (`windows-latest`). It runs:
   - `flutter pub get`;
   - `flutter analyze`;
   - `flutter test`, goldens included on Windows;
   - `flutter build windows --release`;
   - an AI-removed build that proves rule 3.

   You cannot run it. Write it carefully, mark it "not run" in
   `TEST_RESULTS.md`, and keep it free of secrets.
6. Acceptance: the same test count passes before and after the split, apart
   from new tests. `git diff --stat` for the split is explained in
   `HANDOFF.md`.

### WP3. Close the parity gaps that matter on a desktop

Implement these in this order. For each, write the design in two to five
sentences in the README before coding it.

#### 3.1 Reminders with real Windows notifications

- Use the same reminder data as Android: `dueAt` and `NoteRepeat` on the
  note, through the repositories. There is no separate reminder store.
- Notifications must be **durable**. A reminder set while the app is open
  must fire even if the app has since closed. An in-process `Timer` alone is
  not acceptable.
  - Use Windows scheduled toast notifications (`ToastNotifier.AddToSchedule`
    / `ScheduledToastNotification`), either through the native runner or
    through a maintained plugin that supports scheduling on Windows.
  - Justify the choice in the README.
- Toasts need an identity:
  - an AppUserModelID set on the process;
  - a Start-menu shortcut that carries the same AUMID, created by the
    installer;
  - the same AUMID in development builds where possible. Document what
    happens in an unpackaged `flutter run`.
- **Reconcile on every launch and after every change.** The scheduled set
  equals the set of future, non-deleted, non-completed reminders in the
  database:
  - past-due ones are shown once as overdue;
  - repeats schedule their next occurrence;
  - deleting or editing a note updates its schedule.

  Put this logic in pure Dart, with unit tests that use a fake scheduler.
- Toast activation (body click) opens Nex on that note, in either interface
  mode. Toast actions:
  - **Done** clears the reminder;
  - **Snooze 10 minutes** reschedules it.
- The reminder UI: a picker with the same quick choices as Android (later
  today, tomorrow morning, a date and time; repeat), plus reminder chips on
  cards and in the detail view. Persian calendar and digits apply when they
  are on.
- If you cannot make scheduled toasts work durably, ship nothing that
  pretends to. Leave the UI hidden behind a flag and document exactly what
  blocked you.

#### 3.2 Backup restore

- Add a restore flow for the Nex full-backup format (`FullBackup`, with the
  recovery key for the encrypted private settings):
  - choose a file;
  - say clearly what will be replaced;
  - restore into a staging area;
  - validate;
  - swap atomically;
  - roll back on any failure;
  - reopen the store.
- A backup made on Android must restore on Windows, and the other way round.
  Write one round-trip test per direction, using fixtures created with the
  packages' own writer.
- Restore must not touch shell preferences unless the backup carries the
  desktop's own settings entry. Say which entries the desktop reads and
  ignores.

#### 3.3 Link notes

- Capture a link (paste or type) as a link note. Read the page title and
  description **after** the note exists, never before.
- Reading must follow Android's `link_reader.dart` exactly:
  - read the stream only up to 256 KB, never buffering the whole response;
  - 8-second timeout;
  - HTML only;
  - Open Graph first, then `<title>`;
  - no third-party service.

  Prefer delivering a patch that moves `link_reader.dart` into a package
  over copying it. If you copy, list it as duplication.
- Link cards show the caption when there is one (comes from
  `Note.displayText`).

#### 3.4 Recurring items (commitments)

- Port the Android list, editor and calendar for the `Commitment` model in
  `packages/core/lib/models/commitment.dart`, through the existing
  repositories. Keep cadence labels identical; they live in the Android
  client today.
- In Persian, weekday choices start on Saturday («شنبه»), as on Android.

#### 3.5 Behaviour parity with Android 1.93.0

- **Markdown links** in notes follow only `http`, `https`, `mailto` and
  `tel`. Everything else is ignored, never handed to the shell.
- **Copy** follows Android's rule:
  - a caption wins;
  - otherwise the transcript or OCR text;
  - for a text, Markdown or `.docx` file note, the file's text rather than
    its name, capped like Android's `note_copy.dart`.
- **New checklists** are kept when the editor closes; there is no Capture
  button for them. Editing an existing checklist keeps an explicit Save and
  a discard question.
- **Long documents** in the reader must not stall the reveal animation in
  either mode. Lay out documents over about 8 KB after the transition, then
  fade them in.
- **Drafts:** an editor the app or the OS closed mid-edit reopens with its
  draft. Writes are coalesced (about 300 ms) rather than per keystroke, and
  flushed on exit and on window deactivate.

#### 3.6 Import (only if 3.1 to 3.5 are done)

- Import a Google Keep Takeout and a folder of `.md`/`.txt` through
  whatever import API the packages expose. Do not write a second parser.

**Out of scope this round:**

- assistant (keep the stub unless everything above is done);
- vault;
- LAN or cloud sync;
- OCR;
- on-device AI;
- an in-app updater.

List each under "Next steps" with what it would take.

### WP4. Window mode as a real desktop app

**Goal:** someone who never opens the edge panel can use Nex all day with
keyboard and mouse.

1. **Library layout.**
   - At widths of about 900 px and above, show two panes: the timeline list
     on one side and the reader or editor on the other, with a draggable
     divider whose position is persisted.
   - Below that width, use the current single-pane flow.
   - In RTL the panes mirror.
2. **Keyboard.** Add these shortcuts, all listed in a Help / Shortcuts screen
   and all localised:

   | Shortcut | Action |
   | --- | --- |
   | `Ctrl+N` | New note |
   | `Ctrl+Shift+N` | New checklist |
   | `Ctrl+F` | Search |
   | `Ctrl+L` | Library |
   | `Ctrl+,` | Settings |
   | `↑` / `↓` | Move selection in the list |
   | `Enter` | Open the selected note |
   | `Esc` | Close the reader, then clear search |
   | `Delete` | Delete, with an Undo snackbar and `Ctrl+Z` |
   | `Ctrl+P` | Pin |
   | `Ctrl+C` | Copy (by the copy rule) |

3. **Mouse.**
   - A right-click context menu on a card mirrors Android's hold menu
     actions.
   - `Ctrl`/`Shift`+click multi-select, with a bulk action bar (tag, thread,
     pin, copy, delete with one Undo).
   - Drag and drop onto the window creates notes, the same as the panel.
4. **Focus and accessibility.**
   - Visible focus rings at 3:1 or better.
   - Every icon button has a tooltip and a semantic label.
   - Narrator can read cards and the reader.
   - Windows high-contrast mode and text scaling up to 200% keep the layout
     usable.
   - Test the main flows with keyboard only.
5. **Window chrome.**
   - Follow the system light or dark setting when the theme is "system".
   - Use the Nex icon in the taskbar, Alt-Tab and tray.
   - The title shows "Nex".
   - Restore the frame across monitors as today.

### WP5. Measure, then harden

Report measured numbers; "not measured" is acceptable. Do not guess.

1. **Latency.**
   - Time from the global hotkey to a focused, typeable capture field, warm,
     in both modes. The target is under 150 ms.
   - Cold start to the first usable frame.
   - Measure with timestamps logged behind a diagnostics flag, never in
     normal use.
2. **Large library.**
   - Generate 10,000 notes with Nex's own capture APIs into a temporary
     database. Measure:
     - first page of the timeline;
     - scroll frame times;
     - search latency for a common word and for a Persian word.
   - Commit the generator as a test or a tool, not the database.
3. **Media.**
   - Large imports must not block short text writes behind them in the FIFO.
     Prepare media (copy, hash) outside the repository transaction, then
     commit briefly.
   - Add a test in which a 50 MB import and a text edit overlap and the text
     edit commits first.
4. **Shutdown and races.**
   - Closing the app with a picker open, mid-recording, mid-import or
     mid-backup must exit cleanly and lose nothing that was already
     committed.
   - Add tests where Dart can reach. Describe the native checks for the
     owner.
5. **Clipboard images.** Support PNG on the clipboard (the "PNG" registered
   format), in addition to CF_DIB and CF_DIBV5. Unknown formats show a clear
   message rather than nothing.

### WP6. Installer and release hygiene

1. `installer/nex.iss`:
   - version `0.11.0`;
   - the same AppId;
   - per-user install;
   - a Start-menu shortcut with the AUMID from WP3.1;
   - Persian and English;
   - uninstall keeps notes, media and settings unless the user ticks a
     clearly labelled box.
2. `Runner.rc`: product and file versions `0.11.0.7`, product name "Nex",
   company and copyright as in the current file.
3. `tools/build_installer.ps1` builds from a clean tree and prints the
   SHA-256 of the installer.
4. `apps/desktop/CHANGELOG.md` (new). Windows release notes in English,
   written for users, starting at `0.11.0`.

---

## 6. Quality bar

- `dart format` applied to files you touched. `flutter analyze` clean. No
  `print`. No hard-coded user-visible strings. No colours outside `nex_ui`
  tokens and the active `ThemeData`.
- **Tests.** Every new piece of logic has unit tests. Add widget tests for:
  - quick capture: type, close and reopen, note still there (both modes);
  - search, including Persian folding;
  - delete then undo;
  - the reminder reconciliation (fake scheduler);
  - the restore round trip;
  - link-reader capping (fake HTTP client streaming forever);
  - keyboard navigation in window mode;
  - the two-pane layout at 1200 px and the single pane at 700 px, in `en`
    and `fa`.
- The AI-removed build check from section 4, rule 3.
- **If you can run commands**, run:
  - `flutter pub get`, `flutter analyze` and `flutter test` in
    `apps/desktop`;
  - `make check` in a `DbsNex` checkout with your patches applied, to prove
    Android is unaffected;
  - on Windows, `flutter build windows --release`, the installer build and
    `tools/windows_smoke.ps1`.

  Put commands and real output summaries in `TEST_RESULTS.md`. If you cannot
  run something, say so plainly.
- **Native code you could not compile** is marked "compiled by review only".
  Each such change gets a short manual check for the owner.

---

## 7. Decisions you must not make alone

Leave these for the owner. Record each in `HANDOFF.md` under **Owner
decisions**, with your recommendation and its cost:

- which Right Panel utilities stay (calculator, units, colours, emoji,
  timers, media keys, app or folder pins, screenshot, and so on);
- whether the edge panel stays a supported mode after 1.0;
- the AUMID string and the notification display name;
- whether uninstall offers to delete data;
- whether the Windows app gets an in-app updater, and from where;
- the final Dart package and repository names once the app moves into
  `DbsNex`.

---

## 8. What to deliver: one zip file

Name: **`nex-windows-<YYYY-MM-DD>.zip`**. Layout:

```
nex-windows-<date>.zip
├── repo/                      # full source snapshot of Nex_windows_test after your work
│   ├── apps/desktop/          # app, tests, runner, installer, tools, README, CHANGELOG
│   ├── packages/              # upstream DbsNex main packages + the two shared moves
│   ├── patches/               # regenerated against DbsNex main (see below)
│   ├── .github/workflows/desktop.yml
│   ├── README.md              # Persian, owner-facing, updated to 0.11.0
│   ├── HANDOFF.md
│   └── TEST_RESULTS.md
├── upstream-patches/          # diffs against DbsNex at your recorded SHA
│   ├── 01-shared-backup.patch
│   ├── 02-shared-theme-presets.patch
│   ├── 03-<concern>.patch     # any further move into a package (e.g. link reader)
│   └── 04-desktop-ci.patch    # optional: a Windows job for apps/desktop in DbsNex CI
├── INTEGRATION.md             # exact steps to move repo/apps/desktop into DbsNex
└── SUMMARY.md                 # one page, see below
```

- **Exclude** build outputs and caches: `build/`, `.dart_tool/`, `.idea/`,
  `*.iml`, `windows/flutter/ephemeral/`, `pubspec_overrides.yaml`, any
  `.exe`, `.msi` or `.zip` inside the tree, and any database or user data.
  **Keep** `pubspec.lock` files and the golden PNGs.
- **Every patch** applies cleanly with `git apply --check` from the
  `DbsNex` root at your recorded SHA. Make them with `git diff`. Each patch
  touches one concern and keeps Android's behaviour and tests identical.
- **`INTEGRATION.md`** contains:
  - the base SHAs of both repositories;
  - the order to apply the patches;
  - the commands to copy `apps/desktop` into `DbsNex` with relative package
    paths unchanged;
  - the commands to verify (`make check`, desktop analyze and test);
  - what to delete from the standalone layout after the move.
- **`SUMMARY.md`** fits on one page:
  - what works now that did not before;
  - what is still missing;
  - the three things the owner should try first on Windows, with steps;
  - every check marked run / not run.
- **`HANDOFF.md`** (inside `repo/`) replaces the old one. It contains:
  - product goal and current stage;
  - the version (`0.11.0+7`) and both base SHAs;
  - architecture in brief;
  - each work package with status;
  - known bugs;
  - "Duplication to resolve";
  - **Owner decisions**;
  - next steps.

  Keep the previous hand-off text under a **History** heading at the end.

If anything in these instructions conflicts with what you find in either
repository (an ADR, a package API, the schema, the runner), **the repository
wins**. Follow it, and note the conflict in `HANDOFF.md` rather than working
around it.
