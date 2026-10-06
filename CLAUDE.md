# Working on Nex

- **Every new or changed screen follows [`docs/16-design-language.md`](docs/16-design-language.md).**
  Sheets open with `nexShowSheet` (never `showModalBottomSheet`), pages are
  pushed with `NexPageRoute`, spacing and corners come from `NexSpacing` and
  `NexRadius`, text a person writes follows ADR-037. Read it before adding a
  page, a sheet or a dialog, and go through its checklist before a pull request.
- Persian and English, light and dark, right to left and left to right: every
  screen works in all of them.
- User-facing changes get a line in both `CHANGELOG.md` and
  `apps/client/assets/CHANGELOG.md`, and the guide (`apps/client/assets/guide/`)
  in both languages when they change how something is used.
