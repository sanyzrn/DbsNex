# Nex — Design Language

> The short, practical companion to [`05-design.md`](./05-design.md): not why Nex
> looks the way it does, but **how every new page, sheet and dialog is built** so
> it looks and behaves like the ones already there. Read it before adding a
> screen. Where a rule is enforced by a test, the test is named — breaking the
> rule fails CI with the file and line.

---

## 1. Sheets

A sheet is anything that rises from the bottom: a picker, a list of actions, a
form that is not a whole page.

- **Always `nexShowSheet`** (`apps/client/lib/widgets/nex_dialog.dart`). Never
  `showModalBottomSheet` directly. The wrapper gives every sheet, in one place:
  - the glass (or opaque, in high contrast) surface with the `NexRadius.xl` top
    corners;
  - the drag handle;
  - the bottom safe area, so the last button is never under the navigation bar;
  - **closing by pulling the content down past the top** — not only from the
    handle. A scrolling body takes the drag before the sheet sees it; without
    this a long sheet can only be closed from its handle and reads as stuck.
  - Enforced by `test/sheet_swipe_test.dart`. The few raw sheets that predate
    the rule are listed there with their reasons; the list only shrinks.
- A sheet that guards unsaved work passes `dismissible: false, swipeToClose:
  true`: the swipe then asks the editor's `PopScope` first.
- Sheet content scrolls (`SingleChildScrollView` or `ListView`) and starts with
  `NexSpacing.md` padding; its title is `titleLarge`.
- A sheet that belongs to a space with its own look (see §8) wraps its content
  in that space's theme, never its own copy of the colours.

## 2. Pages

- Pushed with **`NexPageRoute`** (`packages/ui`), which carries the swipe-back
  gesture. Not `MaterialPageRoute`.
- A plain `AppBar` with the page's name as its title and its actions as icon
  buttons with a tooltip. A page has **one primary action**; everything else is
  secondary (an icon, a text button, a menu).
- Content in a `ListView` with `NexSpacing.md` side padding, so it scrolls on a
  small phone and with large text.

## 3. Dialogs

- `AlertDialog` with its body in `NexDialogBody`; the cancelling action first,
  the destructive one in `colorScheme.error`, the confirming one last.
- A dialog asks one question. Anything with more than two or three fields is a
  sheet or a page.

## 4. Text a person writes

- More than one line: **`NexTextField`**. One line: inside **`NexAutoDirection`**,
  or with an explicit `textDirection` (a number, a link, a key: left to right).
- Enforced by `test/text_field_rule_test.dart` ([ADR-037](./10-decisions.md)).

## 5. Space, shape and type

- Spacing only from `NexSpacing` (`xs` 4, `sm` 8, `md` 16, `lg` 24, `xl` 32);
  corners only from `NexRadius`. No bare numbers for either.
- Text styles only from `Theme.of(context).textTheme`; colours only from the
  `colorScheme` (or a feature's named colour function, such as
  `cyclePeriodColor`). No hex codes in a screen.
- Directional by default: `EdgeInsetsDirectional`, `AlignmentDirectional`,
  `PositionedDirectional` — every screen is read right to left in Persian.
- Numbers a person reads go through the locale's digits (`nexDigits` or the
  feature's helper): «۱۲ روز», not «12 روز».

## 6. Motion

- Short and purposeful (`NexMotion`); nothing loops forever on its own.
- Respect reduced motion: when `MediaQuery.disableAnimationsOf(context)` is
  true, appear in place.
- A test's `pumpAndSettle` must settle: a page that never stops animating is a
  page that cannot be tested — and one that tires the person looking at it.

## 7. Reach and meaning

- Touch targets at least 48dp. Every icon-only button has a `tooltip`.
- A custom-painted control (a ring, a chart) has a `Semantics` label saying
  what it shows.
- Empty states say what to do next, with the button to do it.

## 8. A space of its own

Most of Nex is calm, neutral and the person's own theme. A feature may have
**its own space** only when stepping into it should feel different — today, only
«Cycle». Such a space:

- defines its look **once**, as a theme over the app's theme (fonts, sizes and
  light/dark stay the person's), e.g. `CycleTheme` / `CycleSpace` in
  `lib/screens/cycle/cycle_space.dart`;
- uses that theme on its page, its sheets and its dialogs alike;
- builds on the same pieces as everything else — `nexShowSheet`,
  `NexPageRoute`, the spacing and radius tokens — so it behaves like the rest of
  the app even where it looks different.

## 9. Before you open the pull request

- [ ] Every sheet opens with `nexShowSheet` and closes by swiping down from
      anywhere in it.
- [ ] Every page is pushed with `NexPageRoute` and has one primary action.
- [ ] Persian and English, light and dark: nothing overflows, nothing reads in
      the wrong direction.
- [ ] Reduced motion leaves nothing moving.
- [ ] New text a person writes follows §4.
