# Cheques & instalments / چک و قسط

## Audit and completion

Starting main: `4ce8d52354a37d253eaa9643a4f8fd412b4a40af` (initial research
started on aae8cbba; main's documentation-only advancement was retained).
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
| AI | Redacted context / draft proposal contracts | Kept, disconnected from AI until an approved host adapter exists |
| Integration | Temporary local wiring | Excluded from delivery per prompt 12 |

## 1. What it does

Screens: Follow up; All (query/direction/status/date range); rolling Outlook;
Jalali month and its daily cash calendar; cheque detail/history; cheque editor;
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
purpose payment/guarantee; amountRial a canonical positive whole-Rial decimal
string (max 24 digits); unit rial/toman; party, bank, account alias, number,
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

Kind `plan`, v1: title; totalRial (whole-Rial decimal string stored once), count
1..120, months 1..12, first civil date, calendar jalali/gregorian, paid mapping
zero-based index strings to actual paid civil dates; remind; beforeDays 1..30;
minutes. The first due date's original day anchors every interval; nonexistent
days clamp to that month's last day and later months recover the original day.
Amounts divide exactly, with any remainder in the last instalment. Paid
schedules are locked against structural edits until payments are unmarked.
Unchecking a payment is an explicit reversible local correction, not a refund.

Derived instalment IDs `plan:<planId>:<zeroBasedIndex>` are never separately
persisted as cheque records. Totals combine actual cheques and these derived
rows without duplicating principal. Their source reminder kind/id is plan/planId.
A future Recurring/due-radar adapter should read outstanding cheque remaining
amounts/due dates and derive outstanding plan dates with `InstalmentPlan`.
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

BigInt arithmetic and canonical decimal strings keep large Rial values exact.
Civil dates do not shift through UTC. Persian dates use the host's Jalali API;
the monthly cash view always groups by Jalali month. Forecast ratios are drawing
values only. Lists use owned query/scroll controllers and IndexedStack to retain
state (the stateful-view exception documented by NexSegmentSwap); swapping the
transient follow-up heading uses the shared fade. FABs have heroTag null.
No queries are triggered per rendered card or by scrolling. All Dart files are
under 400 lines, including the editor's private part file.

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

Only this module's source/test folders are delivered. Maintainers must register
ChequeManagerModule, retire the cheque-manager plan and assign a hero hue. No
rollout enabling is included. Without registration, the module is not in the UI.
Exact notification routing needs host registrations: cheque -> ChequeDetail;
plan -> PlansPage with instalment index from its reminder key. Until then the
host's generic notification fallback opens the module rather than its detail.

Camera/photos, OCR, note links, AI tools, file export/image sharing and a phone
text share-sheet API are not exposed by the current module API. No private
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

Temporary local module/hue/notification wiring and catalog-count adjustments
were used to run integration checks, then removed before delivery. No gate,
rollout, shared API, registry, other module, app version or global changelog
change is included in this branch.

- `flutter analyze --no-pub --fatal-infos`: no issues.
- Changed module/test Dart format check: 31 files, zero remaining changes;
  all individual Dart files under 400 lines. `git diff --check`: clean.
- `flutter test --no-pub test/modules/cheques test/module_kit_test.dart
  --timeout 60s --reporter expanded`: **169 passed** (114 module cases,
  including 80 visual layout cases), with temporary local registration.
- Full client `flutter test --no-pub --reporter expanded` with that temporary
  integration: **07:41 +4200 ~4: All tests passed!** Four pre-existing skips.
- Temporary shared wiring was restored byte-for-byte to main before staging;
  the delivered tree is only this module's two folders. Running the gate in
  a checkout requires the maintainer registration described above.
- Backend/other-package suites, APK/device, TalkBack and measured performance
  were not run or claimed.

Tests cover exact amounts, numeric scripts, bad dates, guarantees, transfers,
partial/full settlements and reversal, unknown data, draft/read/write/cleanup
failures, stale actions, Undo, alarm privacy/withdrawal/stale-plan cleanup,
redacted AI proposals, exact instalment division, Gregorian/Jalali month-end
anchoring, paid dates, monthly view and visibility. Layout review covers FA/EN,
light/dark, 390x844 and 320x640 at text scale 2 with reduced motion. Screenshots
are synthetic data. No Android APK/device, TalkBack or performance trace claimed.

## Device checklist

1. Register locally while keeping Soon; open cheque editor in Persian and English.
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
for owner testing before rollout. API-based image/OCR/AI/sharing need separate
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
| plans | [EN](review/cheque_plans_en_light.png) | [FA](review/cheque_plans_fa_dark.png) |
| planEditor | [EN](review/cheque_planEditor_en_light.png) | [FA](review/cheque_planEditor_fa_dark.png) |
| empty | [EN](review/cheque_empty_en_light.png) | [FA](review/cheque_empty_fa_dark.png) |
