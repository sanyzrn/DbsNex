# Task: finish, upgrade or build one Nex module

You are a senior Flutter engineer. You will work on **one module** of Nex.
Which module, and what it must become, is in its brief:
`docs/prompts/module-briefs/<id>.md`. Read the brief first, then all of this,
then the brief again. Do not write code before you have read both.

There are three kinds of job, and the brief names yours:

- **Upgrade (Soon):** the module's code already exists and is not yet shown
  to anyone (it is "Soon"). Your job is to **finish and upgrade the code
  that is there**, not to start again. Keep what works; fix what does not;
  add what the brief asks for.
- **Upgrade (live):** the module is already in people's hands. Everything
  above, plus: **nothing a person has saved may be lost, hidden or changed
  in meaning**, and nothing they use today may disappear.
- **New:** there is no code yet. Build the module from nothing, inside its
  own folder.

This prompt builds on `docs/prompts/11-module-builder.md`. Rules 2 to 10 of
that prompt apply in full, with the changes below. Where the two differ,
this one wins.

## Getting the code

- **Repository:** <https://github.com/sanyzrn/DbsNex>. Start from the newest
  commit of `main`.
- **Toolchain:** Flutter 3.35.x (Dart 3.9). In `apps/client`, run
  `flutter pub get` first.
- **Branch:** create `agent/module-<id>` from `main`, commit there, and push
  that branch. Do not open a pull request, do not push to any other branch,
  and do not delete branches. If you cannot push, hand off one zip as
  prompt 11 describes.

## Read before you start

1. `CLAUDE.md` at the root: how this project works.
2. `docs/17-modules.md` and `docs/18-module-kit.md`: the platform and its
   rules.
3. `docs/16-design-language.md` and `docs/26-ui-consistency.md`: how every
   screen looks, moves and behaves.
4. `apps/client/lib/modules/module_api.dart` and everything it exports:
   all you may use.
5. A finished module as a model of the standard expected:
   `apps/client/lib/modules/lent_borrowed/` (README, drafts, reminders,
   undo, Persian money and dates). `gold/` shows tabs that keep what was
   typed.
6. For an upgrade: **your module's own folder, its README and its tests,
   all of them**, before you change a line.

## Where you may write

Only:

- `apps/client/lib/modules/<id>/`: code, `README.md`, and `review/` for
  screenshots;
- `apps/client/test/modules/<id>/`: tests.

Never:

- `module_rollout.dart`: the module **stays Soon**. Making it available is
  the owner's decision, after testing it on a phone.
- `module_registry.dart`, `module_plans.dart`, `module_hero.dart`, the ARB
  files, `pubspec.yaml`, the module API, the gate, or another module's
  folder.
- For a **new** module: add it to `nexModules` locally to run the gate, and
  leave that line out of your commits. The maintainers add it, choose its
  hero hue and retire its "On the way" entry.

If you need something outside your folder, write it under **Platform
requests** in the README, with how the module behaves without it.

## Changes to prompt 11's rules

- **Imports:** as rule 2, and never another module's folder. If you need
  something small from another module (a sum, a format), copy it into your
  folder and say so in the README.
- **Files:** at most 400 lines each.
- **Dates:** the API now gives you Persian (Jalali) dates and date entry
  (`module_dates.dart`, `nexPersianDate`, `nexReadableDate`). Use them. In
  Persian, every date a person sees or enters is Jalali, and a "month" is a
  Jalali month.
- **Money:** whole integers in rials, stored once. Show tomans or rials the
  way the app's existing money modules do (`lent_borrowed`, `gold`), with
  Persian digits and grouping in Persian.
- **Undo:** deleting shows the app's banner (`nexShowBanner`) with an Undo
  action, as the existing modules do, not a SnackBar.
- **Sharing:** text goes to the phone's share sheet with
  `nexModuleShareText`, as `lent_borrowed/loan_message.dart` does. There is
  no image sharing yet: ask for it under Platform requests, and share text
  meanwhile.
- **Reminders:** only through `NexModuleReminderControl` and the store's
  `setReminder` / `setDailyReminder` / `clearReminder`. A reminder must say
  what it is about in its own words.
- **Design, added since prompt 11:**
  - a `FloatingActionButton` always sets `heroTag: null`, so it never flies
    into another page's button;
  - a segment that swaps what is shown below it uses `NexSegmentSwap`, so
    the views fade into each other rather than cut;
  - tabs that hold something typed keep it when you switch: never push a
    page per tab, never rebuild a form from storage on each switch;
  - every layout is checked in Persian and English, light and dark, and at
    text scale 2.0.
- **Privacy:** a screen showing money totals or health details offers to
  hide the amounts, or uses `NexSecureWindow` where the brief says so.

## For an upgrade: audit first

Before changing anything, write an **Audit** section at the top of the
module's README:

- what the module does today, screen by screen;
- what is broken, unfinished or below the standard of `lent_borrowed`
  (design rules, Persian, RTL, dark mode, text scale, undo, empty states,
  tests);
- what the brief asks for that is missing.

Then work through the list. Keep the audit in the README, with each item
marked done, or not done and why.

## For a live module: compatibility

- Record kinds and fields may be **added**, never renamed or removed. A
  record written by the current version must open, show and save exactly
  as before.
- Add a test that stores records as the current version writes them, opens
  the upgraded module, and checks nothing was lost or changed.
- Nothing that exists today is moved more than one tap further away.

## The README

The seven sections of prompt 11, plus:

- **Audit** (upgrades only), at the top;
- **Device checklist**: the things the owner should try on a phone before
  making the module available, in the order a person would meet them;
- **Open questions**: what the brief left open that only the owner, or real
  users, can answer.

## Done means

- `flutter analyze --fatal-infos` is clean and the code is formatted.
- `flutter test test/module_kit_test.dart test/modules/<id>` passes, and
  the whole client suite (`flutter test`) has been run once, with nothing
  broken.
- Screenshots of the main screens are in `lib/modules/<id>/review/`, in
  Persian dark and English light at least.
- The README is complete, the branch is pushed, and your final reply gives:
  the commit of `main` you started from, the branch, the audit's status,
  the Platform requests, the Open questions and the end of the test output.
