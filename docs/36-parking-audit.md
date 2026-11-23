# Parking module audit (2.8.18)

Branch: `agent/module-parking-audit`, from `main` at `412efe9e`.
Scope: `apps/client/lib/modules/parking`, its tests and documentation. No
other module, shared widget or data format was changed.

## What was wrong

The module was already complete and its baseline was green (117 tests). The
audit found defects that only appear after real use, not on a first run:

| Finding | Cause | Fix |
| --- | --- | --- |
| A favourite place lost its star the next time it was parked | `rememberPlace` built a place with `favourite: false` and merged it over the old record | Carry the existing `favorite` mark into the rebuilt place; a visit is not an un-star |
| Opening a reminder showed 10 minutes even when 30 was set and saved 10 | `ParkingQuickReminder` passed only a label, while the sheet always started at `10` | Pass the saved lead (or a lead that fits) into the sheet and initialise the field from it |
| A paid-time reminder could ring for a car already closed by a new parking | `save(closeEarlier: true)` wrote `foundAt` but never cleared the other alarm | Clear the earlier key through the store after the write succeeds, best-effort like «I'm back» |
| One-tap parking chose the wrong car after an old record was edited | It took the first vehicle in store order, which is “saved most recently” | `ParkingLogic.lastVehicle` chooses the vehicle of the latest `startedAt` |
| Arabic yeh/kaf and Persian/Arabic digits did not match | Comparison only trimmed, lower-cased and collapsed spaces | `ParkingModels.fold` normalises letters, Arabic-Indic digits, half-spaces and whitespace; used by vehicle/place identity, search and query de-duplication |
| Searching turned an open parking into a dismissible history row | Every match was put in the history list, while active cards were hidden during search | Active matches stay in `active`; only closed matches become history; “no matches” now considers both |
| A countdown under a minute read `0 min` | Durations were floored to whole minutes | Positive sub-minute values read “under a minute” in both languages, on the card, history, detail and glance |
| A reminder could be offered after the paid time ended, then always fail | The control appeared whenever `expiresAt` existed | Offer it only when at least a one-minute lead still fits; the last whole minute for short stays; disable chips that cannot fit |
| The quick reminder label said 30 while the sheet silently changed it | Same as above; opening and saving reset the stored lead | Fixed by the initial-lead change |
| `Keep it open` in the conflict question did nothing and said nothing | Both callers returned without saving | Keep the behaviour (the earlier record stays open, nothing is written) and show a banner saying the new parking was not saved |
| Places beyond the fourth were unreachable, with no way to remove a stale one | Home showed only `take(4)`; there was no places screen | Show six per shelf, sort by `lastUsedAt`, and add an “All places” sheet with star, delete and Undo |
| Place rows hid their clue and how often they were used | Subtitle showed only floor and spot | Subtitle includes the landmark and a use count when above one; the star tooltip says “Remove from favourites” when set |
| Search history stored eight and showed six | A literal `take(6)` | Uses `ParkingModels.searchHistoryLimit` |

## Product additions

- **All places** sheet: every remembered place, recently used first; tap to
  fill the editor, star/unstar, or forget with a confirmation and Undo. Past
  parking is never touched by forgetting a place.
- **Short-stay reminders**: a paid parking with less than ten minutes left
  opens on five, or on the largest whole minute that still fits; no reminder
  is offered once the end is under a minute away.
- **Smarter search**: open cars remain cards, Arabic/Persian spellings match,
  and a repeated query in another spelling is moved instead of duplicated.
- **Honest sub-minute copy**: “Parked for under a minute”, “under a minute”
  left, instead of a misleading zero.

## Deliberate non-changes

- `startedAt` is still “when the parking was recorded” and is not editable.
  Editing it would change the meaning of historical durations and drafts; a
  person who records late can still correct the place/paid time.
- A paid time may be before the recording time. People often enter a parking
  after the meter has already run out; the module says “Past the paid time”
  instead of refusing the record.
- The delete guard that prevents two active parkings for one vehicle from
  being created by Undo stays. Its error is generic today; a dedicated message
  is left for a later shared error-surface change.

## Verification

- `flutter analyze --no-pub lib/modules/parking test/modules/parking`: clean.
- `flutter test --no-pub test/modules/parking`: **135 passed**, up from 117.
  Eighteen regression tests cover the fixes above, including the place sheet,
  conflict banner, active-search results, Arabic/Persian matching, reminder
  defaults and short-stay states.
- The shared module gate (`module_kit`, `module_shared_rules`, parking):
  **251 passed**.

## Remaining limitations

- Search covers parking sessions, not the remembered-place sheet.
- Notification permission, the real keyboard, TalkBack/VoiceOver and release
  builds still need a physical device.
- The version number (`2.8.18`) is the next after `main`; if the parallel
  Asset-book audit branch is merged first, this branch needs a version bump at
  merge. No data migration is involved either way.
- The full client suite (`4,735` passed, `7` skipped, `10` failed) reports
  failures in attachments, attach-paths, the home brief, AI assistant, the OS
  capture bridge and the sponsor card — all outside Parking and outside the
  files this branch touched. They were not investigated here; the Parking
  suite and the shared gate are green.