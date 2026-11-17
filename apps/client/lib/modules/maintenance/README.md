# Maintenance — `maintenance`

## Audit (upgrade pass)

Maintenance is a **Soon** module; people do not have it yet, so fields may be
added but nothing written may change meaning. The brief's second half — the
car as a first-class case — was missing entirely.

What the module did before, screen by screen:

- **Home** — assets grouped as due now, coming up (30 days), needs
  information, scheduled, no schedule and archived; hero counts; add asset.
- **Asset editor** — name, type (car, motorcycle, AC, boiler, filter,
  appliance, other), model, purchase date, what it counts (nothing, km/mi,
  hours), notes, with explicit unit conversion.
- **One asset** — the asset panel, an opt-in device reminder for the next
  service, current-meter panel with readings, interval rules, repeat last
  service, service history, cost totals, share/copy history, archive/delete
  with Undo.
- **Service editor** — task, date, optional cost and currency, meter reading
  with correction question, provider, notes; delete with Undo.
- **Rule editor** — every N days **or** N months, and/or N km/mi or hours.
- **Reading editor** — a quick current odometer/hours update that never
  becomes a service.

What was below the brief and is now fixed:

| Brief ask | Before | Now |
| --- | --- | --- |
| Things with service history | Done | Unchanged |
| Rules: every N km **or** M months, whichever first | Both triggers existed | Unchanged, and the panel states that either can make it due |
| **My car** as a first-class case | Only a car type icon | A **Car details** panel on every car: third-party insurance and technical inspection |
| Insurance and inspection expiry with a reminder some days before (default 14, editable) | Missing | Each date is typed, shown with its countdown, and each has a reminder with 7/14/30-day choices or any number of days, 14 by default; the lead time is stored on the car |
| A quick "today it reads 84,200" | Existing current-meter panel | Unchanged, still one tap |
| Fuel log: date, litres, price paid, rate | Missing | `fuel` records and a Fuel panel: add/edit/delete fill-ups with Undo |
| Monthly quota: litres per rate, this month's cost | Missing | Fuel panel shows this month's litres and cost and each rate's quota used/left/over; month = Jalali month for a solar reader |
| Rates and quotas are the person's settings; examples marked | Missing | A rates sheet with name + monthly quota per rate, example rows explicitly marked; no fetched price, no "official" claim |
| A service record to hand over | History text existed | The shared text now also carries insurance, inspection and this month's fuel/quota |
| No mechanical or legal advice | True | Still true: no diagnosis, no legal wording, no rate claims |

Not done, and why:

- **The shared `duesBetween` and `summarize`** (docs/18, rules 1 and 4). The
  module's own pending-list entries live in
  `test/module_shared_rules_test.dart`, which this task may not edit; adding
  the functions would break the shared-rules test. They are requested under
  Platform requests. The module already reads old records defensively and
  keeps fields it does not know.
- **Insurance and inspection on the due radar** is the brief's Later item;
  the storage shape is described at the end for that future reader.
- **Photos, receipts and live sensors** remain outside the module
  (Platform requests).

## What it does

An offline service log for the things a person looks after, with the car as
the fullest case. Every asset has service history, its own interval rules
(date and/or usage, whichever comes first) and a plainly stated next due.
A car adds a **Car details** panel — third-party insurance and technical
inspection, each with a typed date and an optional reminder a chosen number
of days before — and a **Fuel** panel: fill-ups by date, litres, price paid
in tomans (stored as rials) and the rate they were bought at, with monthly
litres and cost against the person's own quotas. Nothing is fetched,
diagnosed or presented as official.

Screens:

- **Home** — grouped assets, hero counts, add asset.
- **Asset page** — asset facts; for a car, Car details and Fuel; opt-in
  device reminder for the next service; current meter; interval rules;
  repeat last service; full history; per-currency cost totals.
- **Asset / service / rule / reading editors** — existing, unchanged.
- **Fuel fill-up sheet** — date, litres, price paid (tomans), rate choice,
  notes, save, delete with Undo.
- **Fuel rates sheet** — one row per rate: name and monthly quota, add and
  remove, example values marked until checked.

## Records

All records are in the module's own `NexModuleStore`. Kinds:

| Kind | Body |
| --- | --- |
| `asset` | schema 2; nickname, type, optional model/purchasedAt/notes, meterKind, distanceUnit, archived; **for a car** optional `insuranceExpiresAt`, `inspectionExpiresAt`, and `insuranceLeadDays` / `inspectionLeadDays` (integer days, default 14) |
| `event` | schema 2; assetId, task, date; optional cost + currency metadata, meter + scale + kind + unit, provider, notes |
| `rule` | schema 2; assetId, task; days or months; meters or hours; meter unit and scale |
| `reading` | schema 1; assetId, value, scale, meterKind, unit, at, corrected |
| `fuel` | schema 1; assetId, date (calendar day), `litres` (integer thousandths, `litres_scale` 1000), `priceRial` (whole rials), `rate` (the person's rate name), optional notes |
| `fuel_rate` | schema 1; assetId, name, `quota` (litres, thousandths), `quota_scale` 1000, optional `example` marker |
| `draft` | raw editor fields and their record; never a service or total |
| `operation` | the module's recovery journal for a write group |

Money is stored once, as whole **rials**, in a `…Rial` field. Fuel prices are
entered in tomans and converted exactly at save (10 rials = 1 toman); more
than one decimal of a toman is refused, never rounded. Existing asset, event,
rule, reading, draft and operation bodies are unchanged; a car's new fields
are only written for `type: car`, and an old car without them simply shows
"Not set".

## Decisions

- **The car is an asset, not a second kind of record.** Insurance, inspection
  and fuel hang off the existing asset by `assetId`, so a car keeps one
  history, one set of rules and one delete/Undo path. `asset` gains only
  optional fields.
- **Dates are typed, never fetched.** The module asks for insurance and
  inspection dates and remembers them; it does not know a legal date, a
  price or a quota from the outside world.
- **Reminder lead time lives on the car.** Fourteen days by default,
  editable per item, stored as `insuranceLeadDays` / `inspectionLeadDays`, so
  reopening the sheet shows the person's choice instead of resetting it.
- **A reminder never fires in the past.** The sheet refuses a moment already
  gone and says so; scheduling goes through the store's `setReminder`, so
  permission checks and auto-cancel apply.
- **Fuel is a log, not an estimate.** Only fill-ups the person enters count.
  A fill-up with a malformed date, zero/negative litres or a negative price
  is not a record and never enters a total.
- **The month is the person's month.** For a solar reader the quota month is
  the Jalali month; otherwise the civil month. No rolling 30 days and no
  guessed month boundary.
- **Rates are settings with examples, not facts.** The rate sheet can fill
  two example rows (quota and free), each labelled "Example — check yours".
  Names and quotas are free text/numbers the person owns; nothing calls them
  official.
- **Tomans on screen, rials in storage.** Prices are entered in tomans with
  at most one decimal and stored as exact rials; totals are exact integers.
- **Existing service logic is untouched**: independent time and usage
  triggers, no invented baselines, calendar-day arithmetic, unknown states
  shown as needing information, and archive/delete with guarded Undo.
- **Deleting a car deletes its fuel and rates too**, in the same journaled
  group, so Undo brings the whole car back.

## Research

The first pass settled the service side. For the car, checked 2026-11-17:

- Iranian drivers think in **two insurance dates** (third-party insurance and
  technical inspection) and in **fuel card quotas** that are monthly and
  multi-rate. Both are dates/numbers people read off a document, not values
  an app can look up; there is no public, stable API to fetch, and a wrong
  fetched date would be worse than an empty field.
- Fuel is remembered as "how much did I put in, at which rate, and what did
  it cost", because the quota is consumed per rate and the month's cost is
  the number people check.
- A single "next service" reminder is not enough around a car: inspection
  and insurance have their own deadlines, and 14 days is the common
  comfortable warning window, so it is the default and stays editable.

No service, SDK or dependency was added; all arithmetic is local.

## Shared across modules

- **Dates falling due (`duesBetween`)** — not added; the module stays on the
  central pending list because leaving it needs an edit outside this task.
  Requested. The storage is ready for it (see "For the due radar").
- **Money** — fuel is whole rials in `priceRial`; no fractional rial field
  exists. Costs keep their existing explicit currency metadata.
- **People** — none; a provider is free text and not a person record.
- **A line per record (`summarize`)** — not added, same pending-list reason;
  requested.
- **Unknown fields** — kept: edits merge onto the raw record and fuel writes
  spread the old body.
- **Saving, leaving a form, Undo** — drafts and guarded Undo as before; fuel
  entries use the same draft frame and Undo banner.
- **Reminders** — through the store's reminder call, wording names the car,
  the item and the date. Lead time is in **days**, default 14, editable;
  docs/18's shared set is day-scale, so this fits.
- **Sharing and hiding** — text through `nexModuleShareText`; no money
  totals or health data to hide in the new panels beyond the person's own
  entered costs.
- **Look and movement** — `NexPanel`, `nexShowSheet`, `NexPageRoute`,
  `NexSpacing`/`NexRadius`, ADR-037 on typed fields, `heroTag: null`;
  checked in Persian/English, light/dark and scale 2.0.

## Guide

**English.** Add the car as an asset and choose that it counts kilometres.
On its page, set the third-party insurance and technical inspection dates;
each shows how many days are left and can remind you 14 days before (change
it to 7, 30 or any number). Log each fill-up with its date, litres, what you
paid in tomans and which rate it was bought at; under Fuel you see this
month's litres and cost and how much of each rate's quota is left. Set your
rates and monthly quotas once in **Rates and quotas** — the examples are
marked until you check them. Services and intervals work as before, and the
menu's share/copy history now also carries the two dates and the month's
fuel.

**فارسی.** خودرو را به‌عنوان یک دستگاه اضافه کنید و بگویید با کیلومتر
شمرده می‌شود. در صفحهٔ آن، تاریخ بیمهٔ شخص ثالث و معاینهٔ فنی را بگذارید؛
هر کدام روزهای مانده را نشان می‌دهد و می‌تواند ۱۴ روز قبل یادآوری کند
(۷، ۳۰ یا هر تعداد روز دیگر). هر سوخت‌گیری را با تاریخ، لیتر، مبلغ
پرداختی به تومان و نرخش ثبت کنید؛ زیر «سوخت» لیتر و هزینهٔ این ماه و
ماندهٔ سهمیهٔ هر نرخ را می‌بینید. نرخ‌ها و سهمیه‌های ماهانه را یک بار در
«نرخ‌ها و سهمیه‌ها» بگذارید — مقدارهای نمونه تا وقتی خودتان بررسی نکنید
همان‌طور علامت‌خورده می‌مانند. سرویس‌ها و بازه‌ها مثل قبل کار می‌کنند و
«اشتراک تاریخچه» حالا این دو تاریخ و سوخت این ماه را هم دارد.

## Changelog

EN: The car is now a full case in Maintenance: third-party insurance and
technical inspection dates with a countdown and a 14-day (editable) reminder,
a fuel log with litres, price and rate, and monthly litres/cost against your
own quotas — with example rates marked until you check them. The service
history text you hand over now includes both dates and the month's fuel.

FA: خودرو حالا در «نگهداری» یک بخش کامل است: تاریخ بیمهٔ شخص ثالث و
معاینهٔ فنی با شمارش روزها و یادآوری ۱۴ روزهٔ قابل تغییر، دفتر سوخت با
لیتر، مبلغ و نرخ، و لیتر/هزینهٔ ماه در برابر سهمیه‌های خودتان — با
نرخ‌های نمونه که تا بررسی نکنید علامت‌خورده می‌مانند. متن تاریخچهٔ سرویس
حالا این دو تاریخ و سوخت ماه را هم دارد.

## Platform requests

1. **Store transactions with cross-process conflict detection** — still
   absent; writes stay serialized with the module journal and guarded Undo.
2. **Receipt/photo attachment APIs** — for insurance papers, inspection
   slips and fuel receipts; entered dates and notes stand in.
3. **`duesBetween` and `summarize` in the kit**, plus the maintainers
   updating the central pending lists; this module may not edit
   `test/module_shared_rules_test.dart`.
4. **Image sharing** for the service record (text is shared today).
5. **A due-radar surface** for insurance and inspection, once the platform
   has one; the module stores what it needs (below).

## For the due radar (Later — not built)

Insurance and inspection are stored on the car asset as `insuranceExpiresAt`
and `inspectionExpiresAt` ISO calendar days, with `assetId` = the asset's
id and the record kind `asset`. A future `duesBetween` can read each car's
two dates and return one `ModuleDue` per date: `recordKind: 'asset'`,
`recordId` the car, `at` at local midnight, `title` the car's nickname plus
the item, `kind` `insurance` / `inspection`, `amountRial: null`, `done`
false, `private: false`. The lead times are `insuranceLeadDays` /
`inspectionLeadDays`.

## Device checklist

1. Open a car written before this upgrade: it opens as before and shows
   "Not set" for both dates.
2. Set an insurance date and an inspection date; reopen and confirm the
   dates and countdowns remain.
3. Set reminders: 14 days by default, then 7 and 30, allowing notifications;
   check the alert names the car and item.
4. Try a date whose reminder moment has passed: it is refused with words.
5. Add a fill-up with litres, tomans and a rate; confirm the price is stored
   in rials by editing it and seeing the same tomans.
6. Set two rates with quotas; log fill-ups at each; confirm the month's
   litres, cost and quota left/over match.
7. Change the phone calendar between Jalali and Gregorian and confirm the
   fuel month and all dates follow the person's calendar.
8. Star nothing, invent nothing: open Rates and quotas with no rows, use the
   example values, and check they are marked until edited.
9. Share the service history: it includes insurance, inspection and this
   month's fuel.
10. Archive and delete a car, then Undo: fuel and rates come back with it.

## Open questions

- Should insurance and inspection reminder defaults differ (for example 30
  days for inspection)? The brief says 14 for both.
- Should a rate rename rewrite old fuel rows, or is the rate name a stable
  historical label (the current choice)?
- Should quotas reset visibly on the Jalali month boundary with a "new
  month" note, or is the silent recalculation enough?
- Is a single price per fill-up (total paid) enough, or do people want
  price-per-litre as well?
- Should the car panel let someone pick "this is my car" on the home screen,
  or is any car asset equally first-class?
- When the due radar arrives, should insurance/inspection appear by default
  or only after opting in?

## Checks

Upgraded against `main` at `e3edff3f`. Run from `apps/client`:

```text
dart format lib/modules/maintenance test/modules/maintenance
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart test/modules/maintenance
flutter test
```

Results: analyzer clean; the kit/shared/module gate **216 passed** (module
tests **118**: 101 inherited, all still green, plus 17 for the car — model
round trips, malformed refusals, solar/civil month keys, quota maths, exact
tomans↔rials, the car panel, lead-time saving, fill-up flow, example rates
and the history text); no file over 400 lines. Edits confined to `lib/modules/maintenance` and
`test/modules/maintenance`; `module_rollout.dart` untouched, so the module
stays **Soon**.

Screens in `review/`: home and the car page with details/fuel in Persian
dark and English light, plus the fill-up sheet. Widget renders with
synthetic data, not device captures: notification permission, the real
keyboard, TalkBack/VoiceOver and release builds still need the owner's
phone.
