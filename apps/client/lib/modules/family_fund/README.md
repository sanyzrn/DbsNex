# Family fund · صندوق خانوادگی

## What it does

A private, offline ledger for a family or colleagues' rotating loan fund
(صندوق قرض‌الحسنه). Registered as `FamilyFundModule()` in `nexModules`
(hue 324), in the Money shelf and the Tools list.

- **Funds** opens existing ledgers and creates one with a name, amount per
  share, first Jalali month, contribution day, draw day and optional rules.
  Cards show the next date, progress, round and a plain-language state; they
  never show amounts, so a phone left on a table reveals no ledger.
- **Month** shows the collected cash, the pot, payment progress for the
  selected month and which members are overdue. Tick a contribution once to
  record the member's full amount for that month. Earlier months can be
  revisited and late contributions are dated when recorded.
- **Members** keeps join and departure months, the share count and the
  effective share history. Recording a departure stops future contributions
  from the next month. Earlier contributions, draws and loans remain.
- **Draws** previews eligibility and saves the round, date, winner and
  eligible snapshot. A redraw requires a reason, excludes earlier picks for
  that month and preserves all attempts. The result appears inside the same
  sheet; a paid-out loan locks that month's result. A round panel shows how
  many current members have already won and who is left.
- **Loans** records a real payout against the selected winner and splits
  principal into due instalments. Tick repayments as received; the next
  instalment, all instalments and the outstanding amount are one tap apart.
- **Report** previews the fund name, month, paid and pending names, balance
  and winner. It can be shared, copied or reduced to a group reminder naming
  only the members still open. The eye control masks amounts in the view,
  report and reminder.

## What this audit changed

The module already had a sound one-row-per-fund ledger. The audit kept the
storage shape and the money model, then fixed the places where the product
did not match how a real Iranian fund runs:

- **Effective-dated shares.** A fund's monthly share rises over time in real
  life. `shareChanges: [{from, shareRial}]` records the change from a chosen
  month; `shareFor(month)` is the only way money is read. Recorded payments
  keep the amount they were saved with, so history never silently changes.
  The Members tab shows the share history.
- **One draw sheet.** The old confirm dialog and separate redraw editor were
  merged into a single sheet: eligible names and shares, one confirmation,
  an animated result, and, for a redraw, the reason field in place. The
  winner is persisted before the result is shown, so closing the sheet never
  loses a draw.
- **Round transparency.** `roundFor(month)` counts the effective draws among
  currently active members and reports won, remaining and complete. The
  Month panel says "3 of 5 members have won this round" and lists who is
  left; the draw history lists earlier rounds with reasons.
- **Member sheet.** Tapping a member opens their share, contribution count,
  total paid, open months with due dates and arrears, a quick "record this
  month" action, and their loan if they won.
- **Fund corrections.** The fund's name, rules and contribution/draw days can
  be edited from the page menu. The ledger is untouched; recorded payments
  keep their dates and the edit hint says so.
- **Loans.** Progress, paid count, outstanding amount, next instalment and an
  expandable list of every instalment.
- **Report and reminder.** The report can be copied to the clipboard and the
  group reminder can be shared on its own. Amounts are omitted entirely when
  hidden.
- **Reminder fix.** The notification body was built from a recomputed
  suggestion rather than the date and time the manager actually picked. It
  now uses the stored instant, so the alert says the day it will ring.
- **Shelf and empty states.** A glance that counts started funds, upcoming
  starts, paid progress and draws; cards that state "starts in …", "ready to
  draw", "winner waiting" or "settled"; a clear empty state, a failed-load
  state and a warning for unreadable records.
- **Validation and edge cases.** Stored months must be the first day of a
  Jalali month (`month`, member `from`/`until`, share-change `from`);
  duplicate share entries are canonicalized without dropping unknown fields;
  a correction or payout that would make a recorded payout day negative is
  refused; the payment day clamps at month length.

## Records

| Kind | Fields |
| --- | --- |
| `fund` | `v: int` (1), `name/rules: String`, `shareRial: int` (opening share), `paymentDay/drawDay: int`, `start: ISO civil day`, plus the nested lists |
| `shareChanges` | `from: ISO day` (first of a Jalali month), `shareRial: int` — effective share from that month |
| `members` | `id: String`, `person: {name: String, …}`, `shares: int`, `from: ISO day`, optional `until: ISO day` exclusive |
| `payments` | `member: String`, `month: ISO day` (first of Jalali month), `at: ISO day`, `amountRial: int` |
| `draws` | `id: String`, `month/at: ISO day`, `round: int`, `reason: String`, `winner: member id`, `eligible: List<{id, person, shares}>`, `shares: int` snapshot |
| `loans` | `draw: String`, `person: {name, …}`, `at: ISO day`, `amountRial: int`, `instalments: List<{amountRial: int, due: ISO day, paidAt?: ISO day}>` |
| `draft` | Shared form-draft envelope with typed fields, month, entry unit and stable ID for retries |
| `__reminder` | Platform-owned one-time alerts with distinct contribution/draw keys and the same real fund source row |

One row keeps each financial mutation atomic within its ledger. Writes compare
the loaded body with the stored body and preserve unknown fields, including
nested person metadata and unknown fields on share-change entries. The store
does not expose an atomic compare-and-swap across independent editors.
Unreadable or unsupported records remain in storage and the index displays a
warning. The module intentionally has no destructive fund deletion action.

## Decisions

- All fund periods follow the Jalali calendar, even in English. A day beyond a
  month's length clamps to its last day. English dates keep the same month
  boundaries and use transliterated Persian month names.
- Toman is the default display. The account stores whole rials. Example
  `500,000 toman = 5,000,000 rials`. The display unit switch preserves all
  entered values. The opening share is fixed at creation; later changes go
  through the effective-dated list.
- One chance per active person. Shares multiply contributions. An unpaid
  contribution does not automatically bar someone from the draw. A round
  restarts once all currently active members have won. Only the effective
  pick counts toward the round, and a later month's result closes earlier
  draws to changes.
- New members can join from the current month or a later one. Departures
  affect the next month. No automatic refunds or transfers are assumed.
  An existing member's shares are fixed in that membership entry.
- There is one full contribution per member/month. Cash is confirmed
  contributions and instalments minus confirmed payouts. Payouts are limited
  to the recorded balance. Corrections that would make a recorded payout
  day go negative are refused. The ledger uses day granularity.
- Instalments contain principal only. The final instalment holds the
  remainder, keeping the total exact. Recording a repayment early is allowed.
- The manager schedules two one-time alerts from the next open due dates.
  The store requires an actual fund source row for each alert. The shared
  reminder control derives its key from that row, so the two controls use
  the store's supported reminder calls with distinct keys. `keepUp` rolls
  each alert to the fund's next contribution or draw day at the same clock
  time; a cleared alert has no record and stays off.
- The index deliberately shows no amounts. The detail page has a per-session
  eye control; hiding masks the month, members, loans, report and reminder.
- A private family or colleagues' fund is ordinarily an informal arrangement,
  not a licensed institution; this module is a ledger for the group's own
  rules, not a claim of regulatory compliance. Contributions carry no
  interest and no profit share. Bylaws in the references concentrate on the
  awkward cases — late payment, leaving mid-round, guarantees, draw order and
  what happens when a member cannot pay — so the app makes those visible and
  leaves the consequence to the group's written rules.
- Research observed more than one local approach to draw chances and share
  handling. [Hamyan's developer guide](https://blog.hamyanapp.com/training-software-hamian-sandogh-gharzolhasane/)
  covers member shares and monthly dues, while a
  [published family-fund rulebook](https://s-family402.blogfa.com/post/4)
  assigns each share a draw number. These are product examples. The
  one-person rule in this module is an explicit choice for the supplied brief.
- Further Iranian references used for wording and flow:
  [Pand's family-fund article](https://pand-co.com/what-is-the-family-loan-fund/),
  [Vamilon's sample bylaws](https://vamilon.com/blog/family-loan-conditions),
  [Vindad's bylaws](https://vindad.com/blog/%D8%A7%D8%B3%D8%A7%D8%B3%D9%86%D8%A7%D9%85%D9%87-%D8%B5%D9%86%D8%AF%D9%88%D9%82-%D9%82%D8%B1%D8%B6-%D8%A7%D9%84%D8%AD%D8%B3%D9%86%D9%87-%D8%AE%D8%A7%D9%86%D9%88%D8%A7%D8%AF%DA%AF%DB%8C/),
  [Rokla's qard-al-hasan contract](https://rokla.ir/blog/good-loan-agreement/),
  [Bourseiness on setting one up](https://www.bourseiness.com/20984/family-fund-loan) and
  [Hamyan's sample bylaws](https://hamyanapp.com/blog/nemoone-asasname-sandogh-khanevadegi).

| Shared rule | Implementation |
| --- | --- |
| Dates | Nex month/date APIs, pure `FundDues.duesBetween`, local-midnight due dates, strict first-of-month validation |
| Money | Whole `*Rial` amounts, Toman/Rial and Persian digits, effective share through `shareFor` |
| People | `person.name` with surrounding metadata retained |
| Summary | Pure private `summarize` for fund records |
| Unknown data | Original fund body and nested unchanged fields spread into writes; unknown share-change fields kept |
| Draft and Undo | Shared form draft and copied guard. Correction and departure banners offer guarded Undo |
| Reminders | Two module-store alerts. On-day default with explicit date/time control and localized purpose |
| Sharing | System text share after preview, clipboard copy, amount masking, group reminder |
| Theme | Nex app bars, panels, hero, routes, sheets, adaptive segments and shared transition |

Copied the money references and their local dependencies from `lent_borrowed`
(`money_format.dart`, `amount_field.dart`, `currency_field.dart`), plus
`draft_guard.dart` and `form_draft.dart`. The currency picker is a reference
copy. Fund entry is explicitly IRR.

## Guide

**English.** Create a fund, pick its first month, and add each member with
their share count. Tick contributions after receipt; tap a member to see what
is still open. Review eligible names before drawing; the result is saved as
soon as it appears. Record the payout after disbursing the loan and tick
received instalments in Loans. Raise the share from Members when the group
agrees — it applies from the month you pick and never changes past payments.
Review the monthly report before sharing or copying it.

**فارسی.** نام صندوق، مبلغ هر سهم و ماه شروع را وارد کنید. برای هر عضو تعداد
سهم را مشخص کنید و پس از دریافت واریزی، تیک همان ماه را بزنید؛ با لمس هر عضو
می‌بینید چه ماه‌هایی باز مانده‌اند. پیش از قرعه فهرست افراد واجد شرایط را
ببینید؛ نتیجه همان لحظه ذخیره می‌شود. بعد از پرداخت واقعی وام، آن را ثبت کنید و
اقساط دریافتی را در بخش وام‌ها تیک بزنید. وقتی گروه توافق کرد، سهم را از بخش
اعضا بالا ببرید؛ از ماهی که انتخاب می‌کنید اعمال می‌شود و واریزی‌های گذشته را
عوض نمی‌کند. گزارش ماه را پیش از هم‌رسانی یا کپی مرور کنید.

## Changelog

**English.** Effective-dated share changes, a single draw sheet with an
in-sheet result and redraw reason, round transparency, member history and
quick record, editable fund details, richer loans, a report that can be
copied and a group reminder, privacy-first shelf cards, and a reminder body
that names the picked day and time.

**فارسی.** تغییر سهم از ماه مشخص، برگهٔ یکپارچهٔ قرعه با نتیجه و دلیل قرعهٔ
دوباره، شفافیت دورها، سابقه و ثبت سریع عضو، ویرایش مشخصات صندوق، وام‌های
کامل‌تر، گزارش قابل کپی و یادآور گروهی، کارت‌های بی‌مبلغ در فهرست، و متن
یادآوری بر اساس همان روز و ساعتی که انتخاب شده است.

## Limitations and platform requests

- No destructive deletion of a fund: a mistaken fund can be emptied of
  members and payments only through the existing correction flows. A guarded
  archive/delete flow (with a full JSON export) is the next safe step.
- Alerts are per-record one-time notifications that `keepUp` rolls monthly.
  A native monthly recurrence and a single control for both alerts would be
  cleaner; the shared reminder API currently supports one key at a time.
- Sharing is text. A monthly status image with the fund name and a small Nex
  mark would travel better in Telegram and WhatsApp.
- One manager edits on one device. The store has no cross-device
  compare-and-swap, so two managers editing the same fund at once is not a
  supported flow.
- Contributions are full-share only; partial payments and refunds are
  deliberately out of the model.
- The report states the balance as of today, not the selected month's end.
  The label says so; a month-end close could be a future addition.

## Checks

Run from `apps/client` with the repository's pinned Flutter:

- `flutter analyze --no-pub --fatal-infos lib/modules/family_fund test/modules/family_fund`
  → `No issues found!`
- `flutter test --no-pub test/modules/family_fund --reporter compact`
  → `00:17 +37: All tests passed!` (model, widget, reminder upkeep, RTL/dark/
  compact draw sheet, creation, draw/redraw, payout/instalments, member sheet,
  edit, share change, shelf, empty state, report privacy, share-entry extras,
  empty-fund dues, and a paid month's reminder moving on).
- `flutter test --no-pub test/module_kit_test.dart test/module_shared_rules_test.dart
  test/module_glance_test.dart test/module_hero_rebuild_test.dart
  test/module_infrastructure_test.dart test/module_preview_test.dart
  test/module_reminder_alarm_test.dart test/modules_test.dart
  test/ui_consistency_test.dart test/motion_test.dart test/text_field_rule_test.dart
  test/menu_rule_test.dart test/sheet_swipe_test.dart test/nex_text_field_test.dart
  test/module_kit test/app_guide_test.dart test/guide_screen_test.dart
  test/whats_new_test.dart test/version_test.dart`
  → `00:24 +245: All tests passed!`
- The whole client suite was not re-run on this branch; the focused gates above
  are the ones this module touches. Device-only checks (real notifications,
  system share sheet, keyboard) remain in the checklist below.

## Device checklist

1. Create a fund with a Persian amount and choose Esfand as its first month.
   Reopen an unfinished form.
2. Add one member with two shares, record a contribution, then raise the share
   from the next month and confirm the old month still reads the old amount.
3. Preview the draw pool, record a draw, then redraw with a written reason.
   Check both attempts and the round count in history.
4. Log the payout, confirm the result is locked, and record an instalment.
   Check the next instalment, all instalments and the balance with amounts
   shown and hidden.
5. Copy the report, share the reminder, and confirm hidden amounts never
   appear in either.
6. Set both alerts and confirm they remain separate and ring at the chosen
   clock time. Test on a device with notifications enabled.

## Open questions

Ask three to five real managers about one-person versus one-share chances,
whether unpaid members may win, what starts a new round, joining and leaving
mid-round, and how they handle partial contributions, refunds and transfers.
Also validate whether the group should see all names or only totals in the
report, and whether managers prefer automatic monthly alerts or the current
explicit pick.
