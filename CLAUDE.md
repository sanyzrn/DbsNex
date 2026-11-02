# Working on Nex

- Push the working branch yourself once a change is finished and verified (the
  tests and analysis pass) — the owner does not need to ask each time. Create,
  merge or edit pull requests only when the owner asks. Keep later edits
  together in the requested release.
- **Before choosing a version number, always check what is already published at
  <https://github.com/sanyzrn/DbsNex-releases>** (its tags and Releases). The
  owner publishes from there, often between sessions: a version found there is
  closed, and everything after it goes under the next number — never add to a
  released version's changelog section or reuse its tag. (2.1.14 was out while a
  later change was still being written under that number; it moved to 2.1.15.)
- Continue work on the shared `codex/2.0-polish` branch. Do not create a new
  branch for each change or module unless the owner explicitly requests it.
- Available modules are **Cycle, Breathing break (Pause), Birthdays & occasions,
  Word by Word and Habits** (`cycle`, `pause`, `occasions`, `words`, `habits`).
  The authoritative rollout list is `apps/client/lib/modules/module_rollout.dart`;
  installed and active modules are resolved through `nexModulesOn`.
  Other modules remain **Soon** pending completion and device review. Preserve
  their code, installation choices and data; never enable them just because
  their source or translations exist. `addons/README.md` tracks scope.
- **Every new or changed screen follows [`docs/16-design-language.md`](docs/16-design-language.md).**
  Sheets open with `nexShowSheet` (never `showModalBottomSheet`), pages are
  pushed with `NexPageRoute`, spacing and corners come from `NexSpacing` and
  `NexRadius`, text a person writes follows ADR-037. Read it before adding a
  page, a sheet or a dialog, and go through its checklist before a pull request.
- **One look everywhere.** The UI is being unified one family at a time
  ([`docs/26-ui-consistency.md`](docs/26-ui-consistency.md)): corners, cards,
  menus, pickers, banners, buttons. When you are in a file and meet a stock or
  copied piece, move it to the shared component in the same change and lower
  its number in `test/ui_consistency_test.dart`. Cycle is the one deliberate
  exception.
- Persian and English, light and dark, right to left and left to right: every
  screen works in all of them.
- User-facing changes get a line in both `CHANGELOG.md` and
  `apps/client/assets/CHANGELOG.md`, its Persian in `CHANGELOG.fa.md` (what
  the update screen shows a Persian reader), and the guide (`apps/client/assets/guide/`)
  in both languages when they change how something is used.

## Release-note editorial policy

Root and bundled `CHANGELOG.md` / `CHANGELOG.fa.md` are user-facing content.
Include usable new features, noticeable improvements and important visible
fixes. Use short descriptive titles and explain the benefit. Write Persian
naturally, never as a literal translation. Omit internal architecture,
dependency/build/CI details and insignificant cosmetic adjustments. Keep
bundled copies identical to their roots. Preserve technical history in git
and `docs/development/CHANGELOG*.md`, outside the app's notes. Apply the same
standard to historical entries. Internal-only releases may be absent from
the user-facing history. Updating historical wording does not add new
features to those releases; new changes belong to an unreleased version.
