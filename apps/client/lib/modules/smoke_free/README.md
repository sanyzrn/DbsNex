# Smoke-free

## 1. What it does

First-run setup asks days since quitting, prior cigarettes/day, pack price in
the chosen currency and cigarettes/pack. All baseline fields can be corrected.
The dashboard shows calendar days, estimated cigarettes avoided and money kept,
with the input basis and rounding/day-boundary explanation. Logging a craving
is the primary action: intensity, triggers, coping choice, note and timestamp.
Earlier logs can be edited/deleted with Undo; patterns count each trigger once
per log. History remains accessible even when no attempt is active.
“I smoked” explicitly records a lapse, optionally restarting today; a separate
“Start a new attempt” action restarts without labelling it a lapse. Both preserve
earlier attempts, currency/baseline and cravings. A same-day attempt is honestly
labelled as ending on the day it began. Setup/craving editors keep local drafts.
There are no health claims, recovery milestones, treatments, notifications,
external links/exports, sensors, accounts, telemetry or AI features.

## 2. Records

Kind `quit`, store-generated stable ID, schema v2:

```json
{"v":2,"startedAt":"2026-10-07T09:00:00.000","cigarettesPerDay":10,"pricePerPackMinor":650,"currency":"USD","currencyDecimals":2,"perPack":20,"endedAt":null,"endedWhy":null}
```

`startedAt`: ISO timestamp; `cigarettesPerDay`: integer 0–1000;
`pricePerPackMinor`: integer currency minor units; `currency`: three-letter code;
`currencyDecimals`: integer 0–4; `perPack`: integer 1–100 (default 20);
`endedAt`: ISO timestamp or null; `endedWhy`: lapse/restart or null.
The newest record with null end is active. A lapse/restart ends the same record
and creates a new ID if requested. Failed multi-write restart compensates by
restoring the prior attempt; histories and cravings are never deleted.

Legacy records without currency/minor-price remain **IRR whole rials** and read
`pricePerPackMinor` unchanged. New IRR records also retain that legacy key.
In the Dart model `pricePerPackRials` is only a legacy source alias (a
constructor parameter and a stored key the reader accepts); new logic uses
`pricePerPackMinor`. Missing text/numeric fields default to safe empty/zero
values, missing start to now, invalid end to null. Pack size defaults to 20.

Money is an **integer count of the selected currency's minor units**. The
offline table contains 165 current currency/fund codes with known precision,
verified from [SIX's ISO 4217 List One](https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml)
on 2026-10-12. Examples: USD/EUR 2 digits, JPY/KRW 0, KWD/BHD 3, CLF 4.
**IRR deliberately uses whole rials (0 digits)** to preserve the original Nex
contract and existing records; this differs from ISO's listed minor-unit scale.
There is no currency conversion, exchange-rate lookup or total across currencies.

New amounts/prices are limited to `2^53 − 1` minor units, exact on native and web
runtimes. Input uses integer/BigInt parsing, accepts Latin, Persian and Arabic
digits, grouped thousands, and `.` / `٫` decimals. Excess precision, negative
money, malformed grouping, decimal comma and larger values are rejected rather
than silently rounded/clamped. Stored fractional/NaN/infinite amounts default
to zero. Stored currency precision is preserved, including an unknown valid
three-letter historical code; new selections come from the bundled table.

Kind `craving`, store-generated ID:

```json
{"at":"2026-10-12T13:20:00.000","intensity":2,"triggers":["stress","coffee"],"coping":"water","note":"after tea"}
```

`at`: ISO timestamp; `intensity`: integer 1–3;
`triggers`: distinct known string keys (stress, boredom, coffee, afterMeal,
social, driving, tired, emotion, other); `coping`: water/deepBreath/walk/gum/
waited/distraction or null; `note`: string. Unknown/duplicate triggers and coping
keys are filtered; nonfinite intensity falls back to 1. Invalid timestamp reads
as now. Future timestamps get an explicit future label ("Tomorrow", "in N
days"), never a negative "days ago". Deletion/Undo restores the complete raw
craving body.

Drafts are stored under kind `draft`, IDs `<editor>:<record-id>` or
`<editor>:new`, with `{v: 1, base: <JSON string of original body>, fields: {...}}`.
Field values are strings from the editors plus typed choices described below.
`fields.recordId` is an optional stable target ID for new records: if that record
already exists, a leftover checkpoint is not reopened as a new unsaved record.
A cleanup failure may replace the draft with `{v: 1, discarded: true}`; this
marker has no fields/base and is ignored on read.
Serial, coalesced writes keep the latest snapshot; back/swipe keeps it, explicit
Cancel discards it, successful Save clears it. A baseline fingerprint rejects
stale drafts after a final record changes. These records stay in this module's
store/backups and never count toward progress or balances.

Quit draft fields: `daysAgo`, `perDay`, `price`, `perPack` strings;
`currency` string, `digits` integer and `anchor` ISO timestamp. Craving draft:
`note` string, `intensity` integer, `triggers` string list, `coping` nullable key.

## 3. Decisions

- Days count **local calendar boundaries**, not full 24-hour periods: yesterday
  at 23:00 to today at 07:00 is one calendar day. UTC/offset timestamps are first
  converted to device local time. Future starts clamp to zero.
- Avoided cigarettes = calendar days × baseline/day. Saved minor units =
  floor(avoided × pack price / cigarettes per pack). Zero/negative/corrupt
  baselines cannot produce negative values or divide by zero.
- BigInt intermediates and the displayed `moneySavedMinor` keep very large
  estimates exact, even past int64. The legacy `rialsSaved` numeric alias is
  bounded to the interoperable integer range and is not used by the dashboard.
- Ended attempts stop estimating at their end. Same-day attempts cross zero
  calendar boundaries; they are not described as lasting one full day.
- Baseline-only edits preserve the exact original timestamp. Changed relative
  dates use calendar construction anchored at editor-open time, avoiding DST
  shifts and midnight drift. Drafts retain that anchor on reopen.
- The person never enters or reads an absolute calendar date: the quit start is
  "N days ago", progress is "N days", cravings are "today / yesterday / N days
  ago". Relative wording is the honest UX for a quit streak, so the shared
  Jalali picker has nothing to wrap here; storage stays civil ISO 8601.
- Lists are deterministic: exact-same-instant cravings and attempts tie-break on
  the store's time-ordered record id, so rows never swap between rebuilds.
- One-unit counts read in the English singular ("Smoke-free for 1 day",
  "≈ 1 cigarette not smoked", "Lasted 1 day", "Tomorrow"); Persian needs no
  plural branch and keeps its own natural wording.
- Empty-state and retry buttons grow with the text scale instead of carrying
  Material's fixed 40 px height cap, so a 2× label is never clipped.
- Encouragement is non-medical and compassionate; estimates are labelled.
  Missing craving logs do not prove there were no cravings.
- Writes are guarded and failures preserve the editor; stable save IDs make
  retries idempotent. Module storage remains independent of every other module.

## 4. Guide

**English:** Set your quit date and earlier smoking baseline, including pack
price and currency. The dashboard estimates cigarettes avoided and money kept
from calendar days; these are estimates. Log a craving when helpful, then review
what set it off and what you tried. A lapse or a fresh attempt keeps your earlier
history. You can correct the baseline and undo a deleted log; unfinished forms
keep a local draft. Everything stays offline on this device.

**فارسی:** زمان شروع ترک و مبنای قبلی را، همراه قیمت بسته و ارز آن، وارد
کنید. صفحه بر اساس روزهای تقویمی، تعداد سیگار نکشیده و پول صرفه‌جویی‌شده را
برآورد می‌کند. هر وقت مفید بود هوسی ثبت کنید تا محرک‌ها و کارهایی را که
امتحان کرده‌اید مرور کنید. ثبت لغزش یا شروع تلاش تازه، تاریخچهٔ قبلی را نگه
می‌دارد. مبنا قابل‌اصلاح است، حذف هوس بازگردانی دارد و فرم ناتمام به‌صورت
پیش‌نویس محلی می‌ماند. همه‌چیز روی همین دستگاه و آفلاین است.

## 5. Changelog

- EN: Smoke-free: exact international currency estimates, visible attempt
  history after lapses, explicit restarts, preserved quit dates and local drafts.
- FA: بدون سیگار: برآورد دقیق با ارزهای بین‌المللی، تاریخچهٔ در دسترس پس از
  لغزش، شروع تلاش تازه، حفظ زمان ترک و پیش‌نویس محلی.
- EN: Smoke-free: honest singulars ("1 day", "1 cigarette", "Tomorrow"),
  deterministic same-instant ordering, and text-scale-safe empty-state buttons.
- FA: بدون سیگار: واژه‌های مفرد درست («۱ روز»، «۱ سیگار»، «فردا»)، ترتیب
  قطعی برای ثبت‌های هم‌لحظه و دکمه‌هایی که با متن بزرگ می‌شوند، نه بریده.

## 6. Platform requests

1. Evidence-reviewed localized recovery milestones as platform content. Still
   requested: no clinical recovery timeline or outcome claim is shipped without
   a vetted source, and the module's own encouragement stays calm and
   non-medical regardless.
2. ~~Shared Jalali picker/formatter through the API; relative days are the
   honest working fallback.~~ **Fulfilled by design — nothing to wire.** The
   module has no absolute date a person enters or reads: the quit start is a
   relative "days since quitting" number, progress and history are relative
   day counts, and cravings read "today / yesterday / N days ago". That is the
   deliberate UX for a quit streak, so `NexModuleDateEntry` and
   `nexModuleDateLabel` have no spot to occupy; if an absolute date is ever
   added, it will go through them. Storage stays civil ISO 8601.
3. ~~Export `NexTextField` for Nex's native per-paragraph note editor.~~
   **Fulfilled.** The module's only multiline note — the craving note — uses
   the exported `NexTextField`; the remaining fields are single-line numbers
   kept in explicit left-to-right `TextField`s on purpose (ADR-037). No local
   multiline fallback existed to convert.
4. Optional atomic storage batch for attempt end/restart. Still requested: the
   kit cannot provide a crash-atomic two-record transaction. Current writes are
   guarded, use stable save IDs, and compensate failures by restoring the
   prior attempt; histories and cravings are never deleted.

## 7. Checks

Current pass (this repository, this folder only), run from `apps/client` with
the repository's pinned Flutter **3.35.5** / Dart **3.9.2**:

```text
dart format lib/modules/smoke_free test/modules/smoke_free   # 0 changed
flutter analyze --fatal-infos                                  # clean
flutter test test/module_kit_test.dart -j 2                    # 40 passed
flutter test test/modules/smoke_free -j 2                      # 92 passed
```

92 = 78 inherited (all still green, none weakened) + 14 added: English and
Persian singular day/cigarette wording, the same-day attempt line, Tomorrow
and in-N-days future labels, the 2×-text empty-state button height, and
deterministic same-instant tie-breaks for cravings, the active attempt and
history. Both language maps carry identical keys (91 each) with no empty
value and no bidi control characters (the only isolates in the module are
`money_format`'s long-standing LRI/PDI pair around a currency code inside a
bidi sentence, shared verbatim with the reviewed `lent_borrowed` module);
no file in the module's `lib` folder exceeds 400 lines. Edits are confined
to `lib/modules/smoke_free/` and `test/modules/smoke_free/`.

Originally reviewed in the owner's Windows / PowerShell workspace against Nex `main`
`fdd70f4890b0bab67d30b88d4821273113d4b01d`, with the repository's pinned Flutter **3.35.5** / Dart **3.9.2**.
The installed system Flutter is 3.44.8; a local validation SDK was used instead.

All three modules were temporarily registered in a separate reference checkout
under `.validation/DbsNex`; the original registry is restored after checks.
No core source, ARB, dependencies, registry or planned-catalog edits are delivered.
No Commit, Push, PR, remote write or ZIP was made. `core.longpaths` was supplied
to clone per command rather than changing the owner's global Git configuration.

Commands run from `apps/client` (with the pinned local SDK):

```text
flutter pub get --enforce-lockfile
flutter test --no-pub test/module_kit_test.dart test/modules/habits test/modules/smoke_free test/modules/lent_borrowed --reporter expanded
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter expanded
dart format <module's lib and test folders>
```

`--no-pub` follows successful dependency resolution: Flutter's final Windows
plugin-symlink setup reports missing Developer Mode privileges. Package versions
remain exactly those in the baseline lockfile; only the hosted download endpoint
was changed temporarily to the public Flutter mirror because pub.dev returned
403. Tests run outside the filesystem sandbox after its compiler-temp-file copy
failed with Access denied. Neither workaround changes module code or dependencies.

Final results: **248/248 passed** for the combined module tests and the real
module-kit gate with temporary registration; **full client analyzer clean**.
The full client run reported **1368 passed, 4 failed, 3 skipped**: two Windows
attachment-fixture file-lock cleanup failures, the intentional old planned
Habits entry pending maintainer integration, and the multiline editor/API
discrepancy described above. The Windows failures reproduced with the original
registry. Core: 231 passed/analyzer clean. Data: 253 passed, 2 failed (Windows
symlink privileges), 14 skipped/analyzer clean. Final detailed evidence is in
`review/VALIDATION.md` at the workspace root. Earlier test failures were repaired;
the final log, not the initial README's historical claims, is authoritative.

Tests include Persian RTL and English LTR, light/dark, text scale 2.0 at 320×640,
reduced motion, reopening, isolation, failed writes/retry, draft coalescing,
back waits for the latest durable checkpoint, retry after a failed flush,
and meaningful user journeys. Actual Flutter main-screen captures use Nex's
themes and bundled fonts in Persian dark and English light, under
`review/screenshots`. These are widget renders with test fixtures, not Android-device screenshots.

Maintainer integration: register the three const modules and imports in
`nexModules`; remove the old planned IDs **`habits`, `smoke-free`, `lent`**
(different from the actual IDs `habits`, `smoke_free`, `lent_borrowed`).
Copy the Guide/Changelog paragraphs above into the app's content. Run the gate,
full app checks and device/accessibility review before release.

## Changes since the upgrade pass

- 2.1.12: Quit Habits — several habits (presets and custom) with a live count, future start, money and time kept, saving goal, a reason, marks, a five-week grid and a help sheet (4-7-8 breathing, ten-minute wait, tips). Records of the Smoke-free module read as cigarettes and are written back unchanged; new fields (`habit`, `name`, `why`, `goalMinor`, `minutesPerUnit`) appear only when used.
