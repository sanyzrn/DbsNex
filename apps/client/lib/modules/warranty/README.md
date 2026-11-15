# Warranties (`warranty`)

## What it does

One place for what a person bought and who stands behind it. Each purchase
keeps the product, the shop, the **warranty company** and its support line,
the card and serial, the coverage period and the person's own notes; its cover
is decided on view — covered, ending within 30 days, ended, or with no readable
end. The screen opens with what runs out in the next 30 days, so nothing
expires unnoticed. Each purchase has its own page with everything a service
desk asks for, a dated log of claims and services, an optional device
reminder offered while the end date is being saved, and a service file to copy
or share. It records only what the person typed: it does not verify a
warranty, call a shop, or promise what will be accepted.

**Screens**

- **Warranties (home).** One hero with how many purchases are covered; then —
  in this order — *Ending in the next 30 days* (soonest first, with a count),
  *Covered*, *Expired*, *Date unavailable*, and archived purchases behind one
  toggle. Search by product, brand, shop or company; an optional sort by
  soonest end. Each row shows the product, the brand (or the company when
  there is no brand), the end date on the person's calendar and how many days
  are left or since it ended. Empty state carries its own add button; the FAB
  is the one primary action once there is something to list.
- **Add / edit purchase (sheet).** Asks first for the product, the purchase
  date, the end date (or a duration with the computed end shown as it is
  typed), the kind of cover and — when the module may schedule one — a
  reminder. Everything else is behind *Shop, card, price and note*: category,
  brand, model, serial/IMEI, shop, warranty company, support phone, card
  number, registry, invoice reference, amount in rials or tomans, and a note.
  Common terms (6/12/18/24/36 months) fill the duration. What is typed is kept
  as a draft; leaving asks first.
- **A purchase (page).** A status card (days left or since it ended, and the
  end date), then *Purchase and shop* and *Warranty and support* with one icon
  per field, the support number one tap from the clipboard, the reminder
  control, and the claim/service log. The menu has edit, archive, copy/share
  the service file and delete; delete and archive offer Undo.
- **Claim or service note (sheet).** The person's own words, dated on save;
  the note can be deleted with Undo. Nothing is presumed about the outcome.

## Records

All kinds are module-local, ride in core backups and go with the module's data
when it is removed.

- **`warranty` v2** — `v`, `product`, `category`, `brand`, `model`, `serial`,
  `merchant`, `receiptRef`, `coverageType`, `note`, `purchasedAt`,
  `coverageEnd` (ISO 8601 civil dates), `archived`, optional `durationMonths`
  and `amountRials` (integers); **new in v2**: `coverKind` (`company`,
  `seller`, `afterSales`), `company`, `supportPhone`, `cardNumber`,
  `registryOwner` (`mine`, `other`). Every new field is optional and written
  only when typed. v1 records (2.1.x) have none of them and read as empty —
  no migration, no rewrite on read, no invented value. Unknown `coverKind` or
  `registryOwner` values read as *not recorded*. An edit merges only the fields
  the person changed into a fresh raw record, so fields this version does not
  know survive.
- **`claim` v1** — `warrantyId`, `kind` (`claim`, `service`), `note`, `at`
  (UTC instant, shown as the local day it happened).
- **`draft` v1** — the raw text of the editor or claim sheet, its base
  fingerprint, the stable record id and the choices that are not text
  (tomans/rials, cover kind, registry, reminder choice). Claim drafts bind
  parent and kind; purchase deletion and Undo include them.
- **`operation` v1** — the durable before-images that make grouped
  delete/Undo recoverable after a crash. Recovery rolls an unfinished group
  back before any new write.
- **`__reminder`** (the kit's) — the optional OS alert, keyed
  `warranty:<id>`, so the alert set in the editor and the one cleared from the
  purchase page are the same alarm.

## Decisions

**What the audit found, and what changed**

1. **The 30-day list was buried** under every comfortably-covered purchase.
   It is now the first section, headed *Ending in the next 30 days* with a
   count, soonest first; covered and expired follow, and expired is ordered
   most-recently-ended first.
2. **There was no company, support line or card number** — the things a
   service desk actually asks for — and no way to say whether the cover is a
   company warranty, the shop's guarantee or after-sales service. Added as v2
   fields and a three-way choice with one line explaining each.
3. **The reminder lived only in the detail sheet.** It is now offered in the
   editor beside the end date, on by default for a new purchase, with 30/7/1
   days before and the exact moment it will ring. A saved purchase starts the
   switch off and says so, because the module cannot read back an existing
   reminder and must not claim to have removed one.
4. **The purchase was a sheet with a transparent `Scaffold` and a
   `ScaffoldMessenger` inside it**, no app bar, no back gesture, and a
   drag handle for a page of content. It is a page (`NexPageRoute`, `NexAppBar`,
   one edit action plus a menu).
5. **Every field row used the receipt icon** (merchant, serial, type and note
   alike). Each row now has its own icon, a left-to-right value where digits
   must not reorder (serial, card, phone, invoice), and a copy action for the
   support number.
6. **The archive menu action said "Archived"** (a state) and the archived
   toggle had no count. They now read *Archive* and *Archived (N)*.
7. **The claim buttons were `OutlinedButton`s**, outside the app's button
   family; they are tonal `FilledButton`s now.
8. **The "Today" chip sat inside the date field's suffix** and cut the label
   to "Purchase …" at 2× text; it now sits under the field with its own 48dp
   target. Two-up field rows stack when the width or the text scale says so,
   instead of truncating "Duration (months)" and "or end date".
9. **Mixed left/right padding** (`EdgeInsets.fromLTRB`) in the header and
   list, and a hard-coded `Colors.transparent`, are gone.
10. **The Persian copy read like a translation** in places ("هیچ حدس کشوری‌ای
    به‌کار نمی‌رود", "با رفتن خرید، آن هم می‌رود"). Rewritten naturally, and
    the page title is «گارانتی‌ها» — what a Persian speaker calls it — while
    the about text explains ضمانت‌نامه.
11. **The service file did not carry the company, phone, card, registry,
    duration or the state of the cover.** It does now, in the order a desk
    reads it, and ends with a line saying where it came from and what Nex does
    not confirm.

**Kept from earlier decisions** (still true, still tested)

Coverage month arithmetic is "same day in the destination month, clamped to
its last day" (Jan 31 + 1 month is Feb 28/29), counted from the purchase
anchor; the end day is inclusive; missing or unreadable coverage is *date
unavailable*, never expired and never today's date; durations are 1–2400
months and cannot end past 2100; input is civil `yyyy/MM/dd` while every date
a person reads goes through the shared Jalali/Gregorian label. Amounts are
integer rials; tomans allow one decimal and convert exactly. Impossible dates
and both a duration and an end date at once are refused, and choosing a common
term clears a written end date rather than leaving both.

**The Iran fields.** Only what helps at the moment something breaks: which
company to call and on what number, the card number and serial a desk asks
for, who the device is registered to (a phone service centre asks for that
person's national ID), and which of the three promises this is. Nothing else —
no shop-rating, no repair history outside the person's notes, no automatic
"warranty valid" badge.

**Reminders.** A new purchase whose end is far enough ahead offers one on by
default — "nothing expires unnoticed" is the reason the module exists — at
30 days before at 09:00, with 7 and 1 days offered. The offer only appears
when the platform will let this module schedule one (`remindersEnabled`);
otherwise the save would fail on every purchase, so it waits rather than
promising something it cannot keep. A failed schedule after the purchase is
saved says so and never hides that the purchase itself was saved; the reminder
is removed by the platform when the purchase is archived, deleted or the
module is removed. The module cannot read a reminder back, so the editor never
shows one as "on" for a saved purchase.

**Honesty.** The module verifies nothing and says so on the card, in the
editor, on the purchase page and at the end of the service file. The cover is
whatever the person typed; a purchase with no serial and no invoice says so
instead of implying a document exists.

## Research

Checked on **2026-11-15**. Everything the module needs at runtime is constant
text; nothing is fetched.

**How warranties work in Iran**

- Phones sold in Iran commonly carry an **18-month** warranty: همراه طلایی,
  «گارانتی» — eighteen months from the sale, warranty card with a hologram;
  digi2040 — «مدت اعتبار گارانتی دستگاه شما ۱۸ ماه می‌باشد»; همراه اول for
  modems — most 18 months, some 12.
  <https://hamrahtalaei.com/guarantee>,
  <https://digi2040.ir/شرایط-گارانتی>, <https://mci.ir/modem-guaranty>
- **A company warranty is separate from the shop.** The buyer deals with a
  warranty company (شرکت گارانتی) that issues the card (رقم گارانتی) and runs
  the service centres; the shop only sells. The card carries the model,
  serial/IMEI, start date and duration, and a card without the seller's stamp,
  purchase date or serial is stated to be invalid.
  <https://hamrahtalaei.com/guarantee>, <https://lg-group.ir/warranty-rules>
- **What the desk asks for on a claim**: the warranty card, the original box,
  an official invoice — and, for a phone, the **national ID card of the person
  the device is registered to (رجیستری)**. Some firms also require the phone
  to be registered in the buyer's name before service.
  <https://hamrahtalaei.com/guarantee>
- **Typical exclusions**: impact, liquid or dust ingress, unauthorised repair
  or opening, non-original parts and chargers, electrical surges, tampered
  serial/IMEI, and consumables/accessories. Software work and data loss are
  not covered.
  <https://digi2040.ir/شرایط-گارانتی>,
  <https://lg-group.ir/warranty-rules>, <https://www.homatelecom.com/terms-of-service>
- **When the clock starts**: some makers say the card's own date governs and
  the invoice date does not; others start at activation, at most six months
  after the import declaration for phones and tablets.
  <https://www.homatelecom.com/terms-of-service>,
  <https://digi2040.ir/شرایط-گارانتی> — *this is why the module stores both the
  purchase date and the end date as separate typed facts and never derives one
  from the other when the person wrote both.*
- **گارانتی / ضمانت‌نامه / خدمات پس از فروش**: the ضمانت‌نامه is the written
  document a producer, importer, supplier or repairer gives the buyer, stating
  the period and what is fixed or replaced free; گارانتی is the everyday word
  for the coverage and for the company that provides it; خدمات پس از فروش is
  the wider after-sales service (service centres, parts supply) that can run
  longer than the warranty — one importer advertises an 18-month warranty with
  a five-year parts card.
  <https://kharazian.ir/knowledge/difference-guarantee-and-warranty>,
  <https://lg-group.ir/warranty-rules>
- **Consumer law**: قانون حمایت از حقوق مصرف‌کنندگان (۱۳۸۸/۰۷/۱۵) requires the
  supplier to hand over a written ضمانت‌نامه stating the period and type of
  guarantee together with an invoice showing the price and date (art. 9), and
  the executive regulations set the after-sales duties: a part replaced under
  warranty is itself guaranteed for six months, and if a fault cannot be
  fixed within two weeks in the warranty period (two months in the commitment
  period) the supplier must provide a replacement.
  <https://kharazian.ir/knowledge/difference-guarantee-and-warranty>,
  <https://tabagt.com/guaranty-policies>,
  <https://www.arkasupport.com/warrant-conditions>
- **The registry check** matters for phones: registration (رجیستری) ties the
  IMEI to a person, and a service centre asks for that person's national ID.
  <https://hamrahtalaei.com/guarantee> — the module records *whose name* the
  device is registered in, never a national ID number, and says what the desk
  will ask for.

**How warranty trackers present it**

- The ones people use sort by **what runs out first**, not by when it was
  added, and show days left on every row: Lapse ("one dashboard, sorted by
  urgency… closest to expiring is always on top"), Warranty Wallet (countdown
  rings, green/orange/red, Active/Expiring/Expired badges), Warranty Tracker
  ("your vault shows what needs attention this month, right at the top").
- **Reminder lead times** cluster at **30, 7 and 1 days**; some offer 1–90
  days: Warranty Keeper (30 days), Warranty Tracker & Bill Keeper and Warranty
  Drawer (30/7/1), Warranty Wallet (1–90), Warranty Logger (7/14/30/60).
- They carry a **claim kit**: product, serial, purchase date, warranty end and
  the bill, ready to share — Warranty Tracker's "one-tap claim kit", Warranty
  Hub's "insurance-ready PDF". Some keep the **repair contact's phone, email
  and website on the item** (Warranty Wallet).
  <https://lapse.apprem.io/>, <https://play.google.com/store/apps/details?id=app.trackwarranty>,
  <https://receiptiq.me/app-warranty-wallet>, <https://adelyons.com/apps/warrantydrawer/>,
  <https://www.warrantylogger.com/>, <https://www.fusioncoreapps.com/blog/best-warranty-tracker-apps-android>

Where sources disagree, this module chose: the person's **typed end date** is
the truth (never derived from a default duration), the **support number** is
the company's rather than the shop's, and **30 days** is the "ending soon"
window because it is the lead time every tracker above offers.

## Guide

**EN.** Add a purchase, its date and the cover you were given. Pick the kind of
cover — a company warranty, the shop's guarantee or after-sales service — then
a common term or the end date itself; the end is shown as you type. Add the
warranty company, its support number and the card number when you have them,
and say whose name the phone is registered in. The home screen keeps what ends
in the next 30 days at the top; each purchase opens to everything you need at
a service desk, a claim log, and a service file you can copy or share. A
reminder before the end is offered while you save.

**FA.** خرید، تاریخش و گارانتی‌ای که گرفته‌اید را اضافه کنید. نوع پوشش را
انتخاب کنید — گارانتی شرکت، ضمانت فروشنده یا خدمات پس از فروش — بعد یکی از
مدت‌های رایج یا خودِ تاریخ پایان را بنویسید؛ پایان همان‌جا نشان داده می‌شود.
اگر داشتید، شرکت گارانتی، شمارهٔ پشتیبانی و شمارهٔ کارت را هم بنویسید و بگویید
گوشی به نام چه کسی ثبت شده است. صفحهٔ اصلی آنچه در ۳۰ روز آینده تمام می‌شود را
بالا نگه می‌دارد؛ هر خرید همهٔ چیزهایی را که در مرکز خدمات لازم است، تاریخچهٔ
ادعا و یک پروندهٔ خدمات برای کپی یا اشتراک دارد. هنگام ذخیره، یادآوری پیش از
پایان هم پیشنهاد می‌شود.

## Changelog

**EN.** Warranties now keep the warranty company, its support line and the
card number beside the shop, put what ends in the next 30 days at the top, and
offer a reminder while you save — with a service file a repair centre can use.

**FA.** گارانتی‌ها حالا شرکت گارانتی، شمارهٔ پشتیبانی و شمارهٔ کارت را جدا از
فروشگاه نگه می‌دارد، آنچه در ۳۰ روز آینده تمام می‌شود را بالای فهرست می‌آورد و
هنگام ذخیره یادآوری پیشنهاد می‌کند — با پروندهٔ خدماتی که مرکز تعمیر می‌تواند
از آن استفاده کند.

## Platform requests

1. **Receipt photos.** The module cannot open the camera or the file system,
   so a receipt or warranty card is typed text and the editor says so. Wanted
   API: `NexModuleStore.putAttachment(kind, id, bytes, mimeType)` returning an
   opaque id that rides in backups and is deleted with its record, plus
   `nexPickModuleImage()` and an `NexModuleAttachment` view/opener. Without
   it, nothing is photographed and no document is implied.
2. **A page destination for notifications.** The app's own resolver still
   opens a purchase inside a sheet for a reminder tap; the module keeps
   `WarrantyDetailSheet` for exactly that caller while the normal way in is
   `WarrantyDetailPage`. Wanted: a module-declared page destination (or
   `nexShowSheet` no longer assumed by the resolver) so both paths are the same
   page.
3. **Reading a reminder back.** `NexModuleStore` has `setReminder` and
   `clearReminder` but no reader, so an edit cannot show "on, 30 days before"
   and must offer a new one instead. Wanted: `reminderFor(key)` returning the
   stored moment.
4. **Dialing.** There is no way to place a call from a module; the support
   number is copied instead. Wanted: `nexModuleDial(phone)` behind the same
   explicit-tap rule as `nexModuleShareText`.
5. **Transactions / compare-and-write** (carried over). The public API has no
   transaction; the durable journal keeps local compound delete/Undo
   recoverable, and independent external writers still need core support.

No hidden network, file or private-core access. Nothing is sent anywhere.

## Checks

Flutter 3.47.9 / Dart 3.13.7 (the pinned `.fvmrc`), from `apps/client`.
`dart format` on every changed file; `flutter analyze --fatal-infos` on the
module and its tests: no issues, 0 infos. Module tests and the kit gate pass;
the whole client suite was run once. No file in the module is over 400 lines;
en/fa string parity is checked by the gate.

~~~text
$ flutter analyze --fatal-infos
No issues found! (ran in 5.6s)

$ flutter test test/module_kit_test.dart test/modules/warranty
00:17 +156: All tests passed!

$ flutter test
06:41 +3580 ~4: All tests passed!
~~~

Captured screens (`--dart-define=NEX_CAPTURE=<dir>` on
`test/modules/warranty/screen_review_test.dart`) are Flutter widget renders
with synthetic data, not device screenshots: list, purchase page and editor in
Persian dark and English light, plus 320×480 at text scale 2. Android
notification permission, the native keyboard, TalkBack and release builds
still need the owner's device check.
