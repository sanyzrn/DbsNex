# Word by Word (words)

## What it does

An independent offline vocabulary box. Capture a word/phrase, language label,
your own meaning (including multiple senses), example, note and tag/source.
Manual duplicate capture asks before adding another card. Search every content
field including language; filter New, Due, Learned or Paused and actual tags.
More than eight tags can be expanded. Review settings are a quiet disclosure.

Review due cards first, then new cards within the daily allowance. A separate
session size defaults to twenty. Reveal keeps the meaning out of the concealed
tree and semantics. Again/Hard/Good/Easy show their next intervals; a failed
card never loops inside one session. Skip for now records no grade.
Empty meanings have Add meaning and cannot be graded. Done is scrolling and
calm; reduced motion bypasses shape animation entirely.

Batch paste accepts one word per line, optionally a Tab and your typed meaning.
Preview before saving; at most 200 unique words per batch. Repeated and already
saved words in that language are reported. Partial failures retain unconfirmed
lines and meanings for retry. Card/batch drafts survive back/swipe/restart.
Discard removes a draft; failure keeps it recoverable. A failed draft read
blocks editing until Retry, rather than overwriting it with an empty checkpoint.

No dictionary, AI translation, audio, network, Nex-note import, file export,
reminders or background work. Every definition is user-entered.

## Records

Kind card, stable store ID, new schema 2:

~~~json
{"schema":2,"headword":"A word","language":"English","meaning":"Typed meaning",
"example":"Typed example","note":"","tag":"Reading","createdAt":"2026-10-13T12:00:00",
"step":1,"due":"2026-10-16","lapses":0,"reps":1,
"lastReview":"2026-10-13T12:05:00","introducedOn":"2026-10-13","paused":false,
"log":[{"at":"2026-10-13T12:05:00","g":"good"}],"lastReviewId":"review-event-id"}
~~~

Content fields are strings; createdAt/lastReview are ISO instants; due and
introducedOn are real date-only ISO days. step is 0..5; reps/lapses are
non-negative exact integers. paused is boolean. log holds at and grade g
(again/hard/good/easy), oldest first; grading retains the newest 200.
Lifetime counters and immutable introduction day survive that cap.
lastReviewId is a non-secret repository idempotency marker.

Schema-1 records default safely. Invalid dates remain unknown, not today.
Malformed timestamps and nonfinite/fractional counters are rejected.
Legacy introduction day is inferred from the earliest available valid log
before trimming. A day already lost by an older capped build cannot be invented.
Editing changes only content/version/introduction metadata in a fresh raw body;
raw progress, longer future logs, pause and unknown fields remain intact.
Pause changes only its flag. Review checks current state before writing:
deleted/paused/already-graded cards are refreshed/skipped and never recreated.
The same event ID confirms an interrupted committed write without grading twice.

Kind settings, fixed ID settings:
{schema:2,newPerDay:10,sessionLimit:20}. Daily options 5/10/20/0; session options
10/20/40/0. Zero explicitly means no cap. Valid legacy custom values up to 200
remain readable; malformed negatives/large values use bounded defaults.
Changing one setting preserves the other and unknown fields. Introduction
allowance counts retained cards introduced that local day, including paused ones.

Kind draft, IDs card:new, card:<id>, batch:new: {v:1,base,fields}. base is an
edit card's original content fingerprint, or {}. Card fields are raw
headword/language/meaning/example/note/tag plus recordId/createdAt; batch fields
are raw text/language. Writes coalesce serially and preserve unfinished input.
Completed new-card and stale-content checkpoints are ignored.
{v:1,discarded:true} can acknowledge failed delete cleanup. Closing awaits the
latest checkpoint; a failed initial read never starts a replacement.

Kind operation, ID card:<id>: {v:1,records:[{kind,id,body}]} temporarily journals
raw card + related edit-draft deletion. Interrupted deletes roll back before
the next read. Timed Undo restores raw fields/history, unknown data and stable
IDs; store-managed updatedAt changes.

## Decisions

A reviewed card with a missing/impossible review date shows it as unavailable.
The explicit Set review date to today action confirms first and preserves raw
history, pause state and unsaved wording. It never changes a now-valid schedule
from another review. Timestamp offsets are validated rather than normalized.


- Fixed ladder: 1/3/7/14/30/60 days. Again resets step 0 and tomorrow, adding
  an Again count; Hard repeats the interval, Good climbs one step, Easy two,
  capped at step 5. First Good schedules three days, Easy seven, Hard/Again one.
  Learned names the 60-day rung; no FSRS or certified proficiency claim.
- Schedule from the answer's local day, never the old overdue date.
  Validated civil-date differences use UTC coordinates, independent of DST.
- Due and new are distinct; session size caps the combined queue. No same
  card reappears within one session after Again or Skip.
- Duplicate identity folds case/whitespace in word and language. Batch keeps
  the first occurrence and reports repeats; manual capture supports second senses.
- Unknown scheduling dates are explicit and excluded from automatic due counts.
  Reads refresh on resume and reject stale responses.
- Persian due labels stay relative («۳ روز دیگر»); the one absolute date a
  person reads — the added-on day beyond a month, or a future one — goes
  through the shared `nexModuleDateLabel`, so it follows the person's
  calendar (Jalali for Persian) and their digits. Storage stays ISO/civil;
  the module has no typed date field, so no calendar entry is wired (the
  repair action sets the review day to today).
- Multiline input (meaning, example, note, batch paste) is the shared native
  `NexTextField`; one-line fields follow content direction. Read surfaces
  preserve mixed paragraph direction.
- Serial per-store writes, fresh checks, event IDs and journals reduce races.
  A cross-window compare-and-write transaction is outside the current API.

## Guide

**English.** Keep words and phrases with meanings you write yourself. Add an
example or source when useful. Back keeps a draft; Discard removes it. Paste
several lines for quick entry, optionally separating word and meaning with a
Tab, and preview first. Reviews follow a fixed one-to-sixty-day ladder:
Again starts tomorrow, Hard keeps the interval, Good climbs one step and Easy
two. Reveal before grading; edit or skip a card without a meaning. Due cards
come first, then a few new ones. Choose daily allowance and session size under
Review settings. Pause any card; editing words preserves review progress.

**فارسی.** واژه‌ها را با معنایی که خودتان می‌نویسید نگه دارید و اگر کمک
می‌کند مثال یا منبع اضافه کنید. برگشت، پیش‌نویس را نگه می‌دارد؛ «کنار گذاشتن
پیش‌نویس» آن را حذف می‌کند. چند خط بچسبانید و برای معنا، واژه و معنایش را با
یک تب جدا کنید؛ پیش از افزودن پیش‌نمایش را ببینید. مرور روی فاصله‌های ثابت
یک تا شصت روز است: «دوباره» از فردا شروع می‌کند، «سخت» فاصله را حفظ می‌کند،
«خوب» یک پله و «آسان» دو پله جلو می‌رود. پیش از پاسخ، معنا را آشکار کنید؛
کارت بی‌معنا را ویرایش یا فعلاً رد کنید. کارت‌های سررسید جلوترند و بعد چند
کارت تازه می‌آیند. سقف کارت تازه و اندازهٔ جلسه را از تنظیمات مرور انتخاب
کنید. توقف یا اصلاح متن، پیشرفت مرور را پاک نمی‌کند.

## Changelog

EN: Added-on dates now read through the shared label in the person's own
calendar (Jalali for Persian); the empty collection carries its own add
button, a filter that empties the list says so honestly, the session-done
line counts a single card correctly, Persian wording reads naturally, and
review-queue ties are decided, not accidental.

FA: تاریخ افزوده‌شدن با برچسب همگانی در تقویم خود شما (جلالی برای فارسی)
نوشته می‌شود؛ فهرست تهی دکمهٔ افزودن خودش را دارد، فیلتر بی‌نتیجه حقیقتش
را می‌گوید، پایان جلسهٔ تک‌کارت درست گفته می‌شود، فارسی روان‌تر شد و ترتیب
کارت‌های هم‌سررسید قطعی شد.

EN: Added explicit repair of unavailable review dates and corrected review-button
interval contrast using the actual button foreground.

FA: تاریخ مرور نامشخص با تأیید شما قابل اصلاح است؛ سابقه و متن تایپ‌شده حفظ
می‌شوند. خوانایی فاصله مرور روی دکمه‌ها نیز اصلاح شد.


**English.** Word by Word now preserves introduction dates and live progress,
bounds review sessions, recovers drafts, accepts typed meanings in batch paste,
retries partial saves, and supports compact, large-text reviews.

**فارسی.** واژه به واژه اکنون تاریخ اولین مرور و پیشرفت را حفظ می‌کند،
جلسه‌های محدود و پیش‌نویس قابل‌بازیابی دارد، ورود گروهیِ واژه و معنا را
پشتیبانی می‌کند و خطاهای ذخیره و نمایش متن بزرگ را بهتر مدیریت می‌کند.

## Platform requests

1. Fulfilled: the platform now ships the public native `NexTextField`, and
   every multiline field in the module (meaning, example, note, batch paste)
   uses it. One-line fields follow content direction as before; no local
   `EditableText` fallback remains.
2. Fulfilled: the absolute added-on date reads through the shared Jalali
   formatter (`nexModuleDateLabel`), following the person's calendar and
   digits. Due labels stay relative where they read better, and the module
   has no typed date field, so no calendar picker is wired.
3. Optional atomic compare-and-write for multi-window changes. Current serial
   writes, fresh checks, event IDs and recovery journals stay within the store API.
4. Approved export/import/notification APIs if added later. Not requested now:
   no reminders are scheduled — the module's review scheduling is its own and
   stays inside the session. Current paste is manual input, not an import from
   Nex notes.

## Checks

Linux sandbox; Flutter 3.35.5 / Dart 3.9.2. This review-and-upgrade pass:

~~~text
dart format lib/modules/words test/modules/words    # 0 changed
flutter analyze --fatal-infos                       # No issues found
flutter test test/module_kit_test.dart -j 2         # 40 passed
flutter test test/modules/words -j 2                # 90 passed
~~~

Test coverage kept and extended: FA/EN, both themes, 320x640 at scale 2 with
reduced motion, Jalali added-on labels, empty-state action, double-tap save,
deterministic session ties, draft/batch/replay/raw-history regressions, and
the scheduler's ladder against month ends, a year end and a leap day.

The original authoring pass (Windows/PowerShell, baseline cad5fca) ran the
same gate with --no-pub; its captures and outcomes live with that phase's
review/VALIDATION.md. No Android/device/TalkBack claim is made for either
pass. Maintainer const-registers WordsModule(), retires planned words and
incorporates Guide/Changelog before release/device checks.

## Meaning first, copy the list (2.1.13)

The review page has a switch to ask **meaning first**: the meaning is the front
of the card and the word is not in the tree until Reveal. Grading is the same
four buttons, once per card; a card with no meaning to show is asked forward.
The home screen can **copy the list on screen** (every word the filters leave)
as `word<TAB>meaning`, one line each — what the paste box reads back; line
breaks in a meaning become « ; ». No file is written.
