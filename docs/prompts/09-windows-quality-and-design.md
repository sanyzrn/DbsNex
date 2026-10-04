# Task: Make Nex for Windows correct, honest and genuinely good to look at

You are continuing work on **Nex for Windows**, the Windows counterpart of the
Nex Android app. The previous round (0.11.0) added a lot: reminders with
Windows toasts, backup restore, link notes, recurring items, a two-pane
window mode, keyboard shortcuts and a split native runner. It also left the
documentation contradicting itself, the vendored packages behind upstream,
files far larger than the round claimed, and **an interface full of visual
bugs and inconsistencies**.

This round is a **quality round**. You are not judged on how many features
you add. You are judged on:

- how many real defects you find and fix, with proof;
- how much better every screen looks and feels, in both languages and both
  themes;
- how honest your hand-off is.

"Finished" here does not mean "the listed items are ticked". It means you
went through every screen and every work package, found what is wrong
beyond the list, and kept improving until the definition of done
(section 9) holds. **Do not stop early.** If you reach the end with time
left, run the audit loop again (section 5, WP2.1). A second pass always
finds more.

- **Windows working repository:** `github.com/sanyzrn/Nex_windows_test`,
  branch `main`, commit `5f2072e5c7c8d869e76e6fda563d7cbf7995e117`
  (desktop app `0.11.0+7`).
- **Nex upstream (the source of truth):** `github.com/sanyzrn/DbsNex`,
  branch `main`, commit `b00fcddf50ddee90231f6753b4fed7d8b3a9e250`. The
  Android app there is **1.93.3**.
- **This round produces Windows `0.12.0+8`.**

---

## 1. Access and how you work

- You have **read-only** access to both repositories. You can clone and
  browse them. You **cannot** push, open branches, pull requests, issues or
  comments, run their CI, or publish releases. You cannot reach the
  maintainers during the task.
- Clone both. Check that the two SHAs above still exist and record the ones
  you actually start from. Everything you deliver is based on those two
  commits. **Never write a SHA, tag or version you have not resolved
  yourself with `git rev-parse` or `git show`.** The previous round recorded
  a base commit that does not exist in `DbsNex` and a tag that was never
  created; that must not happen again.
- If you cannot read `Nex_windows_test`, stop and say so. If you cannot read
  `DbsNex`, continue on the vendored packages, skip WP1.3, and say so at the
  top of `HANDOFF.md`.
- You deliver **one zip file** (section 10). The owner unpacks it, builds it
  on Windows and decides what to keep.
- Write documentation, comments and reports in **English**. Every
  user-visible string goes through the ARB files in both `en` and `fa`. The
  owner-facing `README.md` at the repository root stays in **Persian**.

---

## 2. What you are starting from

The code wins over this section. Where they disagree, note it in
`HANDOFF.md`.

### 2.1 Layout

| Path | Contents |
| --- | --- |
| `apps/desktop/lib/core/` | `controller.dart` (about 1,330 lines; `PanelController`), springs, native wrapper (`native.dart`), panel geometry, holds, settings, window mode, storage, theme definitions, world clock. |
| `apps/desktop/lib/nex/` | The Nex layer: `store.dart` (database isolate), `features.dart` and `features_state.dart`, `capture_view.dart`, `library_view.dart` (about 1,245 lines), `note_detail_view.dart`, `settings.dart` (about 800 lines), reminders, reminder picker, commitments, link reader, note copy, shortcuts dialog. |
| `apps/desktop/lib/ui/` | `shell.dart` (edge panel), `window_shell.dart` (about 1,160 lines; window mode), dock, flyout, `widgets.dart` (about 820 lines), `views/` (clipboard, colour, emoji, more, and `small_views.dart` / `small_views2.dart` at about 920 and 780 lines). |
| `apps/desktop/windows/runner/` | The C++ runner, split into `native_common`, `native_startup`, `native_hotkeys`, `native_tray`, `native_window`, `native_clipboard`, `native_pickers`, `native_notifications`, plus `native_bridge`. |
| `apps/desktop/test/` | Unit, widget, regression, benchmark and golden tests. There are 10 golden PNGs, **all panel-mode at 480×680**. |
| `packages/{core,data,ui,ai}` | Vendored Nex packages, said to be from Android 1.93.0, plus two shared patches (`patches/01-shared-backup.patch`, `patches/02-shared-theme-presets.patch`). |
| `.github/workflows/desktop.yml` | Windows CI: analyze, test, goldens, release build, AI-removal check. |
| `docs/` | `HANDOFF.md`, `INTEGRATION.md`, `TEST_RESULTS.md`, `archive/`. |

### 2.2 Defects found in a review of 0.11.0 (you must fix all of these)

**Truth and documentation**

1. **The upstream base is recorded three different ways.**
   - Root `README.md` says DbsNex `4861feac…`, which is PR #290 (Android
     1.92.x).
   - `docs/INTEGRATION.md` says `3626d03d…` "tag v1.93.0". That commit does
     not exist in DbsNex, and DbsNex has no tags at all.
   - `CHANGELOG.md` says "1.93.0 at recorded SHA".

   Work out what the vendored packages really are by diffing them against
   DbsNex history. Then record one true base everywhere.
2. **`docs/TEST_RESULTS.md` contradicts `CHANGELOG.md`.** The test results
   end with "Reminders/toasts, … desktop backup restore UI … were not
   implemented". The changelog says both shipped. Rewrite the results so
   that every claim matches the code and is labelled with the version and
   toolchain it was observed on.
3. **"Modularized … under 500 lines per file" is false.** `controller.dart`,
   `library_view.dart`, `window_shell.dart`, `small_views.dart`,
   `widgets.dart`, `settings.dart` and `small_views2.dart` are all well over
   500 lines. Either make it true (WP4) or stop claiming it.

**CI**

4. **CI downloads packages from a mirror.** `desktop.yml` sets
   `PUB_HOSTED_URL: https://pub.flutter-io.cn`. GitHub-hosted runners do not
   need a mirror, and a third-party package source is a supply-chain risk.
   Use the default `pub.dev`.
   - Check that the pinned `flutter-version` exists and matches what the
     lockfile and the vendored packages need.
   - Pin it to the same Flutter stable that DbsNex uses (DbsNex `.fvmrc`,
     read by its `.github/workflows/ci.yml`), unless you can show a reason
     not to.

**Visual defects in the existing goldens**

These are visible in the existing golden images. Treat them as the first
entries in your audit (WP2), not as the whole audit.

5. **Settings shows its title twice.** The panel header says "Settings" and
   the page under it starts with a second, larger "Settings". The content is
   also cut off at the bottom of the panel with no fade and no visible
   scroll affordance.
6. **The panel card jumps between views.** Its top edge sits at about
   y=118 (capture), y=144 (emoji), y=80 (more) and y=10–13 (reader,
   settings), and its height changes with it. Switching views makes the
   card leap. Decide a rule and apply it to every view: a fixed anchor with
   a smooth height spring, kept within the springs in rule 8.
7. **The reader layout is broken.**
   - The edit pencil floats alone on the far side of the header row.
   - The action buttons wrap 2+2 at different widths: Copy, Pin, then
     Remind me, Delete.
   - Most of the panel is empty below "Tags and threads".
   - The metadata separator dot is nearly invisible.
   - In Persian the metadata line reads in a jumbled order:
     `۱۴۰۵/۰۷/۱۲ ۱۰:۰۴ • ۴ کلمه`. Date, time and word count need
     direction isolation (`Directionality` or `⁨…⁩`) so they read
     correctly in RTL.
8. **Light-mode capture actions are nearly invisible.** The six action
   tiles in light mode have almost no border or fill, while dark mode
   outlines them. Make the two themes the same component with
   theme-correct contrast (WCAG AA 4.5:1 for text, 3:1 for control
   boundaries).
9. **The capture "+" is unlabeled.** A bare "+" sits beside "Saved
   automatically on this device", with no tooltip and no label. Its purpose
   is not discoverable.
10. **The emoji panel has several defects.**
    - The search field's "→" button is tiny and misaligned.
    - The category icons are small and low-contrast.
    - The last row of emoji is cut in half at the panel edge with no fade.
11. **The "More" header is unpolished.** "TOOLS  drag a tile onto the dock"
    mixes an all-caps label with a sentence-case hint at two sizes on one
    baseline.
12. **The dock is inconsistent.** The active item is a filled circle while
    the inactive ones are rounded squares, and the active colour differs
    between themes: deep blue in light, pale blue in dark. Make it one shape
    language with one accent rule driven by the active Nex theme preset.

**Off-system styling**

13. **The UI does not use Nex's tokens.** Colour literals bypass them, for
    example the "emerald" `Color(0xFF10B981)` in `capture_view.dart`,
    `settings.dart` and `window_shell.dart`. There is also a hard-coded
    English `Text('No store')` in `window_shell.dart`.
    - Everything visual comes from `nex_ui` tokens and the active
      `ThemeData`.
    - Every string comes from the ARB files.

**Golden test limits**

14. **The goldens are not a faithful picture of the app.**
    - Flutter tests draw shadows as solid hard-edged blocks by default
      (`debugDisableShadows`). Every panel therefore shows a grey slab under
      its bottom edge in the goldens. That is a test artifact, not the real
      app.
    - For the review screenshots in WP2, render with shadows enabled, so
      that what the owner sees is what ships.
    - There are no window-mode goldens at all, and no golden at a larger
      text scale.

### 2.3 What changed upstream since the vendored packages

Read `CHANGELOG.md` in DbsNex from `v1.93.0` to `v1.93.3`. The changes that
touch the shared packages are:

- **Copy keeps line breaks.** `packages/ui` gained `NexSelectableLines`
  (`lib/widgets/nex_selectable_lines.dart`). `NexMarkdown` and
  `NexTextSurface` use it, so text selected and copied across several lines
  keeps its newlines.
- **New tag colours.** `packages/data` gained `tagAutoPalette` and
  `pickTagAccent`: a new tag gets the least-used of twelve colours.
- **Settings navigation on Android.** Settings became a list of categories,
  each with its own page, and language and calendar are chosen in place.
  These live in `apps/client` and are only a design reference for WP2.

---

## 3. Read before you write any code

In `Nex_windows_test`:

- `README.md`, `docs/*`, `apps/desktop/README.md`, `apps/desktop/CHANGELOG.md`;
- every file under `apps/desktop/lib/ui/` and `apps/desktop/lib/nex/`;
- `lib/core/controller.dart` and `lib/core/theme_defs.dart`;
- `test/golden_test.dart` and `test/flutter_test_config.dart`;
- `.github/workflows/desktop.yml`.

In `DbsNex` at the recorded SHA:

- `docs/05-design.md`, which is Nex's design language. **It is binding for
  look and feel.**
- `docs/10-decisions.md`, the ADRs, which are binding. The ones on capture,
  storage, AI removability, typing surfaces and Persian matter most.
- `packages/ui/lib/nex_ui.dart` and everything under
  `packages/ui/lib/tokens/` and `packages/ui/lib/widgets/`. This is the
  component and token set to build from.
- `apps/client/lib/screens/` as the reference for how Nex screens look and
  behave on Android. Match its craft, not its phone layout.

Then write a short **Plan** at the top of `apps/desktop/README.md`:

- what you will fix, in order;
- each work package's acceptance check;
- what you will deliberately not do this round, and why.

---

## 4. Rules you must not break

### Nex rules (from the ADRs; the repository wins on any conflict)

1. **Local-first, one store.**
   - SQLite through `nex_data` is the only note store: same schema, same
     migrations, same note model as Android.
   - No JSON note files, no second database, no parallel note model.
2. **Capture never waits.**
   - No mandatory fields and no Save button.
   - A note exists as soon as it has content.
   - Nothing on the capture path waits on the network, AI or a dialog.
3. **AI is optional and removable.**
   - At most one file in `apps/desktop/lib` imports `nex_ai`.
   - The app builds, tests and runs without it.
   - Keep the CI proof.
4. **Persian first.**
   - Strings live in `app_en.arb` and `app_fa.arb`.
   - Fonts are Vazirmatn and Inter.
   - User text takes its direction from its content (`nexDirectionOf`,
     `NexTextSurface`).
   - The whole UI mirrors in RTL, while a physical panel edge stays the edge
     the user chose.
   - Persian copy uses the polite «شما» register and Nex's terms.
   - Persian digits wherever the Persian UI shows numbers.
5. **The vault's data never enters** notes, search, AI, clipboard history,
   notifications or logs.
6. **No secrets in the binary.**
7. **One source of domain truth.**
   - Do not copy Nex schema, search, merge, backup or theme tokens into
     `apps/desktop`.
   - If something shared is missing, deliver it as a patch to a package
     (section 10).

### Windows app rules

8. **The spring constants and the liquid shell stay in panel mode:**
   - slide `320/38`, grow `340/24`, vertical flyout `380/30`;
   - pill travel `420/26`, pill stretch `380/22`;
   - icons `380/25`, hover `500/30`, press `700/28`.

   New motion you add must use springs or Nex's motion tokens, respect
   Windows "Show animations" (reduce motion), and never block input.
9. **Do not regress any earlier repair.** Every repair from 0.9.0, 0.10.0
   and 0.11.0 has a test. Keep those tests meaningful.
10. **Versions.**
    - The Windows version is independent of Android. This round is
      **`0.12.0+8`**.
    - It must be identical in `pubspec.yaml`, the About screen, `Runner.rc`,
      `nex.iss` (and the installer file name), `README.md` and
      `CHANGELOG.md`.
    - Add a test or script that fails when they disagree.
11. **Keep the installer AppId, the AUMID `Nex.Desktop.App` and the data
    paths unchanged.** An update must keep notes, media, settings and
    scheduled reminders.
12. **Honesty.**
    - Never report a check you did not run as passed.
    - "Not run", "not measured" and "compiled by review only" are acceptable
      answers. A wrong PASS is not.
    - Every number in a document is one you measured, with how and where.

---

## 5. Work packages, in priority order

Finish and test each before moving on. If time runs out, stop at a clean
boundary and say where.

### WP1. Truth, upstream and CI

1. **Reconcile the documents.** Fix items 1–3 of section 2.2.
   - `README.md`, `HANDOFF.md`, `INTEGRATION.md`, `TEST_RESULTS.md` and
     `CHANGELOG.md` must agree on every SHA, version and feature status.
   - Add a short **Claims audit** table to `HANDOFF.md`: each claim from the
     0.11.0 changelog with a verdict of true, partly true or false, and the
     evidence.
2. **Clean up CI.** Fix item 4 of section 2.2.
   - Remove the mirror and pin Flutter correctly.
   - Add a version-consistency step (rule 10).
   - Add a step that fails on `Color(0x` literals and hard-coded `Text('…')`
     strings outside an allowlist.
   - Upload the screenshot matrix of WP2 as a CI artifact on every run.
3. **Bring the packages up to upstream 1.93.3.**
   - Replace the vendored `packages/*` with DbsNex at the recorded SHA, then
     re-apply the shared changes.
   - Regenerate both patches so they pass `git apply --check` from the
     DbsNex root at that SHA.
   - Pick up `NexSelectableLines` wherever the desktop shows selectable note
     text (reader, detail, Markdown). Add a copy-keeps-newlines test, as
     DbsNex has in `packages/ui/test/nex_selectable_lines_test.dart`.
   - Pick up the new tag palette through `upsertTag`.

**Acceptance:** documents agree; CI is green on Windows with no mirror;
patches apply; analyze and test pass.

### WP2. Visual audit and redesign pass (the core of this round)

#### 2.1 The audit loop

Build a **screenshot harness**: a golden-style test, tagged `review`, that
renders every screen in this matrix and writes PNGs to `design/after/`.

- **Mode:** panel (left and right edge) and window (700, 1200 and 1600
  logical px wide).
- **Language:** `en` and `fa`.
- **Theme:** light and dark, and at least two other Nex presets.
- **Text scale:** 1.0 and 1.5.
- **States:** empty library, a library with 3 notes, a library with 500
  notes of mixed types, a long note, a note with a very long unbroken word
  or URL, a Persian-English mixed note, a checklist, a link note, a voice
  note, a file note, a photo note, an open reminder picker, an open context
  menu, multi-select with the bulk bar, the restore flow, the shortcuts
  dialog, every utility view, and every settings section.

Render with real shadows (`debugDisableShadows = false`) and the bundled
fonts. Before changing anything, render the same matrix from the starting
commit into `design/before/`.

Then loop:

1. **Audit.** Go through every screenshot and log every defect in
   `design/UI_AUDIT.md`. Each entry has:
   - an id;
   - the screen and matrix cell;
   - a severity: P1 (broken or unreadable), P2 (wrong or inconsistent), P3
     (polish);
   - one line describing it;
   - the cause in code (file and line);
   - its status.

   Look specifically for:
   - **Clipping and overflow:** any `RenderFlex overflowed`, text cut off,
     ellipsis where there is room, content under the dock or title bar.
   - **Alignment:** baselines, icon and text centring, unequal padding, grids
     whose items differ in width.
   - **Spacing:** values off the 4/8 grid or off Nex spacing tokens;
     different gaps for the same relationship.
   - **Type:** sizes and weights off the scale; two type ramps on one
     screen; Persian line height too tight; numbers in Latin digits in `fa`.
   - **Colour:** contrast below AA; literals; hover, pressed, focused and
     disabled states that look the same or are missing; light and dark
     drawn differently for the same component.
   - **RTL:** icons that should mirror (back, chevrons, send) and ones that
     must not (play, clock, checkmarks); mixed-direction lines;
     `EdgeInsets` instead of `EdgeInsetsDirectional`; alignment `left` or
     `right` instead of `start` or `end`.
   - **Scale:** every view at 1.5× text scale and at 150% and 200% Windows
     DPI.
   - **Consistency:** the same action looks the same everywhere (copy, pin,
     delete, remind); one button hierarchy (primary, secondary, tertiary,
     destructive); one corner radius set; one icon set and weight.
   - **Motion:** jumps, layout pops, card position leaps (item 6), spinners
     where content could appear progressively.
   - **Empty, loading and error states:** every list and every async action
     has all three, written in Nex's voice.
2. **Fix** every P1 and P2. Fix P3s where cheap.
3. **Re-render** and check the fix in every matrix cell it touches. A fix
   that breaks another cell is not a fix.
4. **Repeat** until the audit has **no open P1 or P2**. Then do one more full
   pass looking only at consistency across screens.

`UI_AUDIT.md` must show the before and after image path for every fixed
entry. The 14 defects in section 2.2 are the first entries, not the target.
**A thorough audit of this app will find many more.** Expect dozens, and
report the real number.

#### 2.2 Design direction

The window mode is now the main experience. It should feel like a
first-class Windows 11 app that is unmistakably Nex, not a phone layout
stretched to a monitor.

- **System.** Build every surface from `nex_ui` tokens and components.
  - If a component the desktop needs is missing from `nex_ui`, add it there
    as a patch (section 10). Do not hand-roll it in `apps/desktop`.
  - One spacing scale, one radius set, one elevation scale, one type ramp,
    one icon weight.
- **Windows 11 integration.**
  - Mica or acrylic backdrop where supported, falling back cleanly on
    Windows 10.
  - A custom title bar that keeps snap layouts (hover on maximise), drag
    and double-click to maximise, with correct RTL placement of controls.
  - Visible keyboard focus rings everywhere.
  - Tooltips on every icon-only control, with its shortcut.
  - Right-click menus that look like the rest of the app.
- **Window mode layout.**
  - A clear three-zone structure: navigation rail, list, reader or editor.
  - A resizable splitter with sensible minimums.
  - The reader uses the available height and width. Long notes read at a
    comfortable measure (about 70 characters), centred, not stretched
    edge to edge.
  - Actions live in one consistent toolbar, not in wrapped rows of
    unequal buttons.
- **Panel mode.** Keep the liquid shell. Fix the card anchoring (item 6), the
  header patterns and the per-view inconsistencies. The panel must look
  like the same product as the window.
- **Typography.** Inter for Latin and Vazirmatn for Persian.
  - Check Persian line heights and the weights that read well on Windows
    ClearType at 100% and 150%.
  - Numbers use tabular figures where they line up in columns (timers,
    world clock, dates in lists).
- **Voice.** Every string reads like Nex on Android: short, plain and
  specific. Compare the `fa` strings against `apps/client/lib/l10n/app_fa.arb`
  in DbsNex and align the terms.

#### 2.3 Creative improvements (required)

Beyond fixing defects, design and implement improvements that make the app
better to use every day. Propose at least **eight** in `design/IDEAS.md`,
each with the problem, the design and its cost. Implement at least **five**
of them, each with tests and before/after screenshots.

Choose ones that fit Nex's principles: capture first, calm, local, Persian
first. Starting points (you are not limited to these):

- **Command palette (`Ctrl+K`):** search notes, jump to any screen or
  setting, run any action, with Persian-folding search.
- **Quick capture from anywhere** that opens instantly with the cursor in
  the field. Show the measured latency in the hand-off.
- **Paste-to-note intelligence:**
  - a pasted URL becomes a link note with its preview;
  - a pasted image becomes a photo note;
  - pasted Markdown keeps its structure.
- **Drag a note out** to Explorer or another app as a `.md` or its media
  file, and drag files in with a clear drop target.
- **A Today strip** at the top of the library: due and overdue reminders,
  and recurring items due today, matching Android's overdue language.
- **Inline tag and thread chips** with keyboard completion (`#` and `>`)
  while typing.
- **A designed empty library:** a calm first-run state with three concrete
  first actions, in both languages.
- **Settings search and category pages** that mirror Android 1.93.2 and
  1.93.3, adapted for the desktop.
- **Thoughtful micro-interactions:** pin, delete and undo, copy confirmation
  and reminder set, each with a subtle, fast and interruptible animation.
  All of them respect reduce-motion.
- **Density modes** (comfortable and compact) for the library list in window
  mode.

Do not add features that break a rule in section 4. In particular, nothing
on the capture path may wait on the network or AI.

### WP3. Screen-by-screen depth pass

For each screen, list in `HANDOFF.md` what you verified and changed:
capture, library and list, reader, editor, search and filters, tags and
threads, reminders and the picker, recurring items, settings (every
section), backup and restore, shortcuts dialog, tray menu, every utility
(calculator, timer, stopwatch, search, snippets, text tools, media, world
clock, generate, password, units, folders, keep awake, pin window,
clipboard, colour, emoji).

For each one, check:

- keyboard-only use;
- screen reader names and roles (Narrator);
- `en` and `fa`;
- light and dark;
- text scale 1.5;
- empty, loading and error states;
- that no action can lose data without undo or a confirmation.

### WP4. Make the code match its claims

- Split the files over 500 lines from section 2.1 into cohesive units, so
  that no file in `apps/desktop/lib` exceeds 500 lines except generated
  l10n.
  - Behaviour must not change.
  - The tests and goldens prove it.
- Remove the colour literals and hard-coded strings (item 13). Enforce both
  in CI (WP1.2).
- Tighten `analysis_options.yaml` toward DbsNex's lints. Fix what it finds.
- Remove dead code, unused assets and stale docs. Move superseded docs to
  `docs/archive/` with a one-line note on what replaced them.

### WP5. Measure, then harden

Replace "not measured" with numbers where you can. For each measurement,
record the method and the machine.

- **Global hotkey to a focused, typeable field (warm):** target under
  150 ms. Instrument it, measure 20 runs, report the median and p95.
- **Window-mode library with 10,000 notes:** report frame build and raster
  times while scrolling, and the first-frame time on open.
- **Cold start to first frame**, in both modes.
- **Memory** after 10 minutes of use with 10,000 notes.

Then work through the manual checklist in `docs/TEST_RESULTS.md`. Automate
what can be automated:

- clipboard round trips with real formats;
- file drop through a simulated OLE drop where feasible;
- picker shutdown races with a fake picker;
- multi-monitor and DPI geometry with pure geometry tests.

What remains manual gets precise owner steps.

### WP6. Accessibility

- Every interactive control has a semantic label, a role and a visible
  focus state, and is reachable by Tab in a sensible order, in both
  directions of reading.
- Contrast meets WCAG AA in every preset, light and dark. Add an automated
  contrast check over the theme tokens.
- **Windows High Contrast mode:** the app stays usable and readable. Take a
  screenshot.
- **Text scale up to 2.0:** nothing clips.

### WP7. Release hygiene

- `0.12.0+8` everywhere (rule 10), with an honest `CHANGELOG.md` entry
  written for users, in the style of DbsNex's `CHANGELOG.md`.
- The installer builds, upgrades over 0.11.0 and keeps data and reminders.
  Write precise steps for the owner to verify.
- Update `README.md` (Persian, owner-facing) with what is new, how to
  install, and the three things to try first.

---

## 6. Quality bar

- `dart format` on touched files. `flutter analyze` is clean. No `print`.
- **Every fix has a test that fails without it.** That can be a widget test,
  a golden, a unit test or the contrast check.
- **Goldens.**
  - Keep the existing ones meaningful.
  - Add window-mode goldens (1200 px, `en` and `fa`, light and dark) for
    capture, library, reader, settings and the command palette if you build
    it.
  - Goldens run on Windows in CI. The `review` screenshot matrix runs too
    and is uploaded as an artifact, but does not gate CI.
- The AI-removal check stays green.
- **If you can run commands**, run:
  - `flutter pub get`, `flutter analyze` and `flutter test` in
    `apps/desktop`;
  - `make check-dart check-ai check-ui` in a DbsNex checkout with your
    patches applied, to prove Android is unaffected;
  - on Windows, `flutter build windows --release`, the installer build and
    `tools/windows_smoke.ps1`.

  Record the commands and real output summaries in `TEST_RESULTS.md`.
- Native code you could not compile is marked "compiled by review only",
  with a manual check for the owner.

---

## 7. Decisions you must not make alone

Record each in `HANDOFF.md` under **Owner decisions**, with your
recommendation and its cost:

- which Right Panel utilities stay after 1.0;
- whether the edge panel remains a supported mode after 1.0;
- whether uninstall offers to delete data;
- an in-app updater, and its source;
- any change to the information architecture beyond what Android already
  has, for example new top-level sections.

Visual and interaction decisions inside Nex's design language are yours.
Make them, explain them in `design/DECISIONS.md`, and move on.

---

## 8. How to work so the result is good

- **Look before you fix.** Render the before matrix first. Most visual bugs
  are only obvious in a screenshot, not in code.
- **Fix causes, not cells.** If five screens have the same spacing bug, the
  fix is in the shared component, not in five places.
- **Re-render after every change** to a shared component, and check every
  cell it touches.
- **Prefer fewer, better components.** When two widgets do the same job,
  merge them.
- **Write down what you rejected** in `design/DECISIONS.md`, and why.
- **Keep going.** When the list in this prompt is done, go back to the audit
  loop. There is no reward for stopping early, and the owner will open every
  screen.

---

## 9. Definition of done

All of these must be true, and `SUMMARY.md` says which are not:

1. Every defect in section 2.2 is fixed, with proof.
2. `design/UI_AUDIT.md` has **no open P1 or P2**, and lists the real number
   of defects found and fixed.
3. At least five improvements from `design/IDEAS.md` are implemented and
   tested.
4. No file in `apps/desktop/lib` exceeds 500 lines (generated l10n
   excepted). There are no colour literals or hard-coded strings, and CI
   enforces both.
5. The documents agree with each other and with the code, and every SHA in
   them resolves.
6. The packages match DbsNex at the recorded SHA, and the patches apply
   cleanly.
7. CI is green on Windows with no package mirror.
8. Version `0.12.0+8` appears in every place in rule 10, and a check
   enforces it.
9. Every performance number is measured, or explicitly "not measured", with
   the reason.

---

## 10. What to deliver: one zip file

Name: **`nex-windows-0.12.0-<YYYY-MM-DD>.zip`**. Layout:

```
nex-windows-0.12.0-<date>.zip
├── repo/                      # full source snapshot of Nex_windows_test after your work
│   ├── apps/desktop/          # app, tests, runner, installer, tools, README, CHANGELOG
│   ├── packages/              # DbsNex packages at the recorded SHA + shared changes
│   ├── patches/               # regenerated against DbsNex at the recorded SHA
│   ├── .github/workflows/desktop.yml
│   ├── README.md              # Persian, owner-facing
│   └── docs/                  # HANDOFF.md, INTEGRATION.md, TEST_RESULTS.md, archive/
├── design/
│   ├── before/                # screenshot matrix at the starting commit
│   ├── after/                 # the same matrix after your work, same file names
│   ├── UI_AUDIT.md            # every defect: id, cell, severity, cause, fix, before/after
│   ├── IDEAS.md               # 8+ improvements: problem, design, cost, status
│   └── DECISIONS.md           # design decisions and rejected alternatives
├── upstream-patches/          # diffs against DbsNex at the recorded SHA
│   ├── 01-shared-backup.patch
│   ├── 02-shared-theme-presets.patch
│   └── 03-<concern>.patch     # any nex_ui component or package change you needed
├── INTEGRATION.md             # how to move repo/apps/desktop into DbsNex
└── SUMMARY.md                 # one page
```

- **Exclude:**
  - build outputs and caches: `build/`, `.dart_tool/`, `.idea/`, `*.iml`,
    `windows/flutter/ephemeral/`;
  - `pubspec_overrides.yaml`;
  - any `.exe`, `.msi` or `.zip` inside the tree;
  - any database or user data.
- **Keep:** the `pubspec.lock` files, the golden PNGs and the `design/`
  images.
- **Patches:** each applies cleanly with `git apply --check` from the DbsNex
  root at the recorded SHA, touches one concern, and leaves Android's
  behaviour and tests unchanged.
- **`SUMMARY.md`** fits on one page:
  - what is fixed;
  - what looks different, with the five most telling before/after pairs;
  - what is still open;
  - the three things the owner should try first on Windows, with steps;
  - every check marked run or not run.
- **`docs/HANDOFF.md`** replaces the old one. It contains:
  - the goal and current stage;
  - the version and both base SHAs;
  - the claims audit (WP1.1);
  - the status of each work package;
  - known bugs;
  - "Duplication to resolve";
  - **Owner decisions**;
  - next steps.

  The previous hand-off goes under a **History** heading at the end.

If anything here conflicts with what you find in either repository (an ADR,
a package API, the schema, the runner), **the repository wins**. Follow it,
and note the conflict in `HANDOFF.md`.
