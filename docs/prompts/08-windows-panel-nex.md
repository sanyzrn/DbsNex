# Task: Turn the Flutter edge panel into Nex for Windows

You already converted **Right Panel** (`github.com/raminturne/right-panel`: a Rust + WebView edge panel for Windows, MIT licence) into a Flutter app. You now also have the **Nex** repository. Nex is a local-first, Persian-first capture and notes app; Android is its shipping platform. Your job is to make the panel the **Windows home of Nex**:
- the panel's shell stays: edge reveal, liquid motion, tray, hotkeys, multi-monitor;
- Nex's features and data live inside it.

The goal is a solid, working base, not a finished product. The Nex maintainers will do the final polish on top of your work. That means **structure, correctness and clear hand-off notes matter more than feature count**.

## 0. Before you write any code
1. In the Nex repo, read:
   - `README.md`
   - `docs/04-architecture.md`
   - `docs/05-design.md`
   - `docs/09-ai.md`
   - `docs/10-decisions.md` (the ADRs; they are binding)
   - `packages/core/lib/nex_core.dart`, `packages/data/lib/nex_data.dart`, `packages/ui/lib/nex_ui.dart`, `packages/ai/lib/nex_ai.dart`
   - `apps/client/lib/app.dart`, `apps/client/lib/platform/nex_services.dart`, `apps/client/lib/platform/nex_db.dart`
2. Run `make check` in the Nex repo and confirm it passes before you change anything. It needs Flutter 3.35.x. Use the same Flutter version for your app.
3. Write a short plan in `apps/desktop/README.md` (section "Plan") before implementing. It contains:
   - the architecture decision;
   - the feature mapping table (see section 3);
   - the order of work.

   Then start.

## 1. Where the code goes and how it depends on Nex
- Work on a new branch of the Nex repo, `feature/windows-panel`. Never push to `main` or to any `release/*` branch.
- Put the panel app at **`apps/desktop/`** as its own Flutter app.
  - Bring your converted panel code there, keeping its git history if practical.
  - It depends on Nex's packages **by path**: `nex_core`, `nex_data` and `nex_ui`, plus `nex_ai` only behind one integration point (see the rules).
- **Do not copy** Nex domain logic, schema, search, merge or theme tokens into the panel. One source of truth. If something you need lives only in `apps/client` and is platform-neutral (for example a model helper or a formatter):
  - move it into the right package in a separate, behaviour-preserving commit;
  - update `apps/client` to import it from the package;
  - keep `make check` green.

  If moving it is not small and safe, re-implement only the thin UI piece in the panel and list it in the hand-off notes as duplication to resolve.
- **Do not change Android behaviour.** Changes to `apps/client` are limited to the moves above.
- Keep Right Panel's MIT copyright notice: put its `LICENSE` text in `apps/desktop/THIRD_PARTY_NOTICES.md` and show it in the app's licences page.

## 2. Non-negotiable Nex rules (from the ADRs and the architecture)
1. **Local-first.** The local SQLite store, through `nex_data`'s repositories, is the only store. The panel opens the **same schema** as Android, with the same migrations and the same note model (UUIDv7 ids, content-addressed media, tombstones and change tracking). No parallel storage (no JSON files of notes, no second database). A later step adds LAN sync between the phone and this app over Nex's existing push/pull protocol. Your data must be ready for it without changes.
2. **Capture never waits** on the network or on AI. There are zero mandatory fields and no Save button. A note is saved as soon as it has content (ADR-001, ADR-002).
3. **AI is optional and removable** (ADR-035). Only one file in `apps/desktop` may import `nex_ai`, and the app must build and run with that integration removed.
4. **Persian first.**
   - Every string in `en` and `fa` through ARB files in `apps/desktop/lib/l10n`.
   - The Persian font that Nex uses.
   - Direction taken from the text for user content (`nexDirectionOf` / `NexTextSurface`).
   - The whole panel mirrors correctly in RTL. A right-edge panel in an RTL UI is still on the edge the user chose.
5. **The vault's data never enters** the notes DB, search, AI context, the clipboard history or notifications.
6. **No secrets in the binary.** API keys come from the user and go into secure storage (`flutter_secure_storage` on Windows).

## 3. Features: what to build, in this order
Produce the mapping table first: Right Panel feature → keep as a panel tool / replace with the Nex feature / candidate to remove (owner decides). **Do not delete** any Right Panel tool. Tools that are not Nex features (calculator, units, colour picker, emoji, timers, media keys and so on) stay working, grouped under "More tools", and are listed in the table for the owner to decide.

Then implement, in priority order:

1. **Shell, from your conversion:**
   - edge reveal on the chosen edge and monitor;
   - global hotkey to open the panel;
   - tray icon;
   - start with Windows;
   - single instance;
   - DPI and multi-monitor correctness.
2. **Quick capture:**
   - A global hotkey opens the panel focused on an empty note field. Typing creates the note immediately, and Esc closes the panel with the note kept.
   - Paste an image to create a photo note.
   - Drag and drop files and images onto the panel to create file and photo notes. Files are copied into Nex's media store.
   - The current clipboard text becomes a note in one click.
   - Checklist capture.
3. **Timeline** in the panel's width:
   - newest first;
   - day headers;
   - the note card from `nex_ui` adapted to the width;
   - pin;
   - open, edit, delete with undo, and restore from recently deleted.
4. **Search:** one box using Nex's search (FTS plus filters by type, tag and thread), with Persian normalisation exactly as on Android.
5. **Tags and threads:** add, remove and browse.
6. **Note detail and editing:**
   - text, checklist and markdown rendering, as Nex does it;
   - attachments open with the system app;
   - copy follows Nex's rule: caption first, then OCR or transcript.
7. **Reminders** using Windows toast notifications, with the same reminder data as Android.
8. **Voice notes:** recording (the `record` plugin supports Windows) and playback. Transcription is optional and goes behind the AI integration point.
9. **Settings:**
   - theme, using Nex theme presets and tokens from `nex_ui` rather than Right Panel's themes; keep any extra panel-only appearance options only if they do not conflict;
   - language;
   - panel edge and monitor;
   - hotkeys;
   - start with Windows;
   - backup and export, using Nex's encrypted backup format so a backup made on Windows restores on Android and the other way round;
   - about and licences.
10. **Assistant** (optional, behind the single `nex_ai` integration point): the same action protocol and confirmation rules as Android. If time is short, leave a clearly marked stub instead.
11. **Vault:** only if you can reuse `apps/client`'s vault model safely through a package move. Otherwise leave it for the maintainers and say so.

Not in this task: LAN sync, cloud sync, the AI on-device runtime, OCR on Windows. List them as next steps.

## 4. Quality bar
- `flutter analyze` is clean, and `dart format` is applied to the files you touched.
- Tests:
  - unit tests for every piece of logic you add;
  - widget tests for quick capture (type → note exists in the DB; close → still there), search, and delete → undo;
  - one test that opens a database created by the Android app's schema, and one that round-trips a backup.
- `make check` at the repo root stays green.
- Add the `apps/desktop` analyze and test commands to the Makefile.
- Add a Windows build job for `apps/desktop` to CI, modelled on the existing `client-windows` job in `.github/workflows/ci.yml` (the `windows-2022` runner).
- No `print` statements. No hard-coded user-visible strings. No hard-coded colours outside `nex_ui` tokens.
- Performance: the panel opens in under 150 ms after the hotkey once warm, and the timeline scrolls smoothly with 10k notes. Measure and report the numbers.

## 5. Commits and hand-off
- Use small, focused commits with clear messages. Each one builds.
- At the end, `apps/desktop/README.md` contains:
  - the architecture;
  - how to run, test and build;
  - the feature mapping table with its final status;
  - a **parity matrix** against Android (done / partial / missing, with notes);
  - known bugs;
  - the duplication left to resolve;
  - decisions the owner must make (which Right Panel tools to keep);
  - the next steps (LAN sync, OCR, vault, assistant polish).
- Open a pull request into `main` titled "Windows panel: Nex on the desktop (base)". It must be a draft, and not merged. The description summarises the above and lists what a reviewer should try first.

If anything in these instructions conflicts with what you find in the Nex repo (an ADR, a package API, the schema), **the repo wins**. Note the conflict in the README instead of working around it.
