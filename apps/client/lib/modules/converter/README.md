# Converter

Dates between the three calendars Iranians live by, units, and the sizes on a
clothing label — all of it on the phone, none of it over the network.

Module id `converter`, hue `NexHue.teal`, icon `Icons.swap_horiz_rounded`.
It ships as **Soon**: it is registered in `nexModules`, and it is not in
`nexAvailableModuleIds`.

## What it does

**Dates.** Type a date in any of the three calendars and read it in the other
two at once, with the weekday. The calendar chips switch which one the field is
written in without losing the day. Two sums live behind their own buttons:
the days between two dates, and a date plus or minus a number of days. The
date picker opens in the calendar you are on.

- Solar Hijri and Gregorian come from the app (`nexPersianDate`,
  `nexGregorianDate`), so the converter can never disagree with the rest of Nex
  about a Jalali date.
- Lunar Hijri is computed in the module (see *Decisions*). Every lunar line is
  followed by one line of caveat: a calculated lunar date can differ from the
  announced date in Iran by a day.

**Units.** Length, mass, volume, temperature, area, speed. Pick a category, a
unit on each side, type a number, read the answer. Swap flips the pair (and the
number with it). Every answer carries the factor it came from, so it can be
checked by hand. Nothing converts between categories, and nothing converts
money.

- Standard units are exact: the 1959 international yard, the international
  pound, the US and imperial gallons, the SI prefixes.
- Seven Iranian units are offered (zar, shah gaz, mesghal, sir, man-e Tabriz,
  kharvar) and marked approximate with their assumed value, because they were
  never one number across Iran.

**Sizes.** Eight static charts: women's tops and trousers, men's tops and
trousers, women's, men's and children's shoes, and rings. Choose a chart, the
system you know, and the size; read every other system and the body
measurement the size stands for. Iran is shown as its own system: the European
number for clothes (+1 on shoes, as shops quote it), the metric ISO number for
rings.

Numbers are typed in Latin, Persian or Arabic digits, with `.` or `٫` or `,` as
the separator, and are answered in the digits of the language the app is in.

## Records

Two kinds of records live under `converter` in the module store, and one draft:

| kind | id | what it holds |
| --- | --- | --- |
| `recent` | random | `tab`, `label`, `payload`, `at`. The last 20 conversions, newest first, kept once per payload signature. |
| `favorite` | random | the same, for starred conversions. |
| `draft` | `state` | the tab, calendar, typed date, category, unit pair, value, chart, system and size row. One per person. |

`payload` is what the conversion *was*, not what it was called: a units record
keeps `{cat, from, to, value}`, a date record keeps the calendar and the three
parts, a size record keeps `{chart, sys, row}`. The label is rebuilt in the
current language from that payload, so a conversion made in English reads in
Persian after a language change. A record that has lost a field it needs is
skipped when the list is read, never thrown over: one malformed row cannot take
the history with it.

Deleting a record shows a banner with Undo, which writes the same record back
with its original id and time. A delete that arrives while a conversion is
still waiting to be kept cancels that wait, so the row does not come back by
itself.

## Decisions

**The lunar calendar is calculated, not observed.** The module uses the
tabular Islamic calendar: epoch 19 July 622 in the proleptic Gregorian calendar
(JD 1948440), months alternating 30 and 29 days, and a leap year when
`(11 × year + 14) mod 30 < 11`, which adds a day to Dhu al-Hijjah. It is pure
arithmetic: the same input gives the same answer in 2030 as in 2026, and it
needs no table and no network. Measured against 32 announced Iranian month
starts from 1440 to 1447 AH, 20 land on the same day, 8 a day earlier and 4 a
day later, never more than a day. That is why the caveat line is not a footnote
but part of the screen.

**A range, not the whole of time.** Civil years 1900–2100
(`converterFirstCivilYear`/`converterLastCivilYear`). Outside it the field says
so instead of guessing.

**Standard factors are exact, traditional ones are named assumptions.** The
length and mass factors come from the 1959 yard and pound and the SI; the
volumes from the definitions of the two gallons; temperature goes through
Celsius with absolute zero as a floor (below it the answer says so rather than
showing a negative kelvin). The Iranian units are the ones a shop or a recipe
still uses, at the value the README names, marked approximate with the
assumption in the note: mesghal 4.608 g, sir 75 g, man-e Tabriz 3 kg, kharvar
300 kg, zar 104 cm, shah gaz 112 cm.

**Size charts are printed facts, not formulas.** Clothes follow EN 13402 body
measurements at the European sizes sold in Iran (women 34–52, men 44–58), with
UK and US numbers derived from the same body. Iran is the European number.
Shoes follow ISO 19407 adult and children's tables by foot length in
millimetres, with Iran quoted as EU + 1. Rings are generated from BS 6820
(A = 37.5 mm, +1.25 mm per letter and half letter), with the US number from
`(c − 36.54) / 2.55` rounded to the quarter size, the Iranian shop number from
`round(c − 5)`, and the ISO circumference and diameter beside them. The screen
says charts differ between brands, because they do.

**Nothing leaves the phone.** No network call, no currency rate, no clock
service, no analytics. The only clock read is `DateTime.now()` for "today" and
the record times.

**One screen, three tabs, one hero.** The answer is always the hero at the top;
the fields below it only choose what to answer. A conversion is kept as a
recent once typing pauses for 900 ms, not per keystroke — and never on a tab
switch, because a tab is not a conversion.

## Research

Checked 13 November 2026.

Lunar and civil dates:
- Institute of Geophysics, University of Tehran, calendar centre — the announced
  lunar month starts used to measure the arithmetic calendar:
  <https://calendar.ut.ac.ir>
- Time and Date, Islamic calendar (the tabular rules and the 622 epoch):
  <https://www.timeanddate.com/calendar/islamic-calendar.html>
- The app's own Jalali conversion (`nexPersianDate`, `nexGregorianDate`) as the
  authority for solar dates, not a second implementation.

Units:
- NIST SP 811, *Guide for the Use of the International System of Units*,
  Appendix B (all the exact conversion factors): <https://www.nist.gov/pubs/sp/811/final>
- BIPM, *SI Brochure*, 9th edition: <https://www.bipm.org/en/publications/si-brochure>
- UK *Weights and Measures Act 1985*, Schedule 1 (the imperial gallon, the
  pound): <https://www.legislation.gov.uk/ukpga/1985/72/schedule/1>
- Encyclopaedia Iranica, *Weights and Measures*: <https://iranicaonline.org/articles/weights-and-measures>
- Dehkhoda dictionary, entries for mesghal, sir, man and kharvar (the values
  and their variation by city).

Sizes:
- EN 13402-3:2017, *Size designation of clothes — Body measurements and
  intervals*.
- ISO 19407:2023, *Footwear sizing — Mondopoint system* (adult and children's
  tables by foot length).
- ISO 8653:2016, *Jewellery — Ring-sizes* (circumference and diameter).
- BS 6820:1987, *Ring sizes* (the letter scale at 1.25 mm a step).
- Iranian shop practice for the +1 shoe offset and the ring number, which is
  the circumference in millimetres less five.

## Guide

### English

1. Open **Converter**. It opens on **Dates** with today's date in the calendar
   the app is set to.
2. Type a date — `1405/08/22`, `2026-11-13`, `13.11.2026`: any separator, in
   Persian, Arabic or Latin digits. The other two calendars appear above with
   the weekday. The chips switch the field to another calendar.
3. **Days between** opens two dates and gives the count; **A date, plus or
   minus days** shifts a date and shows the result in all three calendars. A
   minus sign goes before the number of days.
4. **Units**: pick a category, a unit on each side, type a number. **Swap**
   turns the pair around. Units marked *approximate* show the value they assume.
5. **Sizes**: pick a chart, the system you know, and the size. Every other
   system and the body measurement follow.
6. Everything you convert is kept under **Recent**; the star at the top keeps
   the current conversion under **Starred**. Tapping a kept conversion puts it
   back; the row menu stars it or removes it, and **Undo** brings it back. The
   copy button copies the whole conversion, answer included.

### فارسی

۱. **تبدیل‌گر** را باز کنید. روی **تاریخ** و با تاریخ امروز در تقویمی که برنامه
   روی آن است باز می‌شود.
۲. تاریخ را بنویسید — `۱۴۰۵/۰۸/۲۲` یا `2026-11-13` — با هر جداکننده‌ای و با
   رقم فارسی، عربی یا لاتین. دو تقویم دیگر با روز هفته بالای صفحه می‌آیند و
   نشانه‌ها تقویم نوشتن را عوض می‌کنند.
۳. **روزهای میان دو تاریخ** فاصله را می‌دهد؛ **یک تاریخ، به‌اضافه یا منهای
   روز** تاریخ را جابه‌جا می‌کند و نتیجه را در هر سه تقویم نشان می‌دهد. علامت
   منفی پیش از شمار روزها می‌آید.
۴. **واحدها**: دسته، واحد هر دو سو و یک عدد. **جابه‌جایی** دو سو را عوض
   می‌کند. واحدهای *تقریبی* مقداری را که فرض شده نشان می‌دهند.
۵. **اندازه‌ها**: جدول، دستگاهی که می‌شناسید و اندازه را انتخاب کنید؛ بقیهٔ
   دستگاه‌ها و اندازهٔ بدن می‌آید.
۶. هر چه تبدیل کنید در **اخیر** می‌ماند و ستارهٔ بالای صفحه تبدیل جاری را در
   **ستاره‌دار** نگه می‌دارد. با زدن روی هر ردیف، تبدیل به خانه‌ها برمی‌گردد؛
   منوی ردیف آن را ستاره می‌کند یا برمی‌دارد، و **واگرد** برمی‌گرداندش. دکمهٔ
   رونوشت کل تبدیل را با پاسخ رونوشت می‌کند.

## Changelog

### English

- **New module.** Dates across the solar, Gregorian and lunar calendars, with
  days between and date arithmetic; units in six categories, Iranian units
  included; eight size charts for clothes, shoes and rings.
- All three tabs work offline; records and the draft are kept in the module
  store, so the screen comes back as it was left.
- Lunar dates are calculated and say so; Iranian units are approximate and show
  their assumed value.

### فارسی

- **ماژول تازه.** تاریخ در تقویم‌های شمسی، میلادی و قمری، با فاصلهٔ دو تاریخ و
  جمع و تفریق روز؛ واحدها در شش دسته، با واحدهای ایرانی؛ هشت جدول اندازه برای
  پوشاک، کفش و انگشتر.
- هر سه زبانه بی‌اینترنت کار می‌کنند؛ تبدیل‌ها و پیش‌نویس در انبار ماژول می‌مانند،
  پس صفحه همان‌گونه که رها شده برمی‌گردد.
- تاریخ قمری محاسبه می‌شود و همین را می‌گوید؛ واحدهای ایرانی تقریبی‌اند و مقدار
  فرض‌شده را نشان می‌دهند.

## Platform requests

1. **A hue for the hero.** `NexModuleHero` reads `_moduleHues` in
   `lib/modules/module_kit/*`; it has no `'converter'` key, so the hero falls
   back to the theme's primary colour instead of `NexHue.teal`. Add
   `'converter': 176` beside the other entries.
2. **Two counts in `test/module_preview_test.dart`.** The suite counts the
   stored add-ons as twelve and asserts `hasLength(12)` in "all modules default
   off, including the twelve add-ons" and "three add-ons are back, the other
   nine are Soon; their code stays". Registering `ConverterModule()` makes it
   thirteen, so those two tests now fail on the count and nothing else (3,622
   tests, 2 failures, both this assertion). The module author may not touch a
   file outside `lib/modules/converter/` and `test/modules/converter/`; the fix
   is `hasLength(13)`, plus the wording of the two titles.
3. **Nothing else.** The module needs no new service, no table, no permission
   and no network. It reads and writes only its own records through
   `NexModuleStore`.

## Checks

Run in `apps/client`, Flutter 3.47.9:

```
flutter pub get
dart format lib/modules/converter test/modules/converter
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart test/modules/converter
flutter test
```

`flutter analyze --fatal-infos` reports no issues. `test/modules/converter`
holds 70 tests: every calculation, parser and chart generator, the malformed
records, and the screen in both languages, light and dark, at twice the text
size and on a 360 dp-wide phone. The module gate
(`test/module_kit_test.dart`) passes, with the converter tests: 116 tests, all
passing.

Full suite: 3,622 tests in 10m43s, **2 failures**, both
`test/module_preview_test.dart` counting the stored add-ons as twelve when the
registry now holds thirteen (see *Platform requests*). No other test fails.

The tests that touch records and the screen need a real `libsqlite3`; on a
machine whose only copy is `libsqlite3.so.0`, point `LD_LIBRARY_PATH` at a
directory holding a `libsqlite3.so` symlink to it.
