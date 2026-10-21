# Working on Nex

- Push the working branch yourself once a change is finished and verified (the
  tests and analysis pass) — the owner does not need to ask each time. Create,
  merge or edit pull requests only when the owner asks. Keep later edits
  together in the requested release.
- Continue work on the shared `codex/2.0-polish` branch. Do not create a new
  branch for each change or module unless the owner explicitly requests it.
- All 11 supplied add-ons are integrated under `apps/client/lib/modules/`,
  and Birthdays & occasions (`occasions`) was built on the module kit.
  Cycle, Habits, Price Lens, Lent & Borrowed, Quit Habits (`smoke_free`),
  Birthdays & occasions, Expenses, Gold, Words, Parking, Medicine, Warranty and
  Maintenance are all available (the last seven from 2.1.14); none is Soon.
  Preserve all source, installation choices and data; a new module starts Soon
  and is enabled after review (`nexAvailableModuleIds` in `module_rollout.dart`). `addons/README.md`
  tracks scope and limitations.
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
