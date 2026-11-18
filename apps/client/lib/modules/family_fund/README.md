# Family fund · صندوق خانوادگی

## What it does

A private, offline ledger for a family or colleagues' rotating loan fund.
This is a new module from main commit `004306c13d1878206271d522f882257a417e693f`.
It stays outside rollout pending platform integration and phone review.

- **Funds** opens existing ledgers and creates one with a name, amount per
  share, first Jalali month, contribution day, draw day and optional rules.
- **Month** shows cash recorded to date, payment progress for the selected
  month and which members are overdue. Tick a contribution once to record
  the member's full amount for that month. Earlier months can be revisited
  and late contributions are dated when recorded.
- **Members** keeps join and departure months and the number of shares.
  Recording a departure stops future contributions from the next month.
  Earlier contributions, draws and loans remain available.
- **Draw** previews eligibility and saves the round, date, winner and eligible
  snapshot. A redraw requires a reason, excludes earlier picks for that month
  and preserves all attempts. A disbursed loan locks that month's result.
- **Loans** records a real payout against the selected winner and splits
  principal into due instalments. Tick repayments as received. The balance
  changes on actual ledger entries.
- **Report** previews the fund name, month, paid and pending names, balance
  and winner. The eye control masks amounts in the view and report.

## Records

| Kind | Fields |
| --- | --- |
| `fund` | `v: int` (1), `name/rules: String`, `shareRial: int`, `paymentDay/drawDay: int`, `start: ISO civil day`, plus the following nested lists |
| `members` | `id: String`, `person: {name: String, …}`, `shares: int`, `from: ISO day`, optional `until: ISO day` exclusive |
| `payments` | `member: String`, `month: ISO day` first of Jalali month, `at: ISO day`, `amountRial: int` |
| `draws` | `id: String`, `month/at: ISO day`, `round: int`, `reason: String`, `winner: member id`, `eligible: List<{id, person}>` |
| `loans` | `draw: String`, `person: {name, …}`, `at: ISO day`, `amountRial: int`, `instalments: List<{amountRial: int, due: ISO day, paidAt?: ISO day}>` |
| `draft` | Shared form-draft envelope with typed fields, month, entry unit and stable ID for retries |
| `__reminder` | Platform-owned one-time alerts with distinct contribution/draw keys and the same real fund source row |

One row keeps each financial mutation atomic within its ledger. Writes compare
the loaded body with the stored body and preserve unknown fields, including
nested person metadata. The store does not expose an atomic compare-and-swap
across independent editors. Unreadable or unsupported records remain in storage
and the index displays a warning. The module intentionally has no destructive
fund deletion action.

## Decisions

- All fund periods follow the Jalali calendar, even in English. A day beyond a
  month's length clamps to its last day. English dates keep the same month
  boundaries and use transliterated Persian month names.
- Toman is the default display. The account stores whole rials. Example
  `500,000 toman = 5,000,000 rials`. The display unit switch preserves all
  entered values. Contribution size is set when the fund is created.
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
  the store's supported reminder calls with distinct keys.
- Research observed more than one local approach to draw chances and share
  handling. [Hamyan's developer guide](https://blog.hamyanapp.com/training-software-hamian-sandogh-gharzolhasane/)
  covers member shares and monthly dues, while a
  [published family-fund rulebook](https://s-family402.blogfa.com/post/4)
  assigns each share a draw number. These are product examples. The
  one-person rule in this module is an explicit choice for the supplied brief.

| Shared rule | Implementation |
| --- | --- |
| Dates | Nex month/date APIs, pure `FundDues.duesBetween`, local-midnight due dates |
| Money | Whole `*Rial` amounts, Toman/Rial and Persian digits |
| People | `person.name` with surrounding metadata retained |
| Summary | Pure private `summarize` for fund records |
| Unknown data | Original fund body and nested unchanged fields spread into writes |
| Draft and Undo | Shared form draft and copied guard. Correction and departure banners offer guarded Undo |
| Reminders | Two module-store alerts. On-day default with explicit date/time control and localized purpose |
| Sharing | System text share after preview, with amount masking |
| Theme | Nex app bars, panels, hero, routes, sheets, adaptive segments and shared transition |

Copied the money references and their local dependencies from `lent_borrowed`
(`money_format.dart`, `amount_field.dart`, `currency_field.dart`), plus
`draft_guard.dart` and `form_draft.dart`. The currency picker is a reference
copy. Fund entry is explicitly IRR.

## Guide

**English.** Create a fund, pick its first month, and add each member with
their share count. Tick contributions after receipt. Review eligible names
before drawing. Record the payout after disbursing the loan and tick received
instalments in Loans. Review the monthly report before opening Share.

**فارسی.** نام صندوق، مبلغ هر سهم و ماه شروع را وارد کنید. برای هر عضو تعداد
سهم را مشخص کنید و پس از دریافت واریزی، تیک همان ماه را بزنید. پیش از قرعه
فهرست افراد واجد شرایط را ببینید. بعد از پرداخت واقعی وام، آن را ثبت کنید و
اقساط دریافتی را در بخش وام‌ها تیک بزنید. گزارش ماه را پیش از اشتراک مرور کنید.

## Changelog

**English.** Added a private family-fund ledger with monthly contributions,
draw history, loan instalments, manager reminders and a shareable report.

**فارسی.** صندوق خانوادگی با ثبت واریزی ماهانه، سابقهٔ قرعه، اقساط، یادآور مدیر
و گزارش آمادهٔ گروه اضافه شد.

## Platform requests

- Register `FamilyFundModule()` in `nexModules` as part of the platform's
  integration, select a hue, and add the Soon catalog entry if desired.
  Registration used for the local kit check is deliberately excluded from the
  branch. The kit's registration assertion therefore needs the integration
  on the branch where it is reviewed for rollout. Update the two catalog
  inventory expectations in `test/module_preview_test.dart` for the added
  module on that integration branch.
- Add image sharing for a monthly status card with the fund name and a small
  Nex mark. Until then, the system share sheet carries text.
- Add a shared multiple-alert control for one record, and Jalali monthly
  recurrence if required. The existing controls schedule separate one-time
  dates. Alert delivery can only be tested after enabling this module.

## Checks

- Flutter toolchain pinned by the repository. Dependencies resolved with an
  enforced lockfile.
- `flutter test --no-pub test/module_kit_test.dart test/module_shared_rules_test.dart test/modules/family_fund --dart-define=NEX_CAPTURE=lib/modules/family_fund/review --reporter expanded`
  with temporary local registration reported `00:05 +127: All tests passed!`.
- `flutter analyze --no-pub --fatal-infos` reported `No issues found!`.
- Whole client suite: `flutter test --no-pub --concurrency=6 --reporter expanded`
  ran with temporary registration and ended at `05:53 +4437 ~5 -3`.
  One UI consistency failure was fixed by using the shared button styles.
  The two catalog checks expected the original count of 16 add-ons, and
  counted 17 with temporary registration.
- Final recheck of UI consistency, kit, shared rules and the module with
  temporary registration reported `00:12 +135: All tests passed!`.
  After removing the temporary registry entry, the seven catalog checks
  passed. The full suite was not rerun after these focused checks.
- Visual review includes Persian and English in light and dark, including
  compact screens at 2× text. Screenshots use seeded demo records.

| Screen | فارسی | English |
| --- | --- | --- |
| Month | [Dark](review/fa_dark_month.png) | [Light](review/en_light_month.png) |
| Members | [Dark](review/fa_dark_members.png) | [Light](review/en_light_members.png) |
| Report preview | [Dark](review/fa_dark_report.png) | [Light](review/en_light_report.png) |

## Device checklist

1. In a locally enabled QA build, create a fund with a Persian amount and
   choose Esfand as its first month. Reopen an unfinished form.
2. Add one member with two shares, record a contribution and try Undo.
3. Preview the draw pool, record a draw, then redraw with a written reason.
   Check both attempts in history.
4. Log the payout, confirm the result is locked, and record an instalment.
   Check the balance and report with amounts shown and hidden.
5. Set both alerts and confirm they remain separate. Test on a device with
   notifications enabled. Reopen the report in the system share sheet.

## Open questions

Ask three to five real managers about one-person versus one-share chances,
whether unpaid members may win, what starts a new round, joining and leaving
mid-round, and how they handle partial contributions, refunds and transfers.
Also validate whether the group should see all names or only totals in the
report, and whether managers prefer automatic monthly alerts.
