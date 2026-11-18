# Word by Word (words)

**Job:** Upgrade (live). People use this module today; nothing saved may be
lost, hidden or changed in meaning, and nothing they use may disappear.
This pass is the language-learning upgrade (2.8.4).

## Audit

Read before changing a line: the folder, its README, its tests and the
review screens.

### What it did, screen by screen

1. **Home.** A deck card in ink and violet: how many words wait, a
   four-step ladder of where the words stand, and — until this pass — a
   **streak** pill of days in a row with an answer. Under it *Review
   settings* (new words a day, session size, the optional reminder). Then
   one sideways-scrolling row of statuses and tags, the search box, and one
   card per word: a language badge, the word and its meaning each in its own
   direction, a five-bar strength meter and where it stands. One floating
   action, *Add a word*; two icon actions, copy the list and paste a list.
2. **A word's page.** Word, language, meaning, example, note, tag; a
   progress panel with the ladder of rungs, counts, the next review day, an
   explicit repair action for an unreadable date, the added-on day, and
   pause; save and discard; every keystroke kept as a draft.
3. **Review.** Due cards first, then new ones within the day's allowance;
   tap to turn the card over, four answers with the interval each one gives,
   meaning first as a switch, skip, edit a card with no meaning, and a calm
   done state with the schedule explained.
4. **Paste a list.** One word per line, a Tab and the meaning after it, a
   preview, the same words skipped twice, and unconfirmed lines kept.
5. **The reminder.** Off by default; one notification at the chosen time on
   the next day with words waiting.

### What was below the standard, or missing from the brief

| # | Found | Status |
|---|---|---|
| A1 | A **streak** pill, which the brief forbids ("no streaks, no shaming, nothing lost for a missed day") | Done — removed, with its words and its count; replaced by the daily goal |
| A2 | No daily goal, and no quiet note of what is due today beyond the counts | Done — `goalPerDay` in settings, the goal pill in the hero, the line in the progress sheet |
| A3 | No decks: every word sat in one flat list | Done — kind `deck`, `deckId` on a card, a deck row on the home page, a deck field on a word, a deck in the paste sheet |
| A4 | Review was flashcards only; nothing was typed | Done — a typed answer per card, with forgiving matching |
| A5 | No multiple choice | Done — wrong choices drawn from the same deck first, both directions |
| A6 | Both directions existed only for flashcards | Done — meaning-first applies to typing and choices too |
| A7 | Example sentences existed but the brief wants them in practice | Already there and kept: the example shows on the turned card (now held by a test) |
| A8 | Paste accepted only a Tab between word and meaning | Done — Tab, dash, colon and equal sign; preview before saving unchanged |
| A9 | No view of progress ("words learned, words due, how review went this week") | Done — the progress sheet with the week's bars |
| A10 | Three files over the 400-line rule (visuals, review view, home screen) | Done — split into `words_badges.dart`, `words_review_practice.dart`, `words_home_filters.dart`; every file is now under 400 lines |
| A11 | The shared rules: no `duesBetween`, no `summarize` — listed as pending in `test/module_shared_rules_test.dart` | Done — `words_summary.dart`; `words` left both pending lists (see *Decisions*) |
| A12 | The reminder counted due days with its own loop | Done — it now counts through the module's one `duesBetween` |
| A13 | Saving, drafts, undo with its whole history, the duplicate question, the date repair, the reminder's wording | Audited and kept as they were; tests unchanged |
| A14 | Pronunciation, a home-screen card and a review inside the notification | **Not done** — outside the module API; see *Platform requests* |

## Maintainer review (2.8.4)

Reviewed after merge; saved fields keep their meaning (a card without
`deckId` is «no deck», a settings record without `goalPerDay` reads 10, and
every write keeps unknown fields). Changes:

- **Typed answers that a Persian reader would call right.** One sense of a
  meaning is enough when the senses are separated by «؛», «;», «،», «,» or
  «/», not only by new lines — «تاب‌آور» for «تاب‌آور؛ کسی که…»; a space and a
  half-space are the same gap («می روم» = «می‌روم»); the Arabic «ى» reads as «ی».
- **A word whose deck has gone is «no deck»** (`wordsCardDeck`): removed on
  another phone, or named by an older draft, it no longer falls out of every
  deck filter.
- Persian wording: the typing mode is «نوشتن», a wrong answer says
  «این نبود؛ پاسخ درست این است.»; the hint names half-spaces and senses.

## What it does

An offline vocabulary box that now also teaches: keep the words you meet,
group them into decks, and practise them three ways — as cards you turn
over, by typing the answer, or by choosing it — on the small fixed schedule
it already had. No dictionary, no translation, no audio, no network; every
meaning is yours.

The screens:

- **Home** (`words_screen.dart`): the hero with what waits, the goal and the
  ladder; review settings; a deck row when you have decks; search, statuses
  and tags; the words. Two icon actions in the bar — *Progress* and *Copy
  the list* — and *Paste a list*; one floating action, *Add a word*.
- **A word's page** (`words_card_page.dart`): the fields, the deck, the
  progress panel, pause, save and discard.
- **Review** (`words_review_page.dart`): the queue, the way the card is
  asked (flashcards, type, choose — in the header, one tap, a sheet), the
  card, the four answers, skip, and the done state.
- **The deck sheet** (`words_deck_picker.dart`): choose, make, rename and
  remove decks. Removing one keeps its words.
- **The paste sheet** (`words_batch_sheet.dart`): the lines, the language,
  the deck, the preview, the add.
- **The progress sheet** (`words_progress_sheet.dart`): learned, due,
  paused, kept, the goal, and seven bars for the week.

## Records

Kind `card`, stable store id, schema 2 — the same record as before, with one
field added:

```json
{"schema":2,"headword":"resilient","language":"English","meaning":"Able to recover.",
 "example":"Small steps build a resilient routine.","note":"","tag":"Reading",
 "createdAt":"2026-11-02T09:00:00","step":1,"due":"2026-11-20","lapses":0,"reps":3,
 "lastReview":"2026-11-02T09:05:00","introducedOn":"2026-10-23","paused":false,
 "deckId":"<deck record id, or empty>","log":[{"at":"2026-11-02T09:05:00","g":"good"}],
 "lastReviewId":"review-event-id"}
```

`deckId` is **added**: a card written before it reads as «no deck», never as
missing data, and every other field keeps its old meaning. Content fields are
strings; `createdAt`/`lastReview` are ISO instants; `due` and `introducedOn`
are real date-only ISO days; `step` is 0..5; `reps`/`lapses` are non-negative
integers; `log` holds `at` and grade `g`, oldest first, newest 200 kept.

Kind `settings`, fixed id `settings`: `{schema:2,newPerDay:10,sessionLimit:20,goalPerDay:10}`.
`goalPerDay` is **added**; a settings record without it reads as the default
10, and changing it preserves `newPerDay`, `sessionLimit` and unknown fields.
`newPerDay` 0 means no cap; `goalPerDay` 0 means no goal.

Kind `deck`, id from the store, schema 1:
`{"schema":1,"name":"The Little Prince","createdAt":"2026-11-01T09:00:00"}`.
Unknown fields are written back on rename.

Kind `draft` (`card:new`, `card:<id>`, `batch:new`) and kind `operation`
(`card:<id>`) are unchanged; the card and paste drafts also carry `deckId`.

## Decisions

- **Decks are records, not a field on a card.** A deck has a name of its own,
  can be renamed without touching a word, and can be removed while every
  word stays — the delete writes each card's `deckId` back to empty, one
  write at a time, so an interrupted delete cannot take a word with it.
  Two names that differ only in case are one deck.
- **The three ways of asking are the same queue.** A typed or chosen card
  still ends on Again/Hard/Good/Easy: the check says whether the answer
  matched, and only the person knows how hard it was. That keeps the
  schedule, the ladder and every saved record exactly as they were.
- **Forgiving matching** folds case, spacing and punctuation, the Persian and
  Arabic forms of ی and ک, harakat, the zero-width non-joiner, and Persian and
  Arabic digits. Any line of a multi-sense meaning is right. Nothing is
  guessed at: only what the person wrote is compared.
- **Wrong choices come from the same deck first**, then from the rest of the
  words; paused cards are never offered. The order is seeded by the card and
  its place in the session, so the same card shows the same choices on every
  rebuild instead of moving under the finger. A card with fewer than two
  choices is asked as typing instead — one option is not a question.
- **The goal, not a streak.** Ten answers a day by default, said as
  «3/10 today» and «Today: 3 of 10 reviews»; a missed day costs nothing and
  nothing counts the gap.
- **Progress from the log alone.** Learned means the 60-day rung; due means
  due today or overdue; the week counts answers by the local day they were
  given and marks the «again» ones. No levels, no fluency, no certificates.
- **A pasted line splits at the first Tab, dash, colon or equal sign.** A
  plain hyphen is not one, so «well-being» survives; a colon needs a space
  after it, so «10:30» and «https://…» survive. The first separator wins, so
  a meaning keeps its own colons.
- **Shared rules.** Dates falling due go through one
  `duesBetween(cards, from, to)` in `words_summary.dart`, which the reminder
  now uses too; each record has a `summarize` line. `ModuleDue` and
  `ModuleSummary` do not exist in the kit yet, so they are copied here with
  the fields `docs/18-module-kit.md` names, for the kit to replace in one
  move. There is no money in this module.
- **One file outside the module's folders changed:**
  `test/module_shared_rules_test.dart`, where `words` was taken off the two
  pending lists. The test says a module that meets a rule must leave the
  list, and that "upgrading a module is when it leaves"; the edit is those
  two lines. Nothing else outside `lib/modules/words/` and
  `test/modules/words/` was touched.
- **A card's added-on day, its review days and every other stored shape are
  untouched.** The absolute date a person reads still goes through
  `nexModuleDateLabel`; the module still has no typed date field.
- **The home page's deck row appears only when there is a deck.** With none,
  the page stays as quiet as it was and a deck is made from a word or from
  the paste sheet.

## Guide

**English.** Keep words and phrases with meanings you write yourself, and put
them in a deck when they belong to a book, a course or a trip. Paste a list
to add many at once — a Tab, a dash, a colon or «=» between the word and its
meaning — and look at the preview before anything is saved. Review a few at a
time: turn the card over, type the answer, or choose it; each answer still
asks how it went, and Again starts tomorrow while Good and Easy move further
out. Your goal — ten reviews a day by default — is a small invitation, not a
debt, and missing a day costs nothing.

**فارسی.** واژه‌ها را با معنایی که خودتان می‌نویسید نگه دارید و اگر به یک
کتاب، دوره یا سفر تعلق دارند، در یک دسته بگذارید. برای افزودن چندتایی، فهرست
را بچسبانید — بین واژه و معنا یک تب، خط تیره، دو نقطه یا «=» — و پیش از
ذخیره پیش‌نمایش را ببینید. هر بار چندتایی مرور کنید: کارت را برگردانید، پاسخ
را تایپ کنید یا از میان گزینه‌ها انتخاب کنید؛ هر پاسخ همچنان می‌پرسد چطور
بود، «دوباره» از فردا شروع می‌کند و «خوب» و «آسان» فاصله را بیشتر می‌کنند.
هدف روزانه — پیش‌فرض ده مرور — یک دعوت کوچک است، نه بدهی؛ روز ازدست‌رفته
هیچ چیزی کم نمی‌کند.

## Changelog

EN: Word by Word now learns your language with you — group words into decks,
practise them by typing or by choosing from the same deck's words, keep a
small daily goal, see how the week went, and paste a list separated by a Tab,
a dash, a colon or «=». The streak is gone, because a missed day costs
nothing.

FA: «واژه به واژه» حالا همراه یادگیری زبان شماست — واژه‌ها را در دسته‌ها
بگذارید، با تایپ کردن یا انتخاب از میان واژه‌های همان دسته تمرین کنید، یک
هدف کوچک روزانه داشته باشید، نتیجهٔ هفته را ببینید و فهرست را با تب، خط
تیره، دو نقطه یا «=» بچسبانید. شمارندهٔ روزهای پیوسته برداشته شد، چون یک روز
ازدست‌رفته چیزی را خراب نمی‌کند.

## Platform requests

1. **Spoken pronunciation (text to speech)** — the brief asks for it and the
   kit has no audio. Without it, every meaning stays written; the card shows
   the word in its own script and nothing is spoken.
2. **A learning card on the home screen** — outside the API today. Without
   it, what is due today is said on the module's own hero and in the
   reminder.
3. **A review exercise inside the notification** — the reminder names what
   is waiting and opens the session; the question itself lives in the app.
4. **Image sharing** — the brief asks for text sharing, which the module
   already does through `nexModuleShareText`; pictures of a page would need
   a kit piece that does not exist.
5. **Atomic compare-and-write across windows** — current serial writes,
   fresh checks, event IDs and recovery journals stay within the store API.

## Checks

Linux sandbox; Flutter 3.47.9 (`.fvmrc`) / Dart 3.13.7, `flutter pub get`
first.

```text
dart format lib/modules/words test/modules/words      # 0 changed
flutter analyze --fatal-infos                         # No issues found!
flutter test test/module_kit_test.dart test/module_shared_rules_test.dart test/modules/words -j 4
                                                      # 246 passed
flutter test -j 4                                     # 4190 passed, 4 skipped
```

The whole client suite was run once after the last change, with nothing
broken.

Tests kept and extended: FA/EN, both themes, 320×640 at scale 2 with reduced
motion, Jalali added-on labels, empty states, draft/batch/replay/raw-history
regressions, the scheduler's ladder against month ends and leap days, and —
new in this pass — forgiving matching (case, spacing, ی/ک, harakat, ZWNJ,
digits, multi-sense meanings), choices from the same deck with a stable
order, the goal and the week counted from the log, the deck lifecycle (make,
rename, remove without losing a word, move a word with its history), the
paste separators, both practice modes end to end, and a compatibility test
that opens records exactly as the live version writes them and checks that
grading and editing keep every field — including one this version does not
know.

Screenshots are in `review/`: `words_home_en_light.png`,
`words_home_fa_dark.png`, `words_practice_en_light.png`,
`words_practice_fa_dark.png` (with `words_en_light.png` / `words_fa_dark.png`
and `words_review_*.png` from the earlier pass). They are captured from the
real screens by `test/modules/words/words_upgrade_capture_test.dart`:

```text
flutter test test/modules/words/words_upgrade_capture_test.dart \
  --dart-define=NEX_CAPTURE=lib/modules/words/review
```

## Device checklist

In the order a person meets them:

1. Install the update on a phone that already has words; open the module.
   Every word, meaning, example, tag, review day and history is where it was;
   the hero shows the goal where the streak used to be.
2. Review a word as a flashcard — turn it over, answer «Good», see it come
   back three days out.
3. Review as **type**: type the meaning in different case and with a stray
   space; it says «Right.». Type something else; it says «Not quite» and
   still lets you grade.
4. Review as **choose**: the wrong choices belong to the same deck; a card
   with no deck borrows from your other words.
5. Turn on meaning first and repeat 2–4: the meaning is asked and the word
   is hidden until you reveal it.
6. Make a deck from a word («The Little Prince»), add two words to it, and
   filter the home list by it; tap its chip again to see everything.
7. Rename the deck, then remove it: the words are still there, with their
   review days.
8. Paste three lines separated by a dash, a colon and «=»; the preview shows
   the meanings before anything is saved, and the words land in the deck you
   chose.
9. Open **Progress**: learned, due, paused, the week's bars, and the goal.
10. Set the goal to 5, answer five cards, and check the hero says the goal is
    done — and that nothing complains the next day.
11. Turn the reminder on, set a time, and check the notification names how
    many words wait.
12. Persian, dark, and the largest text size: the review header, the deck
    row and the four answers all stay on the screen.
13. Tap **Progress** with the app switcher open, and check nothing private is
    left visible in the preview.

## Open questions

- **How many new words a day, and what goal?** The default stays 10 and 10.
  Should the goal follow the session size, or be one number for the whole app
  when that setting arrives?
- **Should a typed «Again» be suggested automatically?** Today the check says
  right or wrong and the person grades. Auto-grading would be quicker but
  would take the judgement away.
- **Decks of decks?** Not built. A book with chapters would need either a
  second level or named decks like «Book — chapter 3».
- **Should a deck be reviewable on its own?** The filter narrows the list; the
  session still draws from all words. A deck-only session is a small change,
  if that is what people want.
- **Do «learned» and the 60-day rung match what people mean by learned?** The
  module says plainly what the number is based on; a different word for the
  top rung may read more honestly.
- **Should the progress sheet live on the home page** rather than behind an
  icon, for people who never open it?
