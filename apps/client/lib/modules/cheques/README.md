# Cheques & instalments / چک و قسط

## Audit and completion

Starting main: `4ce8d52354a37d253eaa9643a4f8fd412b4a40af` (initial research
started on aae8cbba; main's documentation-only advancement was retained).
PR repair and shared-rules baseline: `9050ad171a5845f8c512927198f73e7007f7db44`.
Final integration includes main `e3edff3fc5e41ad1c556ab8b96a302940fa83b16`
(the owner’s 2.8.3 updates, including module ordering).
The owner then explicitly selected prompt 12 and the cheques brief. The actual
brief path is `docs/prompts/module-briefs/cheques.md` (not `.md.md`). Work runs
in the cloud workspace on **agent/module-cheques.md**. No PR is to be opened.

The earlier, uncommitted cheque work has been kept and extended:

| Area | Previous work | Result |
| --- | --- | --- |
| Cheques | Both directions, guarantee, settlements, history | Kept; registered/handed-over stages added |
| Forecast | Rolling 4 weeks | Kept; Jalali-month totals/net and daily cash calendar added |
| Instalments | Absent | Added exact schedules, 4-month template, paid dates and reversible checkboxes |
| Priority | Sorted follow-up | Past-due/bounced section separated at the top |
| Privacy | Private notification text | Amount visibility control added; named amount alerts per new brief |
| State/motion | Persistent list state, no FAB hero | Kept; stateful lists retained, transient follow-up heading uses NexSegmentSwap |
| Robustness | Drafts, conflict checks, atomic events, Undo | Kept; plan stale-alarm cleanup and tests added |
| AI | Redacted context / draft proposal contracts | Removed in review (2.8.4): unused, and the brief asks for no AI |
| Integration | Missing registry line caused PR CI failure | Registered for the owner’s PR repair; remains Soon |

## Maintainer review (2.8.4)

Checked against the brief, `docs/18` and the design rules; merged and made
available, with these changes:

- **Instalments in whole tomans.** A total in whole tomans is divided in
  whole tomans, the last instalment taking what does not divide: ten
  million tomans in three read 3,333,333.3 tomans before.
- **The month view lists the days something falls due**, not every day of
  the month — thirty cards, most of them "nothing due", buried the few that
  matter. A day more goes out than comes in has a red edge and says so; an
  empty month says so once.
- **The unused AI contract is gone** (`ai_contract.dart` and its tests):
  nothing called it, and the brief asks for no AI.
- The module's hero has its own hue (222, the sky it declares), and the
  "On the way" entry it replaces (`cheque-manager`) is retired.

## 1. What it does

Screens: Follow up; All (query/direction/status/date range); rolling Outlook;
Jalali month list and daily cash flow; cheque detail/history; cheque editor;
confirmed settlement/status editor; instalment plans and plan editor.
All features are offline. No bank/Sayad connection, legal advice, card data or
banking passwords. A self-reported status never establishes authenticity.
Expected receipts and planned net cash flow are not a bank balance.

The eye button hides known monetary values (including editing inputs) without
changing stored data. Names and other text remain visible. It is a session UI
control, not encryption or screenshot protection. Named notifications can expose
the party/amount on the lock screen; reminders are explicitly off until selected.

## 2. Record shapes and compatibility

Namespace `cheques`, kind `cheque`, v1. Fields: direction incoming/outgoing;
purpose payment/guarantee; amountRial a positive whole-Rial integer; unit
rial/toman; person object with name and preserved future fields; legacy party
string retained as a compatibility alias; bank, account alias, number,
sayad empty/16 ASCII digits, note; due/followUp civil Gregorian `YYYY-MM-DD`;
status; archived (derived from closed status for host alarm reconciliation);
events; sayadState unknown/todo/checked and sayadCheckedDay; remind,
reminderDays (max 3 chosen offsets), minutes 0..1439. No float money.

Statuses: active (written/open), registered (user reports Sayad registration),
handed, deposited, bounced, settled, transferred, returned, cancelled. Closed
states are settled/transferred/returned/cancelled. Events retain id, kind,
day, amountRial, previous/next status, target, note and voided. A full settlement
closes the cheque. Reversal voids the latest active event and restores its prior
state without erasing history. Active history locks face amount/direction/purpose.
Max 500 events per cheque. Unknown fields survive valid edits; unsupported or
corrupt records stay visible, protected from editing and excluded from totals.

Kind `plan`, v1: title; totalRial (whole-Rial integer stored once), count
1..120, months 1..12, first civil date, calendar jalali/gregorian, paid mapping
zero-based index strings to actual paid civil dates; remind; beforeDays selected from 1/3/7/14/30;
minutes. The first due date's original day anchors every interval; nonexistent
days clamp to that month's last day and later months recover the original day.
Amounts divide exactly, with any remainder in the last instalment. Paid
schedules are locked against structural edits until payments are unmarked.
Unchecking a payment is an explicit reversible local correction, not a refund.

Derived instalment IDs `plan:<planId>:<zeroBasedIndex>` are never separately
persisted as cheque records. Totals combine actual cheques and these derived
rows without duplicating principal. Their source reminder kind/id is plan/planId.
A future Recurring/due-radar adapter consumes the pure `ChequeDues` snapshot
and `duesBetween` contract described below.
Guarantees, transferred and settled rows are excluded from planned cash totals.

Host v1 drafts: cheque:new, cheque:<id>, action:<id>, plan:new, plan:<id>.
Baseline fingerprints/stable IDs prevent stale drafts and duplicate cleanup
retries. Read failures block editing; save failures retain inputs. Cheque delete
atomically removes cheque/edit/action drafts; Undo restores its saved raw cheque,
not discarded unsaved drafts, and refuses ID/Sayad collisions. Plan delete also
removes its edit draft; Undo restores raw plan/payment dates. Standard backups
apply. No released namespace or schema has been renamed by this new module.

## 3. Engineering and boundaries

A cheque event and its resulting financial state change in one store write.
Repository queues and fresh raw-body comparisons reject stale writes; the store
has no cross-process CAS, so independent external writers remain a limitation.
Plan mutations also write one complete record. Expired/obsolete future alarm
slots are withdrawn; shown notifications are preserved during upkeep. Plan edits
remove orphaned slots after schedule changes. Financial save success and
notification scheduling failures are treated separately.

BigInt arithmetic keeps totals and legacy large values exact. New form input
uses the reference maximum of 9,007,199,254,740,991 rials. Legacy canonical
24-digit strings are still read without rounding; unchanged editing and full
settlement remain possible. New amounts use integer rials; legacy values
above the reference’s interoperable range retain their exact string on write.
A value outside Dart’s signed integer range has shared amountRial=null,
never a saturated/truncated amount.
The source record and local totals retain the complete value.
Civil dates do not shift through UTC. Persian dates use the host's Jalali API;
the monthly cash view always groups by Jalali month. Forecast ratios are drawing
values only. Lists use owned query/scroll controllers and IndexedStack to retain
state (the stateful-view exception documented by NexSegmentSwap); swapping the
transient follow-up heading uses the shared fade. FABs have heroTag null.
No queries are triggered per rendered card or by scrolling. All Dart files are
under 400 lines, including the editor's private part file.

## Shared across modules — 2.8.2 compliance

1. **One calendar:** no independent calendar/grid. The Jalali cash-flow month
   list stays a small module view, replaceable by the future life calendar.
   `ChequeDues.fromRecords(records)` builds an immutable local snapshot of both
   cheque and plan records. `duesBetween(from, to)` accepts inclusive civil
   days, returns stable IDs and local midnight, source cheque/id or plan/id,
   signed remaining rials, done and private=true. Guarantees are review dates
   without money. Completed/returned/transferred rows are done with zero cash
   promise. Corrupt/future records are excluded. Month, outlook and reminders
   consume this same function; no host calendar integration is claimed.
2. **Money:** copied `money_format.dart`, `amount_field.dart`,
   `currency_field.dart` and their helper files from `lent_borrowed` with the
   same public calls. Only module-local strings imports were adapted. All
   three amount editors use the reference grouping/words and exact parsers;
   display uses its formatting. Rial/Toman choice remains a presentation value.
   No foreign-currency UI is added to an Iranian cheque product. Legacy large
   records use the exact compatibility path described above.
3. **People:** writes add `person.name`; old `party` remains readable. Editing
   a name merges into the existing object, keeping id/cards/ibans/unknown keys.
   No new card/IBAN collection or credentials are introduced.
4. **Summary:** pure `summarize(ModuleRecord)` returns title/detail/private for
   supported saved cheques/plans; null for drafts or invalid/foreign records.
   Nothing is connected to main search, timeline, assistant or daily brief.
5. **Unknown fields:** repositories merge parent fields, nested person fields
   and event fields; conflict checks, atomic event writes and raw Undo remain.
6. **Drafts/Undo:** copied `draft_guard.dart` from the reference with `DraftGuard`
   calls; only its reference-only draft type was adapted to exported
   `NexModuleFormDraft`, and strings to this module. No new draft mechanism.
7. **Reminders:** cheque choices are 0/1/3/7/14/30. Plans always include due day
   plus one of 1/3/7/14/30; an existing custom legacy offset is kept until
   explicitly changed, but cannot be newly entered. Named alerts include
   amount, relative lead time and the exact localized due date.
8. **Sharing/privacy:** explicit text Share uses `nexModuleShareText`, with the
   same amount masking as the screen. No photos/image sharing; platform request
   remains. Hidden input fields also hide the reference amount-in-words helper.
9. **Look/state:** choices use `NexAdaptiveSegments`; stateful views retain
   controllers and scrolling. Transient views use `NexSegmentSwap`; every FAB
   keeps heroTag:null. Main hero uses `NexModuleHero`.

## 4. Research and assumptions (2026-11-17)

Desk research is not a measured market size or user-demand survey. Product
priorities are design inferences, expanded by the owner's selected brief.

- Saye developer listing: https://apps.apple.com/us/app/id1139543189
- Didasood: https://didasood.com/features/مدیریت-چک-و-هزینه
- Kavak: https://kavak.ir/modules/cheque-management/
  These establish reminders, status tracking and cheque circulation as existing
  product functions. No claims about preventing bounced cheques are endorsed.
- https://caspianci.ir/terms-and-conditions/ distinguishes Sayad issuance,
  receipt confirmation and transfer. Historical reference, not current legal
  certification. Reproduced CBI guidance dates to 1399; the linked Bank Melli
  news endpoint timed out during research. No SMS number, fee, banking-service
  limit, holiday adjustment or legal deadline is hard-coded from it.

The brief's market statistics were not independently verified and are not
repeated as product claims. Scheduled net flow is never described as real funds.

## 5. Guide / راهنما

FA: چک دریافتی یا پرداختی، مبلغ و واحد، طرف حساب و سررسید را ثبت کن. ضمانت
موعد پیگیری جدا دارد و در چشم‌انداز پول حساب نمی‌شود. تسویهٔ جزئی، انتقال و
تغییر وضعیت را در جزئیات ثبت و تأیید کن. برای اصلاح، آخرین رویداد را برگردان.
از آیکون اقساط برنامهٔ خرید یا وام بساز؛ کل مبلغ به ریال، تعداد، تاریخ اول و
فاصلهٔ ماهانه را انتخاب کن. قالب چهارقسطی آماده است. قسط پرداخت‌شده را تیک بزن؛
اگر اشتباه بود تیک را بردار. نمای ماه جمع تعهدها و روزهای پرداخت بیشتر را نشان
می‌دهد. چشم مبلغ‌ها را پنهان می‌کند؛ یادآورِ انتخاب‌شده نام و مبلغ را نشان می‌دهد.
هیچ ثبت، تأیید یا انتقالی در بانک/صیاد انجام نمی‌شود.

EN: Register direction, amount/unit, party and due date. Guarantees have a review
date and no forecast cash flow. Confirm settlements/transfers/status changes in
details; reverse the latest mistaken event. Open Plans to add a purchase/loan,
whole-Rial total, count, first date and monthly interval; a four-month template
is available. Check paid instalments, uncheck a mistake. Month shows scheduled
cash flows and days when payments exceed expected receipts. The eye hides
amounts; opted-in notifications include the name/amount. No bank action occurs.

## 6. Changelog

FA: چک و قسط: گردش و تسویهٔ جزئی چک، اقساط با تقسیم دقیق، تقویم نقدی ماه شمسی،
تفکیک موعدگذشته/برگشتی، پنهان‌کردن مبلغ‌ها و یادآور نام‌دار؛ بدون اتصال بانکی.

EN: Cheques & instalments: exact settlements/schedules, Jalali monthly cash
calendar, separate overdue/bounced follow-up, hidden amounts and named reminders.

## 7. Platform requests and future integration

For the owner’s follow-up request to repair PR CI, the existing gate required
maintainer registration. This branch now includes only the import/list entry
and the corresponding catalog-count/list traversal assertions outside the module folders;
no rollout setting, shared API or gate was changed. The module stays Soon.
Maintainers can retire the old cheque-manager planned entry and assign its hue.
Exact notification routing needs host registrations: cheque -> ChequeDetail;
plan -> PlansPage with instalment index from its reminder key. Until then the
host's generic notification fallback opens the module rather than its detail.

Camera/photos, OCR, note links, AI tools and file export/image sharing
are not exposed by the current module API. The existing text share API is now
used by the detail page’s Share action; bank/account/Sayad/note are omitted
and hidden amounts stay hidden. No private
imports/platform channels are used to substitute for them. Manual entry works
without those APIs. A future Recurring/due-radar integration is described by the
record shapes above but is not built.

ChequeContextV1 is a bounded read-only projection (default 12/max 20) of locally
computed amounts/dates/reference IDs; names require an explicit argument. Bank,
account, Sayad identifiers, notes and history are excluded. A future host combines
stored cheques with derived plan rows and requires opt-in, cache/in-flight consent
revocation and source citations. ChequeDraftProposalV1 validates suggested fields
and uncertainty without saving. No AI connection or misleading consent toggle
has been added, and no model may calculate or silently change a financial amount.

## 8. Verification

Repo SDK constraint is Dart ^3.13 and CI pins 3.13.7; therefore actual checks use
Flutter 3.47.9 / Dart 3.13.7, not the stale 3.35 example in the prompt. Locked
`pub get --enforce-lockfile` completed without dependency/lockfile modifications.
Host SQLite was built from vendored repository source outside the repository.

The previous delivery used temporary registration for 169 focused checks and
4,200 full-client checks, then removed it as prompt 12 required. The resulting
PR failed the existing registry assertion. The owner requested repair; minimal
registration is now committed and verified in the delivered tree, with no
rollout or gate edits. Final checks on the 2.8.3 integration:

- `flutter pub get --enforce-lockfile`: completed; lockfile unchanged.
- `flutter analyze --no-pub --fatal-infos`: no issues. Analysis of all changed
  module/test files after the last edits also reports no issues.
- Focused final run (module, module kit, shared rules, preview, catalog and
  module arrangement): **01:17 +259: All tests passed!** This includes the
  repaired catalog test and the final reminder wording in both languages.
- Full client suite was run: **15:18 +4281 ~4 -1**. Its only failure was the
  pre-existing catalog test's forward-only scrolling, exposed by registering
  another Soon card alongside 2.8.3's layout. Its registry iteration crosses
  the Available/Soon sections. Each lookup now starts at the top; assertions
  are unchanged, and the complete catalog suites pass in the 259-test rerun.
  The full suite was not repeated after the final catalog/reminder-text edits;
  all affected suites were rerun together as reported above.
- Formatting and `git diff --check`: clean; every module/test Dart file stays
  within 400 lines. Review gallery: 22 synthetic screenshots, Persian dark and
  English light. Layout checks include both themes/languages, 2x text and
  narrow screens; status choices also have a wide-screen check.
- No APK/device, TalkBack, backend or measured performance result is claimed.

Tests cover exact amounts, numeric scripts, bad dates, guarantees, transfers,
partial/full settlements and reversal, unknown data, draft/read/write/cleanup
failures, stale actions, Undo, alarm privacy/withdrawal/stale-plan cleanup,
redacted AI proposals, exact instalment division, Gregorian/Jalali month-end
anchoring, paid dates, monthly view and visibility. Layout review covers FA/EN,
light/dark, 390x844 and 320x640 at text scale 2 with reduced motion. Screenshots
are synthetic data. No Android APK/device, TalkBack or performance trace claimed.

## Device checklist

1. Keep Soon; open cheque editor locally in Persian and English.
2. Enter Rial/Toman amounts and a Jalali date; test back/draft resume and tab state.
3. Make partial/full settlements, transfers and reversals; compare exact balance.
4. Add a 4-month plan; test month-end/leap dates, checking/unchecking payments.
5. Check month totals/calendar, guarantees and past-due/bounced separation.
6. Hide/show money on home, details and forms, including after route changes.
7. Enable notifications with a future date; inspect name/amount, change dates,
   shorten plans, pay an instalment and verify old future alarms disappear.
8. Delete/Undo both record types; test backup restore and disabled-module routing.

## Open questions

No owner answer blocks this drop-in delivery. User research should decide the
preferred unit for plan entry, practical instalment-count limits and lock-screen
privacy defaults. Current plan entry is explicitly Rial; cheque entry supports
both units. Real-device notification routing/permissions and accessibility remain
for owner testing before rollout. API-based image/OCR/AI need separate
maintainer work; no hidden network or bank integration is proposed.

## Review gallery

| Screen | English light | Persian dark |
| --- | --- | --- |
| follow | [EN](review/cheque_follow_en_light.png) | [FA](review/cheque_follow_fa_dark.png) |
| all | [EN](review/cheque_all_en_light.png) | [FA](review/cheque_all_fa_dark.png) |
| outlook | [EN](review/cheque_outlook_en_light.png) | [FA](review/cheque_outlook_fa_dark.png) |
| month | [EN](review/cheque_month_en_light.png) | [FA](review/cheque_month_fa_dark.png) |
| detail | [EN](review/cheque_detail_en_light.png) | [FA](review/cheque_detail_fa_dark.png) |
| editor | [EN](review/cheque_editor_en_light.png) | [FA](review/cheque_editor_fa_dark.png) |
| event | [EN](review/cheque_event_en_light.png) | [FA](review/cheque_event_fa_dark.png) |
| status | [EN](review/cheque_status_en_light.png) | [FA](review/cheque_status_fa_dark.png) |
| plans | [EN](review/cheque_plans_en_light.png) | [FA](review/cheque_plans_fa_dark.png) |
| planEditor | [EN](review/cheque_planEditor_en_light.png) | [FA](review/cheque_planEditor_fa_dark.png) |
| empty | [EN](review/cheque_empty_en_light.png) | [FA](review/cheque_empty_fa_dark.png) |
