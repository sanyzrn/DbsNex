# Lent & borrowed

## 1. What it does

Remember who owes whom — money in the currency it was lent in, or a thing lent
and how many came back — without ever mixing up the direction. Lent and
borrowed are separate ledgers, a repayment is its own dated record so a loan
can be edited without losing its history, and a reminder on the due date can be
added without putting the person's name or the amount on a locked screen.
Iranian amounts are typed and read in **tomans or rials**, with the amount also
written **in words** under the field, because a dropped zero is the most common
mistake with money. Everything is local, offline and yours; nothing is sent,
shared or synced unless you ask.

Each screen:

- **Lent / Borrowed** (two tabs, one page): what is owed to you and what you
  owe, with an outstanding summary for the tab (per currency, never added
  across currencies), `Due soon` / `Overdue` / `Settled` filters, search over
  people, items and notes, and an overdue count up front. The New button takes
  the direction of the tab you are on. A row says what is still out — or, once
  settled, what came back — and the due date in words ("Due in 2 days",
  "1 day overdue", "Settled").
- **New / edit record** (sheet): direction, money or thing, who, and the
  amount with its words underneath. Dates and the note wait behind one button;
  the issue date is today and the due date is empty unless you set one, by
  typing `۱۴۰۵/۰۸/۲۶` or picking it on the shared calendar (Jalali on the
  Persian side). Nothing is lost if the sheet is dismissed: a draft is kept.
- **Record a return** (sheet): part or all of the remainder, dated today by
  default and never in the future or before the loan. The history of returns
  is listed on the record; any one of them can be taken back.
- **One record** (page): the total, the same total in words, what is still
  out, the two dates, then `Record a return`, `Mark fully returned` and
  `Reminder message`, the reminder, and the return history. Deleting is here
  too, with Undo for a few seconds.
- **Reminder** (on the record): a one-time reminder at a time you pick on the
  due date, through the module API's reminder control. Its notification says
  "A lent record is due today" until you turn on **Show who and how much on
  the lock screen** for that record; turning the switch re-words a reminder
  that is already set.
- **Reminder message** (sheet): a short, polite message in three tones —
  friendly, neutral, formal — copied with one tap, or shared through the
  phone's own share sheet. Nex never sends anything.
- **People** (page): one row per person saying, per currency and per
  direction, what they owe you and what you owe them — «به شما ۵۰٬۰۰۰ تومان
  بدهکار است» and «شما ۳۰٬۰۰۰ تومان بدهکارید» — never one number that mixes
  the two or the currencies. Tapping a person opens their records.
- **Amounts**: how Iranian amounts are said (toman or rial) is a choice in the
  list's overflow menu, on every screen that shows a number, and it changes
  nothing that is stored.

## 2. Records

All records live in this module's own store and travel in its backups. Every
read is defensive: a missing or impossible field falls back to a safe value and
never throws.

**`loan`** — one lending or borrowing, schema **v2**. Stored money is an
integer count of **whole rials**, items are an integer count.

```json
{"v":2,"currency":"IRR","currencyDecimals":0,"direction":"lent",
 "person":"سارا","type":"money","amount":500000,"what":"",
 "issued":"2026-10-01","due":"2026-10-15","note":"بلیت قطار"}
```

| field | type | meaning |
| --- | --- | --- |
| `v` | int | `2`; absent on records written before 2.1.11 and read as v2 |
| `direction` | string | `lent` (someone owes me) or `borrowed` (I owe); anything else reads as `lent` |
| `person` | string | the name as it was written; empty is allowed and shown as "No name" |
| `type` | string | `money` or `item`; anything else reads as `money` |
| `amount` | int | money: whole rials (whatever unit they are *said* in); items: the quantity. Never negative, capped at 2⁵³−1 |
| `currency` | string | three-letter code, `IRR` when absent or malformed |
| `currencyDecimals` | int | 0–4 for foreign currencies; `IRR` is always 0 (whole rials) |
| `what` | string | the thing lent; empty for money, and dropped when a record becomes money |
| `issued` | string | local civil date `YYYY-MM-DD`; a missing or impossible date reads as today |
| `due` | string or null | local civil date, or null for "no deadline"; an impossible date reads as null |
| `note` | string | free text, optional |
| `reminderDetail` | bool | written **only when true**; absent means the lock screen stays private |

**`return`** — one repayment or one return of things, its own record so the
history is never rewritten by an edit.

```json
{"loan":"l1","date":"2026-10-05","amount":200000}
```

`loan`: the parent's id; `date`: local civil date key, `""` when unknown (shown
as "date unknown", never as today); `amount`: whole rials, or how many things
came back, in the parent's units.

**`settings`** — the module's one preference, `{"v":1,"irrUnit":"toman"}`.
`irrUnit` is `toman` or `rial`; a missing or malformed record means toman.
Saving merges into the existing body, so a field a later version adds survives.

**`draft`** — written by `FormDraft` while a sheet is open, ids `loan:new`,
`loan:<id>`, `return:<id>`: `{v, base, fields}` with the field values as typed.
It is discarded by Cancel and cleared by Save; a stale draft whose record
changed underneath is refused rather than applied.

**`operation`** — the deletion journal, `{v:1, records:[{kind,id,body}]}`: a
full raw snapshot of the record, its returns and its drafts, written before the
deletion and removed after it, so an interrupted delete can be finished or
undone. The module API has no multi-record transaction; this journal is the
fallback.

**`__reminder`** — the platform's reminder record, written through
`NexModuleStore.setReminder` with `sourceKind: "loan"`, `sourceId`, `at`,
`title` and `body`. One reminder per record at most: setting a new time
replaces the old one.

Nothing here is read by another module, and no record counts toward progress or
balances elsewhere.

## 3. Decisions

- **Money is stored in whole rials, and toman is only how it is said.** One
  toman is ten rials; every record keeps whole rials, `irrUnit` decides whether
  a number is read as tomans (`۵۰٬۰۰۰ تومان`) or rials (`۵۰۰٬۰۰۰ ریال`). A toman
  amount shows one decimal only when the stored rials leave a remainder
  (`۱۲٬۰۰۰٬۰۰۰٫۱ تومان`), because a tenth of a toman is one rial and there is
  nothing smaller. Switching the unit re-reads the same rials; it never rescales
  a stored number, so a record keeps its meaning across the switch and across a
  future redenomination.
- **`IRR` is stored with zero decimals**, unlike ISO 4217's listed exponent of
  2: no one lends 0.37 rial. Foreign currencies keep the precision the code
  table gives them (USD/EUR 2, JPY/KRW 0, KWD/BHD 3, CLF 4), verified from
  SIX's List One on 2026-10-12.
- **Toman is the default**, because that is what people in Iran say, price and
  budget in (see Research); rial stays one tap away for anyone who thinks in
  the official unit.
- **The amount is also written in words under the field.** A dropped or doubled
  zero is the classic money mistake, and «یک میلیون و دویست هزار تومان» catches
  it before Save. The words are built from the same characters the parser reads
  — never from a second copy of the number — so they cannot drift.
- **Persian digits in the field, and either script accepted back.** In Persian
  the field reads `۱٬۲۰۰٬۰۰۰` with U+066C groups and U+066B decimals, typed
  Latin digits included; the parser accepts Latin, Persian and Arabic-Indic
  digits, `,`/`٬` groups and `.`/`٫` decimals, so a record written on either
  side of the app reads and edits the same.
- **Nothing is added across currencies.** A total, a person's summary and a
  list header are always per currency, and items are counted, not summed with
  money. There is no conversion and no rate lookup; the module never guesses
  what a euro is worth today.
- **The lock screen is private by default.** `reminderDetail` is off unless the
  person turns it on for that record; the notification body is then "A lent
  record is due today" with no name and no amount. Turning the switch on or off
  re-words a reminder that is already set, at exactly the same moment, so the
  choice is not a promise about next time only.
- **One reminder per record, on the due date.** It is withdrawn when the record
  is settled or deleted. There is no background service, no repeating alarm and
  no notification the person did not ask for.
- **Three tones, one message, no sending.** Friendly, neutral and formal, each
  short and never pushy — Persian politeness around money is a real skill, and
  the module offers wording rather than pressure (see Research). Copy is one
  tap; share opens the phone's own sheet; Nex itself sends nothing.
- **A settled row says what came back** ("Returned 500,000 tomans"), not "0
  tomans still out". A row never shows a zero for a closed record.
- **Outstanding = total − returns, never negative.** Returns are re-read and
  validated before every save and edit; a total below what came back is
  refused, and the currency or type is locked while a return exists, so a
  record's units can never be reinterpreted after the fact.
- **Dates are absolute**, entered on the person's own calendar: `YYYY/MM/DD` in
  the field, the shared Jalali-capable calendar beside it, and today/7/14/30
  presets. Years are accepted only in 1900–2100 so a Persian year is never
  stored as a civil one; a due date before the issue date, and a return in the
  future or before the loan, are refused with the reason said out loud.
- **Nothing typed is lost**: every sheet keeps a draft, and deleting a record
  (with its returns) can be undone for a few seconds from a banner.
- **Item counts read as a quantity**, not a bare number: «۱ عدد کولهپشتی
  هنوز مانده» in Persian, "1 × Blue backpack still out" in English.
- **The unit switch lives in the list's overflow menu**, not on the record: it
  is a reading preference for the whole module, and a control that looks like
  it edits one record must not silently change all of them.

## 4. Research

Checked 2026-11-15. Everything the module needs at runtime is built in: the
currency precision table, the number-to-words words, the dates and the message
templates; nothing is fetched.

**Toman and rial in everyday use.**

- *Currency in Iran*, Visit Iran (Ministry of Cultural Heritage, Tourism and
  Handicrafts), <https://www.visitiran.ir/en/currency-iran-1>: the official
  currency is the rial, on notes, coins and official papers, while "Iranians
  almost always use 'Toman' in their daily life"; one toman is ten rials.
- *Difference between Toman and Rial*, Living in Tehran,
  <https://livingintehran.com/2022/03/22/difference-between-toman-and-rial>:
  banknotes, statements and documents use rials, but "almost everyone in
  Tehran, from taxi drivers to shopkeepers, talks and quotes prices in tomans";
  people also drop the thousands, so "50 toman" in a shop means 50,000 tomans.
  (The same page's price tables are what convinced me a grouped number with the
  unit word is clearer than a bare figure.)
- Both sources agree that mixing the two is the classic source of confusion,
  which is why the module says the unit in words next to every amount and keeps
  the choice in one place.

**The 2025 redenomination (four zeros).** Sources differ on the name of the
future unit, and this mattered to the module's design:

- Reuters, *Iranian parliament approves currency redenomination*, 5 Oct 2025,
  <https://www.reuters.com/world/middle-east/iranian-parliament-approves-currency-redenomination-2025-10-05>:
  parliament approved removing four zeros "over the next few years".
- Tehran Times, *Parliament approves plan to remove 4 zeros from national
  currency*, 5 Oct 2025,
  <https://www.tehrantimes.com/news/518711/Parliament-approves-plan-to-remove-4-zeros-from-national-currency>:
  10,000 current rials will equal one new rial, divided into 100 qerans, with up
  to three years of dual circulation.
- BBC News فارسی, *مجلس ایران با حذف چهار صفر از پول ملی موافقت کرد*, 5 Oct 2025,
  <https://www.bbc.com/persian/articles/cdjz0mye0z3o>: the unit stays the rial
  («واحد پول ایران ریال باقی می‌ماند»).
- bne IntelliNews, *Iran to phase out old rial by 2030 in four-zero
  redenomination*, 24 Feb 2026,
  <https://www.intellinews.com/iran-to-phase-out-old-rial-by-2030-in-four-zero-redenomination-427812>:
  the amending law was passed on 30 Oct 2025 and came into force on 7 Dec 2025;
  two years of preparation to Dec 2027, then up to three years of dual
  circulation; the name stays "rial", with a qiran subunit.

Earlier drafts would have renamed the unit "toman", and traveller guides still
describe a "toman redenomination" — a good example of why a debt tracker must
not apply a reform by itself. **Choice:** the module stores whole rials and
applies no factor; if a redenomination is ever implemented, old records keep
their exact stored rials and the person decides what they mean. The toman/rial
switch remains a reading preference, not a conversion.

**Writing numbers the way Persian reads them.**

- CLDR, *Persian* (Unicode),
  <https://cldr.unicode.org/translation/language-specific/persian>: Persian uses
  U+06F0–U+06F9 for digits, U+066B as the decimal separator and U+066C as the
  thousands separator — not the Arabic-Indic set, and not `,` or `/`. The
  module follows this in every Persian string and in the amount field.
- r12a, *Persian orthography notes*,
  <https://r12a.github.io/scripts/arab/pes>: the same digit set, with the note
  that Persian ۴۵۶ differ in shape from Arabic ٤٥٦.
- Elon.io, *Persian Digits*,
  <https://elon.io/grammar/farsi/writing-system/word-boundaries-and-input/persian-digits-19>:
  a number is an "internally left-to-right island" inside right-to-left text —
  digits are never reversed to fit the sentence. That is why the amount field is
  left-to-right even on the Persian side, and why a foreign currency code is
  isolated from the surrounding sentence.
- Elon.io, *Building Tens, Hundreds, and Thousands*,
  <https://elon.io/grammar/farsi/numbers/core-number-grammar/building-tens-hundreds-and-thousands-2>:
  every non-zero part of a number is joined with و («دویست و چهل و سه»), bare
  هزار is normal for 1,000, and یک میلیون is ordinary for 1,000,000.
- Persian Language Online, *Numbers*, <https://persianlanguageonline.com/numbers>:
  the same tens + و + units pattern («بیست و پنج»).

**Choice for the words:** groups of three joined with «و»; ۱۰۰ and ۱۰۰۰ stand
alone («صد»، «هزار»); ۱۰⁶ and ۱۰⁹ take «یک» because that is how they are said;
۱۰¹² is «هزار میلیارد», which is what people say, rather than «تریلیون»; and
«بیلیون»/«تریلیون» are never generated. The conversion is tested up to
hundreds of billions, including the boundaries where a group is zero.

**Asking for money without offence (Persian).**

- نمناک, *نمونه پیام درخواست پرداخت بدهی و متن برای گرفتن طلب*,
  <https://namnak.com/debt-payment-request-letter.p71028>: sample messages that
  open by asking whether the person's problem was solved and then leave the
  timing to them («چقدر زمان برای برگردوندن این پول برای شما مناسبه؟»).
- دلگرم, *۵۰ متن محترمانه درخواست طلب از دوست و مشتری*,
  <https://www.delgarm.com/m0rpwqd.a357128>: the piece states the trade-off
  plainly — too formal and the friendship is hurt, too friendly and the
  repayment slips — and offers friendly, neutral and formal registers.
- Cultural Atlas, *Iranian culture — etiquette*,
  <https://theculturalatlas.org/iranian-culture/iranian-culture-etiquette>:
  taarof means a friend may insist you needn't return something; the words are
  courtesy and "should not be taken for their face value". A reminder therefore
  has to be light enough to leave room for that dance.

**Choice for the message:** three tones (friendly / neutral / formal), each one
or two sentences, naming the amount and the due date once, ending with thanks
and leaving the timing to the other person; never a deadline invented by the
app, never a threat, never a demand. It is text to copy, not something Nex
sends.

**How well-known debt apps behave.**

- Splitwise, <https://www.splitwise.com/>: "Pay friends back — record any cash
  or online payment" (a repayment is a record of its own), 100+ currencies and
  balances kept **separate per currency**, with conversion only in the paid
  tier; a 2026 comparison,
  <https://www.evenoutapp.com/alternatives/splitwise-vs-tricount-vs-settle-up>,
  confirms the per-currency balances and that Tricount/Settle Up instead convert
  at a rate.
- Settle Up, App Store listing,
  <https://apps.apple.com/us/app/settle-up-group-expenses/id737534985>: "will
  even remind group members automatically and nudge them to settle their
  debts", all currencies with live rates, works offline; its tips page,
  <https://settleup.io/tips>, explains editable exchange rates.
- IONOS, *Which split app works best for bill splitting?*,
  <https://www.ionos.co.uk/digitalguide/online-marketing/web-analytics/best-bill-splitting-apps>:
  Splitwise sends "personalised reminders" for repayment.

**What the module took from them, and what it left out:** a repayment is its own
dated record and the balance is derived (Splitwise, Settle Up); reminders are a
first-class part of a debt (both); balances are per currency and never converted
(Splitwise's default, and the only honest option offline). It left out the
cloud group, the exchange rates and the automatic nudge: Nex promises that
nothing leaves the phone, and it must not guess a rate to show a single total.

## 5. Guide

**English:** Choose Lent or Borrowed, then add what was lent or borrowed —
money in its currency, or a thing and how many. Iranian amounts are said in
tomans or rials, whichever you prefer (the list's menu), and the amount appears
in words under the field so a wrong zero is easy to see. Add a due date if
there is one, by typing it or picking it on the calendar; record each partial
return and the remainder follows. On the record you can add a reminder for the
due date — by default it says only that a record is due, and you can ask it to
name the person and the amount. Reminder message gives you a short, polite
message in three tones to copy or share. The People page shows what each person
owes you and what you owe them, per currency. Everything stays on this phone.

**فارسی:** «قرض داده» یا «قرض گرفته» را انتخاب کنید و ثبت کنید چه چیزی قرض
داده یا گرفته‌اید: پول با ارز خودش، یا یک وسیله و تعدادش. مبلغ‌های ایرانی را
می‌توانید به تومان یا ریال ببینید و بنویسید — هر کدام را ترجیح می‌دهید (از
منوی بالای فهرست) — و مبلغ زیر کادر به حروف نوشته می‌شود تا صفرِ کم یا زیاد
زود دیده شود. اگر موعدی دارد، آن را تایپ کنید یا از تقویم انتخاب کنید؛ هر
برگشت جزئی را ثبت کنید تا باقی‌مانده خودش به‌روز شود. در صفحهٔ هر مورد
می‌توانید برای روز موعد یادآوری بگذارید؛ به‌طور پیش‌فرض یادآوری فقط می‌گوید
یک مورد موعدش رسیده و اگر بخواهید می‌توانید نام و مبلغ را هم روی صفحهٔ قفل
نشان دهید. «پیام یادآوری» یک پیام کوتاه و مؤدبانه در سه لحن (دوستانه، معمولی،
رسمی) می‌سازد تا کپی یا به‌اشتراک بگذارید. صفحهٔ «اشخاص» نشان می‌دهد هر کس
به تفکیک ارز چقدر به شما بدهکار است و شما چقدر به او. همه‌چیز روی همین گوشی
می‌ماند.

## 6. Changelog

- EN: Lent & borrowed: amounts in tomans or rials with the same amount in
  words, a due-date reminder that keeps names and amounts off the lock screen
  unless you choose otherwise, a short polite message in three tones, and what
  each person owes you — per currency, never mixed.
- FA: قرض و طلب: مبلغ‌ها به تومان یا ریال با همان مبلغ به حروف، یادآوری روز
  موعد که نام و مبلغ را تا وقتی خودتان نخواهید روی صفحهٔ قفل نشان نمی‌دهد،
  پیام کوتاه و مؤدبانه در سه لحن، و حساب هر شخص به تفکیک ارز — بدون مخلوط
  کردن.

## 7. Platform requests

1. **Contacts, the camera and banking apps are not reachable from the module
   API**, and the module is built not to need them: a person is a typed name (no
   address book, no import), a debt is entered by hand (no receipt photo), and
   nothing is paid or collected from inside Nex (no bank or card link). The
   reminder message is text to copy or share, not a message the app sends. If
   contacts ever become available, the useful thing would be filling a person's
   name — never reading the address book silently.
2. **A multi-record write with an all-or-nothing guarantee.** Deleting a record
   means removing the loan, its returns and its drafts; the module writes a
   recovery journal first and restores it if a step fails, but the kit exposes
   no transaction that would make that atomic. The journal is the bounded
   offline fallback.
3. **A reminder title the module can choose.** The shared control titles every
   reminder from the platform's own string; the module passes its own title when
   it re-words an existing reminder, and works fine either way. Being able to set
   the title from the start would keep the wording consistent.
4. **A per-module "unit of money" preference.** This module keeps toman/rial in
   a `settings` record inside its own store, which travels with backups but is
   invisible to the platform. A shared preference would let other money-shaped
   modules agree with it.

## 8. Checks

Run on Linux from `apps/client`, with the repository's pinned Flutter 3.47.9 /
Dart 3.13.7. Only `lib/modules/lent_borrowed/` and
`test/modules/lent_borrowed/` were changed; `module_rollout.dart` was used
locally to see the module in the app and is **not** part of the change.

```text
flutter pub get
dart format <each changed file>
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart test/modules/lent_borrowed
flutter test
```

Results are recorded in the pull request description, with the exact last lines
of each command.
