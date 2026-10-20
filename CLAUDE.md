# Working on Nex

- Push or change remote pull requests only when the owner explicitly asks.
  Otherwise finish and verify locally, then ask whether to push; keep later
  edits together in the requested release.
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
- Persian and English, light and dark, right to left and left to right: every
  screen works in all of them.
- User-facing changes get a line in both `CHANGELOG.md` and
  `apps/client/assets/CHANGELOG.md`, its Persian in `CHANGELOG.fa.md` (what
  the update screen shows a Persian reader), and the guide (`apps/client/assets/guide/`)
  in both languages when they change how something is used.
