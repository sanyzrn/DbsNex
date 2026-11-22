# 33 · Family fund module audit — 2.8.13 line

> Implemented and tested for 2.8.13. The module keeps its one-row-per-fund
> storage shape and uses the shared module API.

## 1. The short answer

The ledger arithmetic was sound and already guarded payouts against a
negative balance. What did not hold up was the product around it: the monthly
share was frozen at creation in a market where shares rise, a redraw lived in
a separate editor from the draw that produced it, the round was invisible
after the result, a member had no history, and the reminder text named a
recomputed date rather than the date the manager picked.

The branch fixes those and adds the practical surfaces a real Iranian fund
needs (effective-dated shares, a member sheet with arrears, editable fund
details, a copyable report and a group reminder), without changing one byte of
existing records.

## 2. What was wrong

| Finding | Effect | Fix |
| --- | --- | --- |
| The share was frozen in `shareRial` | Groups that raise the monthly share had to fake payments or create a new fund | `shareChanges` + `shareFor(month)`; recorded payments keep their amount |
| Redraw was a second sheet with a plain reason field | The manager lost the pool and the first result while typing; closing the form lost the attempt | One draw sheet: pool, confirm, in-sheet result, reason inline, history alongside |
| No round view | "Who has already won?" meant reading every draw | `roundFor` counts effective draws among current members; the Month panel and history show won/remaining |
| A member was one `ListTile` | No way to see history, open months or record the current month without hunting the payment list | Member sheet: share, payments, arrears, quick record, loan |
| Fund name/rules/days were fixed | A typo in a name or a changed contribution day was permanent | Page menu → Edit fund; ledger untouched, with an explicit hint |
| Reminder body used a recomputed suggestion | The notification could name a different day from the one picked | Body built from the stored `at`; test asserts the clock |
| Shelf cards had no state beyond a date | "Starts next month" and "winner waiting" looked identical to a settled fund | Glance counts + plain-language card state; no amounts on the shelf |
| Old draw test codified the removed dialog | Regression suite would block the redesign | Replaced with the new flow and new model tests |
| Stored month fields accepted any day | A hand-edited or migrated record could place a member or share change mid-month | `Fund.read` requires the first day; older valid data is unchanged |
| The home-screen and assistant dues used the opening share | After a share rise they disagreed with the month screen | `FundDues` uses `shareFor(month)`; an empty fund no longer creates a phantom draw due |
| The module tile was teal while its hero was magenta | Two different identities for one module | `hue` is `NexHue.rose`, matching the hero's 324 |

Also tightened: specific creation errors (`invalidName`, `invalidShare`,
`invalidDay`), redraw without a reason is refused in place, empty/failed/
unreadable shelves have distinct states and actions, the card progress says
"no members" instead of "0 of 0", and the loan card says "Settled" rather
than "Still to repay: 0".

## 3. New and rethought

- **Effective-dated shares.** A share change is a month-first entry; the
  latest entry at or before a month wins. Entries that repeat the amount in
  force are dropped during canonicalization, but an entry with unknown fields
  is kept so a future version's metadata is not destroyed. The Members tab
  lists the share history.
- **One draw sheet.** Eligible names, shares and the pot; one confirmation;
  the result animates once (or immediately with reduced motion); "Draw again"
  asks for a written reason in the same sheet and keeps both attempts. The
  winner is persisted before the result is shown, so a system back never
  loses a draw. A paid-out loan locks the month.
- **Round transparency.** "3 of 5 members have won this round", remaining
  names, and a complete/restarting state. `roundFor(month)` is pure and
  tested across Esfand/Farvardin boundaries.
- **Member sheet.** Contribution count, total, open months with arrears
  (respecting month length and the fund's due day), a one-tap "Record this
  month", the member's loan, and a guarded leave action.
- **Editable fund.** Name, rules, contribution day and draw day; the opening
  share stays in effective-dated history. The edit hint says recorded payments
  keep their dates.
- **Loans.** Paid count, progress, outstanding, next instalment, all
  instalments, and a paid/settled state that cannot be "still to repay: 0".
- **Report and reminder.** The month report can be shared, copied to the
  clipboard or reduced to a group reminder naming only open members. Masked
  amounts never reach the text.
- **Privacy.** Index cards show dates, progress and round state, never money.
  The detail's eye control masks the month, members, loans, report and
  reminder for the session.
- **Reminder fix.** The body is built from the stored instant and names the
  picked Jalali day and clock; `keepUp` still rolls the alert to the fund's
  next contribution/draw day at the same clock time.
- **States and accessibility.** Empty shelf, failed load, unreadable records,
  upcoming start, no active members, no eligible pool, payout pending. The
  draw result carries a semantics label; icon actions have tooltips; text
  fields go through `NexTextField`; sheets through `nexShowSheet`.

## 4. Data and compatibility

`fund` gained `shareChanges: [{from, shareRial}]`; draws gained a `shares`
snapshot in `eligible`. Both are additive. `Fund.read` still accepts records
without them, keeps unknown top-level and nested keys, and rejects only
impossible month fields. `shareRial` remains the opening share for older
readers; every new read and write uses `shareFor`. Payments are never
rewritten when the share changes. No migration, deletion or version bump.

## 5. Validation actually run

From `apps/client` on the repository pin (Flutter 3.47.9):

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub --fatal-infos lib/modules/family_fund test/modules/family_fund` | `No issues found!` |
| `flutter test --no-pub test/modules/family_fund --reporter compact` | `00:17 +37: All tests passed!` |
| Module gates, catalog, guide, changelog and version checks: kit, shared rules, glance, hero rebuild, infrastructure, preview, reminder alarm, modules, UI consistency, motion, text field, menu, sheet swipe, `nex_text_field_test`, `test/module_kit`, app guide, guide screen, what's new and version | `00:24 +245: All tests passed!` |
| `dart format` on module source and tests | clean |

New tests cover share changes (including canonicalization and stored-month
strictness), dues at the effective share, round counting and complete/restart,
arrears across Esfand/Farvardin, draw snapshots, ledger soundness, the full
draw/redraw/history flow, payout and instalments, the member sheet and quick
record, editing fund details, share changes keeping recorded amounts, unknown
fields on a redundant share entry, an empty fund having no dues, a fully paid
month's reminder moving on, the shelf and empty state, the compact Persian
draw sheet, the reminder clock, and the report's privacy masking in English
and Persian, light and dark.

**Not run:** the whole client suite (about 4,400 tests) was not repeated on
this branch; the focused gates above are the ones this module can affect.
**Not verified on a device:** real notification delivery, the system share
sheet and the soft keyboard. No screenshots were taken for this audit; the
widget tests render the compact/Persian/dark combinations and assert no
overflow, but a visual pass on a phone is still the owner's check.

## 6. Limitations and next steps

- No destructive fund deletion; a mistyped fund can only be emptied through
  corrections. A guarded archive with a JSON export is the next safe step.
- Alerts are per-record one-time notifications rolled by `keepUp`; native
  monthly recurrence and one control for both alerts need a platform change.
- Sharing is text. A monthly status image would travel better in Telegram and
  WhatsApp.
- One manager edits on one device; the store has no cross-device
  compare-and-swap.
- Full-share contributions only; partial payments and refunds are outside
  the model.
- The report balance is as of today, labelled as such, not month-end.
- The gallery of seeded screenshots was removed from the module README
  because it referenced files from the earlier 2.8.4 review that this branch
  did not regenerate.

## 7. Iranian references

- [Hamyan's developer guide](https://blog.hamyanapp.com/training-software-hamian-sandogh-gharzolhasane/)
  — shares and monthly dues.
- [Hamyan's sample bylaws](https://hamyanapp.com/blog/nemoone-asasname-sandogh-khanevadegi)
  — the clauses a family actually argues about.
- [Pand — what a family loan fund is](https://pand-co.com/what-is-the-family-loan-fund/)
  — monthly instalments and the draw.
- [Vamilon's sample bylaws](https://vamilon.com/blog/family-loan-conditions).
- [Vindad's bylaws](https://vindad.com/blog/%D8%A7%D8%B3%D8%A7%D8%B3%D9%86%D8%A7%D9%85%D9%87-%D8%B5%D9%86%D8%AF%D9%88%D9%82-%D9%82%D8%B1%D8%B6-%D8%A7%D9%84%D8%AD%D8%B3%D9%86%D9%87-%D8%AE%D8%A7%D9%86%D9%88%D8%A7%D8%AF%DA%AF%DB%8C/).
- [Rokla's qard-al-hasan contract](https://rokla.ir/blog/good-loan-agreement/).
- [Bourseiness on starting a fund](https://www.bourseiness.com/20984/family-fund-loan).

**What the research shaped.** A family or colleagues' fund is ordinarily an
informal private arrangement, not a licensed financial institution, so the
module stays a ledger: it records the group's own rules as text instead of
claiming regulatory compliance. Contributions are a fixed share with no
interest or profit calculation; a payout is the collected pot, and repayments
are principal only. Real bylaws spend their words on the awkward cases this
module makes visible — a late contribution, leaving mid-round, who has already
received the fund, the order of the draw and what happens when a member cannot
pay — while leaving the group to decide the consequence. That is why arrears,
round progress and redraw reasons are first-class, and why the app never
invents a penalty or a refund.

These describe product practice and contract vocabulary; they are not
financial advice. The module charges no interest and assumes no profit share.
