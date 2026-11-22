# Lent & borrowed

## Audit (upgrade pass)

This module is live: every loan, return, settings record, draft and reminder
a person already has must read and save exactly as before. To check that, the
upgrade added a compatibility test that stores records as the current version
writes them, opens the list and the record, and saves an untouched edit back;
the body it writes is byte-for-byte the same map, and the split/card kinds it
adds do not appear in old records.

What was already good and is unchanged: two separate ledgers (lent and
borrowed), a repayment as its own dated record, per-currency totals that never
mix, toman/rial as a reading choice over whole-rial storage, amounts written
in words, Jalali dates through the shared calendar, drafts, journaled deletes
with banner Undo, three message tones, and the private-by-default reminder.

What was below the standard and is now fixed:

- **`loan_detail_screen.dart` was 506 lines**, over the module limit. The
  summary panel moved to `loan_detail_panels.dart` (a `part`, so its private
  widgets stay private); the screen is 387 lines and every test still passes.
- **`people_screen.dart` sat at 398 lines** with no room for the new message
  action. `PersonScreen` and its ledger panel moved to `person_screen.dart`;
  the people list is 231 lines and the person page 223.
- **No Audit section, no device checklist, no open questions** — added below.
- The list's overflow menu only chose toman/rial. It now also opens Splits and
  the card book; the unit choice is unmoved, one tap away as before.

What the brief asked for and did not exist (all done):

| Brief item | Now |
| --- | --- |
| Split a cost (دنگ): amount, payer, who shares it, equally or by shares or by exact amounts | A split holds several costs; each cost picks one of the three divisions, validated so the parts always add up to the cost |
| Several costs make a split (a trip, a shared month) | Costs live inside the split record, one write, one delete, one Undo |
| Settle up with the fewest transfers | Net position per person, then largest debtor pays largest creditor; at most one fewer transfer than people, deterministic, every transfer non-zero and never through a middle person |
| Each transfer can become an ordinary loan with one tap | Only transfers involving the person holding the phone (the split's `me`) offer it; it writes a normal `loan` with the split's name as its note, and a second tap does not duplicate it |
| A message per person: what they owe, to whom, and the card/IBAN to pay to | Message sheet on every person row, on the person page and beside each settle-up transfer; card and IBAN lines appear when saved |
| Book of cards and IBANs: 16-digit Luhn-checked card, `IR`+24-digit mod-97 IBAN, holder name, bank from the first six digits with a checked date, copy in one tap, grouped digits, Persian or English digits | `card` records and a Cards & IBANs page; offline validation, grouping, one-tap copy and delete with Undo |
| Never store CVV2, expiry, PIN or password | The card record has exactly four fields: person, holder, card, IBAN. A body carrying extra fields drops them on read, and there is no field in the sheet to type one |
| Never move money, open bank apps, or fetch | No deep links, no payment code, no network code in the module |

Not done, with the reason: **no "hide amounts" switch on the totals**. The
brief does not ask for one, and the module already keeps names and amounts off
the lock screen unless asked. It is listed under Open questions rather than
decided for the owner.

## Maintainer review (2.8.4)

Merged after checking the brief, `docs/18` and the design rules; changed:

- **Shares in whole tomans.** A cost that is a whole number of tomans is
  divided in tomans: 100,000 tomans among three is 33,334, 33,333 and
  33,333 — not 33,333.4, a tenth no one can pay. The parts still add up to
  the cost exactly; a cost in odd rials is divided to the rial as before.
- **The bank table, corrected and filled out.** 639346 is Sina Bank, not
  Saman; Refah Kargaran is 589463, not 627872. Twenty more issuer prefixes
  people pay from every day (Shahr, Ayandeh, Karafarin, Dey, Resalat,
  Gardeshgari, Iran Zamin and others) — only ones known for certain, so an
  unknown prefix still reads as "Bank not recognised".
- **Persian digits on the split page.** The head count beside the names
  was in Latin digits, and the names were joined with a Persian comma in
  English too.
- **`duesBetween` and `summarize`** (`loan_shared.dart`): each loan's due
  date with what is still out, signed in for lent and out for borrowed, in
  rials only, private; a line for a loan and a split, none for returns,
  settings, drafts or the card book. The module left the central pending
  lists.

Against "Shared across modules" (this branch predates the section):

| Rule | Here |
| --- | --- |
| 1 Dates falling due | `LoanShared.duesBetween` |
| 2 Money | whole rials; the live `amount` field keeps its name (rule 5) |
| 3 People | `person` stays a plain string: people's records already say it that way, and a live module's fields are never reshaped |
| 4 A line per record | `LoanShared.summarize` |
| 5 Unknown fields | kept on loans, returns and splits; a `card` record deliberately keeps only its four fields, so nothing like a CVV2 can ever ride along |
| 6 Saving, Undo | drafts, journaled deletes, banner Undo |
| 7 Reminders | the loan's own due-date reminder, private by default |
| 8 Sharing, hiding | text through `nexModuleShareText`; hiding amounts is an open question |
| 9 Look | shared pieces, `heroTag: null`, both languages and themes |

## Audit (2.8.15 pass)

Live module, so the rule is unchanged: nothing saved may be lost or changed
in meaning. Every record format stays exactly as it was — the one addition is
an optional `split` on a loan written from a settle-up, absent on every record
that existed — and this pass adds one test file
(`test/modules/lent_borrowed/audit_test.dart`, 18 tests).

What was wrong and is fixed:

- **An item's message dropped the count.** The sentence was given the number
  and never used it, so two lent backpacks read as one. English says
  «2 × Blue backpack», Persian «۲ عدد کوله‌پشتی».
- **A filter with nothing in it blamed the search.** Choosing **Overdue**
  with nothing late said «Nothing matches that»; each filter now has its own
  line, and only a real search says it found nothing.
- **Settling a loan recorded for a future date wrote a return before the
  loan.** "Mark fully returned" dates the return on the loan's own day when
  today is earlier.
- **The card sheet said «Add a card» while editing one**, and a second save
  for the same person (however the name is typed) added a second record to
  choose between. It says **Edit card**, and the save adopts the person's
  existing card record.
- **A settle-up could be recorded a second time on the next day.** The guard
  compared the loan's date with today; a recorded payment is now matched on
  who, how much, which way and the split's note, so the button reads
  **Recorded** and stays inert, today or next week.
- **A saved split could not be corrected at all** — only deleted and retyped.
- **A person's page could not start a record**, though it is where the next
  flatmate cost comes from.
- **Two lists ended under the floating button** (Cards & IBANs, Splits); both
  now make room, and the empty card book states its one action instead of
  also floating it.

What is new:

| Now | Where |
| --- | --- |
| A saved split is editable: rename it, change its date, add people, add or correct a cost | **Edit split** on the split's page; its cost rows open for correction, and a cost is added from the split itself |
| An edited split keeps its id and every field this version does not know, so a recorded loan still points at it | `split_detail_screen._writeCosts` writes `{...raw, ...split.toJson()}` |
| A transfer already recorded reads **Recorded** (disabled) instead of «Record as a loan» | `splitTransferRecorded`, matched without the date |
| Owing money offers **Ask to pay**: a message asking for the card or IBAN to pay to, with the card they saved attached | the record's actions, `loanPayMessage` with the person message sheet |
| A person's page starts their next record with the name written, and keeps that form's draft under that person | `initialPerson`; draft key `loan:new:<person>` |
| Two directions in one currency say what they net out to | the person's ledger, `LoanSummary.net` |
| The People page is searchable by name, with the module's letter folding | `people-search` |
| Card lines in a message carry a **Pay to:** heading | `messagePayTo` |
| Less repeated work on a busy page: returns bucketed once per page, one standings pass per list, and the loan list built lazily | `LoanSummary.ofBucketed`, `peopleOf`, `LoanListBody` |
| A half-written split asks before it is thrown away | `confirmSplitDiscard` |

Against "Shared across modules": the shared shape is untouched —
`duesBetween` and `summarize` unchanged, money still whole rials, `person`
still a plain string for the reason in 2.8.4, unknown loan/split fields kept
(the card record still keeps exactly four).

The editor's cost list and its discard question moved to
`split_cost_list.dart` and `split_discard.dart`, and the record's actions to
`loan_detail_panels.dart`; the largest files are 376, 372 and 369 lines.

## 1. What it does

Remember who owes whom — money in the currency it was lent in, or a thing lent
and how many came back — without ever mixing up the direction. Lent and
borrowed are separate ledgers, a repayment is its own dated record, and a
reminder on the due date can be added without putting the person's name or the
amount on a locked screen. Iranian amounts are typed and read in **tomans or
rials**, with the amount also written **in words** under the field. Everything
is local, offline and yours; nothing is sent, shared or synced unless you ask.

Each screen:

- **Lent / Borrowed** (two tabs, one page): what is owed to you and what you
  owe, outstanding summary per currency, `Due soon` / `Overdue` / `Settled`
  filters, search, overdue count, and a New button that takes the tab's
  direction. A filter with nothing in it says so in its own words. The
  overflow menu also opens **Splits** and **Cards & IBANs**.
- **New / edit record** (sheet): direction, money or thing, who, amount with
  its words underneath. Dates and the note wait behind one button; the issue
  date is today and the due date is empty unless set. Nothing typed is lost:
  a draft is kept.
- **Record a return** (sheet): part or all of the remainder, dated today by
  default and never in the future or before the loan; any return can be taken
  back.
- **One record** (page): total, the same total in words, what is still out,
  both dates, `Record a return`, `Mark fully returned`, `Reminder message`
  (and, when the record is money I owe, `Ask to pay`), the reminder, and the
  return history. Deleting is here too, with Undo.
- **Reminder** (on the record): a one-time alert at a time you pick on the due
  date. It says "A reminder you set for a loan is due" until you turn on
  **Show who and how much on the lock screen** for that record.
- **Reminder message** (sheet): friendly, neutral or formal, copied in one tap
  or shared through the phone's own sheet. Nex never sends anything.
- **People** (page): one row per person, per currency and per direction, plus
  a message button, and a search by name once there is more than one person.
  Tapping the row opens their records; the person page has its own message
  button, a New button that fills in that person, and the net of the two
  directions per currency.
- **Splits** (page): a list of trips and shared months with their totals.
  **New split** asks for a name, the people, which of them is you, and the
  costs. **One split** shows the total, everyone's net position, the fewest
  transfers, and each cost; a transfer to or from you has `Record as a loan`
  (reading **Recorded** once it has one) and `Message`, and a cost is added or
  corrected in place. **Edit split** changes the name, the date and the
  people. Deleting a split can be undone.
- **Cards & IBANs** (page): one row per person with the card grouped in fours,
  the bank the first six digits name, the IBAN in groups, the holder's name,
  and separate copy buttons for the card and the IBAN.

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
| `direction` | string | `lent` (someone owes me) or `borrowed` (I owe) |
| `person` | string | the name as written; empty reads as "No name" |
| `type` | string | `money` or `item` |
| `amount` | int | money: whole rials; items: quantity. 0…2⁵³−1 |
| `currency` | string | three-letter code, `IRR` when absent or malformed |
| `currencyDecimals` | int | 0–4 for foreign currencies; `IRR` is always 0 |
| `what` | string | the thing lent; empty for money |
| `issued` | string | civil date `YYYY-MM-DD`; missing reads as today |
| `due` | string or null | civil date, or null for "no deadline" |
| `note` | string | free text, optional |
| `reminderDetail` | bool | written **only when true** |
| `split` | string | the split id, written **only when** a settle-up made the loan; absent reads as empty |

**`return`** — one repayment or return of things, its own record.

```json
{"loan":"l1","date":"2026-10-05","amount":200000}
```

**`settings`** — `{"v":1,"irrUnit":"toman"}`; missing or malformed means toman.

**`split`** — a trip or shared month, schema v1. Costs are nested, so a split
reads and writes as one thing and cannot be half-deleted.

```json
{"v":1,"title":"سفر","date":"2026-11-01","me":"علی",
 "people":["علی","سارا","رضا"],
 "costs":[{"id":"c1","title":"شام","amount":9000000,"payer":"سارا",
           "mode":"equal","parts":{"علی":0,"سارا":0,"رضا":0}},
          {"id":"c2","title":"تاکسی","amount":3000000,"payer":"علی",
           "mode":"shares","parts":{"علی":1,"سارا":2,"رضا":1}}]}
```

`me` is the participant holding the phone, and only their transfers can become
loans or messages. `parts` holds the people who share the cost; for `shares`
the weights (≥1), for `amounts` the exact rials (summing to `amount`), and for
`equal` only the names matter. Money is whole rials, as everywhere else in the
module; a split is in `IRR` because settle-up transfers become rial loans.

**`card`** — one person's payment details, schema v1:
`{"v":1,"person":"سارا","holder":"سارا احمدی","card":"6037991234567893",
"iban":"IR820540102680020817909002"}`. The card is 16 digits or empty, the IBAN
is `IR` + 24 digits or empty; at least one must be valid to save. There is no
field for a CVV2, an expiry date, a PIN or a password, and unknown keys are
dropped by the reader.

**`draft`** and **`operation`** are unchanged, and **`__reminder`** is still
written only through `NexModuleStore.setReminder`.

## 3. Decisions

- **Money is stored in whole rials, and toman is only how it is said.** One
  toman is ten rials; `irrUnit` decides whether a number is read as tomans
  (`۵۰٬۰۰۰ تومان`) or rials (`۵۰۰٬۰۰۰ ریال`). A toman amount shows a decimal
  only when the stored rials leave a remainder. Switching the unit never
  rescales a stored number.
- **`IRR` is stored with zero decimals**, unlike ISO 4217's listed exponent.
  Foreign currencies keep the precision the code table gives them (verified
  from SIX's List One on 2026-10-12).
- **The amount is also written in words under the field**, built from the same
  text the parser reads, so a dropped or doubled zero is visible before Save.
- **Nothing is added across currencies**, and items are counted, not summed
  with money. No conversion and no rate lookup.
- **The lock screen is private by default.** `reminderDetail` is off unless
  the person turns it on for that record; toggling re-words an alarm already
  set, at the same moment.
- **One reminder per record, on the due date.** Withdrawn when the record is
  settled or deleted; no background service and no repeating alarm.
- **Three tones, one message, no sending.** Copy or the phone's share sheet.
- **Outstanding = total − returns, never negative**; over-repayment and a
  total below what came back are refused; currency/type are locked while a
  return exists.
- **Dates are absolute**, entered on the person's own calendar; a due date
  before the issue date, or a return in the future or before the loan, is
  refused with the reason in words.
- **Splits keep every rial.** Equal division spreads the remainder by name;
  shares divide by weight and give the remainder to the largest remainders
  (name as the tie-break); exact amounts must add up or the cost is refused.
  The parts of each cost always sum to the cost, so a balance can never be
  invented or lost.
- **Settle-up is largest-first.** Sort debtors and creditors by amount, match
  the largest pair each time; nobody is left in the middle and there is at
  most one transfer fewer than there are people. It is the standard "minimum
  cash flow" reading of "fewest transfers"; the module does not claim a proof
  of global optimality, and the same split always gives the same answer.
- **Only your own transfers become loans.** A transfer between two other
  people is real, but this module is *your* ledger; recording it as your loan
  would be a lie. A recorded transfer writes a normal `loan` with today's date,
  the split's name in the note, no due date, and the direction read from who
  pays whom.
- **A recorded transfer is recognised by what it is, not by the day.** The
  guard matches the person, the amount and the direction, because a payment
  recorded yesterday is still the same payment today; matching on today's date
  let a second identical loan be created the next day. Which payment it is
  comes from `split` on the loan — a link to the split that made it, so
  renaming the split afterwards cannot make it look unrecorded — and, for a
  loan recorded before that link existed, from the note naming the split. The
  same match makes the button read **Recorded**.
- **A split is edited in place.** Costs live in the split record, so adding
  or correcting one is a write of the same record with the same id: an
  ordinary loan already made from that split keeps pointing at it, and every
  field this version does not know is written back.
- **The two directions are netted only where both sides use a currency.**
  One line «net: … in your favour» answers the question the person's page is
  opened with; the direction lines stay, because which way the money runs is
  not the same fact as where it ends up.
- **Cards hold only what may be shown.** A card number is public to whoever is
  paid; a CVV2, an expiry date or a PIN is not, and the record has nowhere to
  put them. Validation is local: Luhn for the 16 digits, ISO 13616 mod 97 for
  the IBAN. The issuer table is a small copy in the module, marked with the day
  it was checked; an unknown prefix says "Bank not recognised" instead of
  guessing.
- **One card record per person**, keyed by the same folded name the rest of the
  module uses, so "Sara" and "سارا" with different spacing do not become two
  different payees.
- **Splits are in rials only.** Mixing currencies inside one settle-up would
  need a rate, and this module never guesses one; a foreign-currency trip is
  left to an ordinary loan record.

## 4. Research

The money and wording research from the first pass still holds (toman vs rial
in everyday use; the 2025 redenomination and why the module applies no factor;
CLDR's Persian digits; Persian politeness around asking for a debt; Splitwise
and Settle Up keeping balances per currency and a repayment as its own record).
It is not repeated here.

Added with the card book and splits, checked **2026-11-17**:

- **Luhn's checksum** (ISO/IEC 7812-1) is the check every card number carries:
  double every second digit from the right, sum the digits, and the total is a
  multiple of ten. It catches a single mistyped digit or a swapped pair; it is
  not proof the card exists, so the module says "checks out", never "valid
  card".
- **IBAN, ISO 13616**: an Iranian IBAN is `IR` plus 24 digits (26 characters).
  Moving the first four characters to the end, reading letters as numbers and
  taking the remainder modulo 97 must give 1. The module does that arithmetic
  locally and never asks a bank.
- **Issuer prefixes**: Iranian card numbers start with a six-digit bank
  identifier. The module keeps the small table it can stand behind (Melli,
  Mellat, Sepah, Tejarat, Post Bank, Maskan, Keshavarzi, Saderat, EN Bank,
  Ansar, Pasargad, Saman, Parsian, Sarmayeh, Central Bank, Refah, Mehr Eqtesad,
  Export Development) and marks the day it was read; anything else is
  "Bank not recognised", because a wrong bank name on a payment screen is worse
  than no name.
- **Bill splitting** (Splitwise, Tricount, Settle Up) informed the shape: costs
  belong to a group of people, each cost has one payer, a settlement is a
  payment between two people, and the fewest-transfers view is the standard
  greedy matching of debtors and creditors. The module leaves out the cloud
  group and the exchange rates, for the same reason the loan list does.

## 5. Guide

**English:** Lent or Borrowed, then add what was lent or borrowed — money in its
currency, or a thing and how many. Iranian amounts are said in tomans or rials
(list menu), and the amount appears in words under the field. Add a due date if
there is one; record each partial return and the remainder follows. On the record you can add a reminder for the due date — private unless you ask it to
name the person and amount. Reminder message gives you a short, polite message
in three tones to copy or share; when the record is money you owe, **Ask to
pay** writes the message that asks for the card or IBAN to pay to, with the
one they saved attached. The People page shows what each person owes you and
what you owe them, per currency, with a message button and a search by name;
a person's page starts their next record with their name already filled and
shows how the two directions net out. For a shared
cost, open **Splits** from the menu, name the trip, add the people and mark
which one is you, then add each cost with who paid and how it is divided. The
split shows everyone's position and the fewest payments; your own transfer can
become a loan record with one tap and then reads **Recorded**. A saved split
stays editable: add or correct a cost, rename it, change its date or its
people. Save a card or IBAN once under **Cards & IBANs**, and every message to
that person can carry it. Everything stays on this phone.

**فارسی:** «قرض داده» یا «قرض گرفته» را انتخاب کنید و ثبت کنید چه چیزی قرض
داده یا گرفته‌اید: پول با ارز خودش، یا یک وسیله و تعدادش. مبلغ‌های ایرانی را
می‌توانید به تومان یا ریال ببینید و بنویسید (از منوی فهرست) و مبلغ زیر کادر
به حروف می‌آید. اگر موعدی دارد، آن را تایپ کنید یا از تقویم انتخاب کنید؛ هر
برگشت جزئی را ثبت کنید تا باقی‌مانده به‌روز شود. در صفحهٔ هر مورد می‌توانید
یادآوری بگذارید؛ به‌طور پیش‌فرض نام و مبلغ روی صفحهٔ قفل نمی‌آید. «پیام
یادآوری» پیامی کوتاه و مؤدبانه در سه لحن می‌سازد؛ اگر پول را شما بدهکار باشید،
**«درخواست پرداخت»** پیامی می‌سازد که کارت یا شبای طرف را برای پرداخت می‌خواهد و
کارتی که ذخیره کرده را همراه دارد. صفحهٔ «اشخاص» حساب هر کس را به تفکیک ارز
نشان می‌دهد، دکمهٔ پیام و جست‌وجوی نام دارد؛ صفحهٔ هر شخص ثبت تازه را با نام خودش
باز می‌کند و خالص حساب دو طرف را نشان می‌دهد. برای هزینهٔ مشترک، از منو
**«دنگ‌ها»** را باز کنید، نام سفر را بنویسید، افراد را اضافه کنید و مشخص کنید
کدام‌یک خودتان هستید؛ بعد هر هزینه را با پرداخت‌کننده و شیوهٔ تقسیم اضافه
کنید. دنگ سهم هر کس و کمترین پرداخت‌ها را نشان می‌دهد، پرداخت خودتان با یک
لمس به قرض تبدیل می‌شود و بعد **«ثبت شد»** می‌خواند، و دنگ ذخیره‌شده ویرایش
می‌شود: هزینه اضافه یا اصلاح، نام و تاریخ و افراد. کارت یا شبا را یک‌بار در **«کارت‌ها و شبا»** ذخیره
کنید تا در پیام‌ها بیاید. همه‌چیز روی همین گوشی می‌ماند.

## 6. Changelog

- EN: Splits for trips and shared months — costs divided equally, by shares or
  by exact amounts, everyone's balance, and the fewest payments that settle
  them, each of yours becoming an ordinary loan with one tap. A message per
  person that can carry the card or IBAN they gave, and a small book of cards
  and IBANs with offline checks, the bank named from the card's first digits,
  and copy in one tap. Nothing already recorded changes.
- FA: «دنگ» برای سفر و ماه مشترک — هزینه‌ها مساوی، با سهم یا با مبلغ دقیق
  تقسیم می‌شوند، سهم هر کس و کمترین پرداخت‌ها دیده می‌شود و پرداخت شما با یک
  لمس به قرض معمولی تبدیل می‌شود. پیام برای هر شخص که می‌تواند کارت یا شبای
  او را همراه داشته باشد، و دفترچهٔ کوچک کارت و شبا با بررسی آفلاین، نام بانک
  از رقم‌های اول کارت و کپی یک‌لمسی. هیچ دادهٔ قبلی عوض نمی‌شود.

## 7. Platform requests

1. **Contacts, the camera and banking apps are not reachable** and the module
   is built not to need them: a person is a typed name, a debt is entered by
   hand, and nothing is paid from inside Nex. If contacts ever arrive, the
   useful thing is filling a name, never reading the address book silently.
2. **Recognising a card or IBAN written in an ordinary note** — "save this as
   Sara's card" — belongs on the timeline, outside this module: the module can
   validate and store one, but it cannot see notes.
3. **A multi-record write with an all-or-nothing guarantee.** Deleting a loan
   writes a recovery journal first; a split is one record, but a transfer
   recorded as a loan plus a later edit is two.
4. **A reminder title the module can choose**; the shared control titles from
   the platform's string, and the module re-words the body instead.
5. **A per-module money-unit preference** shared with other money modules;
   today it is a `settings` record in this module's store.
6. **A shared "hide amounts" affordance** for screens that show totals, if the
   owner wants one; the module has none today (see Open questions).

No clinical/financial advice, rate lookup or payment initiation is requested
or improvised.

## 8. Device checklist

1. Open the module with existing loans: every row, total, date, return and
   reminder reads as before the upgrade, in both languages.
2. Add a loan with a due date, record a partial return, then mark it settled;
   delete it and use Undo — the return history comes back with it.
3. Open the menu: toman/rial still switches the reading of every amount, and
   the new **Splits** and **Cards & IBANs** entries open their pages.
4. Create a split with three people and two costs, one equal and one by
   shares; check every share adds up to the cost and the balances sum to zero.
5. Tap **Record as a loan** on your own transfer: a normal record appears in
   Lent or Borrowed with the split's name in its note; tap again and no second
   record appears. Delete the split and Undo: all costs return.
6. Save a card with a real 16-digit number and an IBAN: the bank name appears
   only when the prefix is known, the number groups in fours, and copy puts it
   on the clipboard. Try a wrong digit and a wrong IBAN: both are refused.
7. Open a person's message from People: their balance is said per currency and
   their card/IBAN lines are present; copy and share work; with no card saved
   the sheet says so.
8. Turn on the reminder detail switch for one loan, then lock the phone and
   confirm the notification wording; turn it off and confirm the private
   wording comes back at the same time.
9. Persian/English, light/dark, text scale 2.0 and a narrow screen: the split
   editor, the cost sheet, the card sheet and the person message must all stay
   usable and keep their Save button reachable.
10. Open a saved split: rename it, add a cost, correct one, and tap a cost to
    edit it. The balances and transfers follow. Record a transfer, leave the
    page and come back: it still reads **Recorded**, and a second tap makes no
    second loan.
11. On a borrowed money record, open **Ask to pay**: the message names the
    remaining amount and carries the card saved for that person. On a person's
    page, **New record** opens with the name filled in, and leaving the split
    editor with something typed asks before discarding it.

## 9. Open questions

- Should a split support foreign currencies (with no conversion between them),
  or is rial-only the right limit?
- Should one person be allowed more than one card (a personal and a business
  account), or is one per person the clearer rule?
- Should other people's transfers be recordable at all, perhaps as a note,
  even though this module is your ledger?
- Does the owner want a "hide amounts" switch for the whole module, and should
  it be remembered per screen or globally?
- How stale may the issuer table get before the owner wants it refreshed, and
  should the module show its checked date on the card row rather than only in
  the sheet?
- Should the person's own name in a split default to the last-used `me`, so a
  regular flatmate does not pick it every time?

## 10. Checks

Run from `apps/client` on Linux with the repository's pinned Flutter 3.47.9 /
Dart 3.13.7, `LD_LIBRARY_PATH` pointed at a local `libsqlite3.so` because the
sandbox has no package manager:

```text
dart format <this module's lib and test folders>
flutter analyze --fatal-infos lib/modules/lent_borrowed test/modules/lent_borrowed
flutter analyze --fatal-infos
flutter test test/module_kit_test.dart test/modules/lent_borrowed
flutter test
```

Measured for this pass on Windows with Flutter 3.47.9 and `--no-pub` (pub.dev
refuses the sandbox): `dart format` clean; `flutter analyze --no-pub
--fatal-infos` over the whole client and again over this module — "No issues
found!"; the module gate `flutter test --no-pub test/module_kit_test.dart
test/modules/lent_borrowed` — **288 passed**, exit 0 (61 gate + 209 that
existed before, all still green, + 18 in `audit_test.dart`); the platform's
rule tests (`ui_consistency_test`, `menu_rule_test`, `sheet_swipe_test`,
`sheet_scrim_test`, `motion_test`, `text_field_rule_test`,
`module_shared_rules_test`, `module_glance_test`) — 89 passed; and one full
`flutter test --no-pub` — **4588 passed, 5 skipped, 13 failed**.

The 13 are not this module's. Eleven are in files that never import it and
that fail the same way when run alone: `attachments` and `attach_paths` on a
Windows temp-file lock in `nex_harness.dispose`, `brief_window` and
`home_brief_balance` on the smart brief, `card_audio`, `os_capture_bridge
(150 simultaneous shares)` and `sponsor_card`. One was a compile race from
editing during that run and passes on rerun. One was this pass's own and is
fixed: the Lent & Borrowed guide bullet had grown long enough to push the
app-lock passage past the assistant's passage budget that
`test/app_guide_test.dart` guards, so the bullet was tightened back to its old
length and that test passes.

No file is over 400 lines and the Persian words carry no bidi control
characters.

Screens in `review/`: the list, editor, detail, message,
people and person pages from before, plus `lent_upgrade_*` for splits, one
split's settle-up and the card book, all in Persian dark and English light.
They are widget renders with synthetic placeholder data, not device
screenshots. Android/iOS keyboards, the real share sheet, clipboard behaviour
and TalkBack/VoiceOver still need the owner's phone and the checklist above.

Only `lib/modules/lent_borrowed/` and `test/modules/lent_borrowed/` changed;
`module_rollout.dart`, the registry, the API, the ARB files and other modules
are untouched. The module was already available and stays as it is.
