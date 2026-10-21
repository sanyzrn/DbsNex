# 26 · One look: the UI consistency register

> Status: **open, worked on a little in every release.** Started 2.1.14.

## The standing instruction

From the owner, as a note kept in the app and repeated since:

> Work only on unifying the shared parts of the interface. Review search and
> text-entry boxes, dialogs, popups and menus across the whole app. Move the
> repeated, scattered implementations and styles into shared components and
> tokens (`packages/ui` and the theme); begin with what already exists there and
> finish it. **Goal:** parts of the same kind take one source for colour,
> corners, border, spacing and focus state; the differences they need come from
> options and variants, not from copies. Do not redesign the pages, and do not
> change the logic, data, rendering engine or native editor. Keep the glass
> material, light and dark, Persian/English and RTL, large text, and the focus,
> error and disabled states. Delete the replaced duplicate code, run the tests,
> and report briefly.

And, 2.1.14: *every* family — corners, cards, menus, calendars, sheets — has one
fixed shape, **except** where a feature deliberately has a design of its own
(Cycle, `docs/16-design-language.md` §8). It is a large job, so: register it
here, and **fix what you meet while you are in the file** — do not wait for a
dedicated release, and do not leave a deviation unfixed because "it is a
different task".

## How the work is done

1. **One family at a time**, in this table's order of cost, never a sweep of the
   whole app in one change.
2. A family's shared component lives in `packages/ui` (or the module kit for
   modules) and is the **only** way to build it. Callers pass options.
3. Every family gets a **ratchet** in `apps/client/test/ui_consistency_test.dart`
   (or its own rule test): the number of old-style uses at registration, which
   may only go down. A new old-style use fails the build; fixing one lowers the
   number — the failure message says so. At 0, the family is finished and stays
   there.
4. When you touch a screen for any reason, move *its* old-style uses to the
   shared component in the same change and lower the number.
5. A deliberate exception (a feature with its own space) is named in the family's
   row, not left to look like drift.
6. Each finished family gets a section in `docs/16-design-language.md`, a line in
   its pull-request checklist, and a rule test.

## The families

| Family | Shared component | Status |
|---|---|---|
| Bottom sheets | `nexShowSheet` (handle, swipe, tap outside, keyboard) | **Done** (2.1.13–14) — `sheet_swipe_test`, `sheet_scrim_test` |
| Menus (⋮, hold, heading, picker) | `NexPopupMenuButton` + `nexMenuItem`, `nexShowContextMenu` | **Done** (2.1.14) — `menu_rule_test`; dropdown lists via `nexDropdownRadius`/`nexDropdownColor` |
| Pickers: time, date, Jalali | `nexPickTime`, `nexPickDate`, `nexPickModuleDate` | **Done** (2.1.14) — raw pickers at 0 |
| Module pages | `NexModuleHero`, `NexMoreDetails`, one empty-state button | **Done** for the 13 modules (2.1.14) |
| Corner radii | `NexRadius` tokens | Mostly: 8 left, all 2–3 px bars/dots — ratchet |
| Messages | `nexShowBanner` (top capsule) | **81 `SnackBar(` left** — a screen at a time |
| Buttons | `FilledButton` / tonal / `TextButton` | 5 stock `OutlinedButton`/`ElevatedButton` left |
| Cards and panels | `NexPanel`, shelf widgets | 4 stock `Card(` left (vault, brief) |
| Dialogs | `nexShowDialog` | Done (no raw `showDialog`/`AlertDialog`) |
| Text entry (single line / search) | `NexTextField` line + the search field header | **To audit:** per-screen `InputDecoration` copies |
| Multi-line text a person writes | `NexTextField` (ADR-037) | Done |
| Spacing literals | `NexSpacing` | **To audit:** ~110 numeric `EdgeInsets`/`SizedBox` |
| Chips, segmented controls | one chip / segment style | **To audit** (`AdaptiveSegments` exists in 5 modules, copied) |
| Lists and rows | `NexGroupedRow` | **To audit** |
| Focus, error and disabled states | theme `inputDecorationTheme` | **To audit** |
| Cycle | its own space (§8) | **Exception**, by design |

"To audit" means no one has counted yet: the first job of that family is to count
the old-style uses, put the number in the ratchet, and only then start moving
them.

## Why a register and a ratchet

Several of these were fixed once and came back (menus drawn in three ways,
sheets that did not close from outside), because nothing stopped the next screen
from copying the old pattern. The number in a test is the cheapest thing that
does.
