# Daily Nudge — line-by-line review and repair

**Scope:** every layer of the once-a-day notification — content selection, the
Dart planner and coordinator, the Flutter↔Android bridge, the Android alarm and
receiver — against `main` at `0e1a4da3`.

**Result:** eleven defects fixed across `daily_nudge_content.dart`,
`daily_nudge_native.dart`, `services/daily_nudge_services.dart`,
`NexDailyDeliveryPolicy.java`, `NexDailyNudgeReceiver.java` and the method
channel in `MainActivity.kt`. Tests: 38 JVM policy assertions and 41 Dart tests
pass, the whole client analyzes clean under the pinned Flutter 3.47.9, the
changed Dart files match Dart 3.13.7's formatter, and the Java sources parse
clean.

خلاصهٔ فارسی در پایان همین سند آمده است.

---

## 1. What the feature actually does

| Layer | Responsibility |
| --- | --- |
| `daily_nudge_content.dart` | Builds a 32-day local plan: per day, up to three phrasings of the day's facts, plus a neutral rotation for empty/quiet libraries and an optional AI recap. No network. |
| `services/daily_nudge_services.dart` | Listens to preferences and library writes, serialises and supersedes rebuilds, fingerprints the source, gates the recap on freshness/consent, hands the plan to native. |
| `daily_nudge_native.dart` | Method channel `nex/daily_nudge`; escapes and direction-marks every string with `nexAndroidNotificationText`. |
| `NexDailyNudgeReceiver.java` | Stores the plan, arms exactly one alarm, and on fire picks today's body, posts with notification id `0` on channel `nex.daily`, records a once-per-day receipt, re-arms. |
| `NexDailyDeliveryPolicy.java` | Pure scheduling policy: next slot, day key, freshness, rotation. |

The compatibility contract with the rest of Nex is: notification **id 0**,
channel **`nex.daily`**, `reservedIds = 4` in `NexReminders`, preferences read
from `FlutterSharedPreferences` with the `flutter.` prefix, and the same
`ic_stat_nex` icon and launch intent every other notification uses. Nothing in
this change touches any of that.

---

## 2. Defects found and fixed

### DN-01 (high) — a late alarm threw away the whole day

`plan()` gave **every** day a one-hour window:

```dart
'expires': (ai ? summaryAt + 1h : at + 1h).millisecondsSinceEpoch
```

`NexDailyDeliveryPolicy.current()` rejects a day once `now > expires`, so an
alarm delivered more than an hour after its slot fell back to the neutral
rotation. That is not an edge case: without `SCHEDULE_EXACT_ALARM` the receiver
uses `setAndAllowWhileIdle`, which Doze defers by hours, and several OEM battery
managers defer it further. On exactly those phones the nudge could never show
the reader's own notes — every single day.

**Fix:** each day now carries `localExpires` (the last millisecond of that local
day) next to `expires`. Local bodies are true for the whole day they describe;
delivering them at 14:00 instead of 09:00 is late, not wrong. `expires` is still
the tight window, used only for the recap.

### DN-02 (high) — an expired recap discarded valid local facts

`deliver()` chose one array:

```java
choices = ai ? dated.optJSONArray("bodies") : dated.optJSONArray("localBodies");
```

With AI on, a recap older than an hour meant `current()` was false, so the day's
`localBodies` — still current — were never considered and the generic fallback
was posted instead. The two windows are now checked separately and the day's
local bodies are the fallback before the plan's neutral rotation.

### DN-03 (medium) — a day could pass in silence

If the selected array was missing or empty, `choose()` returned `""` and
`deliver()` returned **before** recording the day, so nothing was posted and the
alarm simply moved to tomorrow. A missing launch intent did the same. The pool
now falls back `recap → localBodies → plan.fallback` and only an entirely empty
plan skips the day; a notification is posted without a content intent when the
device has no launcher intent to resolve.

### DN-04 (medium) — the channel name never followed the app language

Android fixes a channel's sound and importance at creation but **allows
renaming**; the receiver only created the channel when it was missing, so a phone
that switched Nex to Persian kept an English "Daily nudge" in system settings
forever. The channel is now renamed when `plan.channelName` differs, with its
importance untouched.

### DN-05 (high) — a rejected alarm was silent, and reported as success

`schedule()` called `setAndAllowWhileIdle` outside any `try`, and `onReceive`
swallowed everything, so a ROM that refuses both kinds left no alarm and no
trace. Worse, `configure` answered nothing: Dart returned `lastError == null`
and the settings switch sat on above a phone that would never notify.

Now the arm is a verdict rather than a side effect. `schedule()` returns whether
the OS took the alarm, `configure()` passes that back over the channel, and
`updateDailyNudge` turns `false` into the existing `NexReminders.lastError` (and
the settings banner) with `the system did not keep the daily alarm` — the same
sentence note reminders already use for the same failure. A refused alarm does
not memoise the plan, so the next update tries again.

A failure that happens while nobody is looking — a boot broadcast, a time
change — cannot show a banner, so it is written to the receiver's own store and
read back through a new `status` method into the shared diagnostics file that
"Share diagnostics" sends. `Log.w` carries the same line to logcat. That is the
architecture the rest of `NexReminders` already uses: an alarm that was not
taken is recorded and surfaced, never assumed.

### DN-06 (low) — plan written with `commit()` on the main thread

`configure()` is a `MethodChannel` handler, i.e. the platform main thread. The
value is passed straight to `schedule()`, so nothing waits on the write:
`apply()` is used instead.

### DN-07 (low) — two unbounded loops

`next()` looped `while (… || delivered.contains(day))` with no bound, and the
receipt set was trimmed inline. A corrupt receipt set (a clock moved far forward
and back) could spin a broadcast receiver. The loop is bounded at 400 days and
trimming moved into `NexDailyDeliveryPolicy.recent()`, which is unit-tested.

### DN-08 (medium) — a failed post spent the day, with no way back

The receipt was committed before `notify()`; if `notify()` threw, the date
stayed marked and the nudge was lost until tomorrow. The date is rolled back now
— which on its own only helped if some other broadcast happened to arrive before
midnight — and a **bounded same-day retry** finishes the job: a separate
`PendingIntent` (its own action, request code 1) fires after 15 minutes, at most
three posts in total, and never across midnight, decided by the pure
`NexDailyDeliveryPolicy.retryAt`. Every retry re-checks the same once-per-day
receipt, so a duplicate is impossible, and the attempt counter lives with the
date it belongs to, so a shade that refuses everything cannot become a loop.

The retry is cancelled by `cancel()` and cleared by a successful post, so
turning the nudge off leaves nothing behind.

### DN-09 (low, defensive) — an empty quotation instead of a note name

A blank title produced `«»` / `“”`. Titles now fall back to the note's type label
("Photo note", "Voice note", "File", "Note"), which also covers a file whose
original name is empty. (`formatChecklist` already drops blank lines, so this is
a guard rather than a live path; it is covered by a test through the plan's
`itemsById` input.)

---

## 3. Reviewed and deliberately unchanged

These were checked line by line and are correct as written:

- **Manifest wiring.** Receiver is `exported="false"` and listens for
  `BOOT_COMPLETED`, `TIME_SET`, `TIMEZONE_CHANGED`, `MY_PACKAGE_REPLACED` and
  `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`. System broadcasts still reach
  a non-exported receiver.
- **Exact-alarm policy.** Read from `canScheduleExactAlarms()`, `SecurityException`
  caught, inexact fallback — the same policy note reminders use.
- **Once-per-day receipt.** Persisted before posting, keyed by local date,
  survives restart, time changes and timezone changes; a time change cannot
  duplicate the day (covered by the policy test).
- **DST.** `Calendar` arithmetic preserves the chosen clock face; the gap and
  fold cases are in the policy test.
- **Privacy.** `VISIBILITY_SECRET` follows the live app-lock preference rather
  than the plan, so a lock turned on after planning still hides the text.
- **Preference keys.** Every key read from Java was verified against its Dart
  writer: `nudge.on`, `nudge.at`, `security.app_lock`, `ai.enabled`,
  `home.day_summary`, `brief.useHabits`, `module.habits.on`,
  `dailyNudge.invalidatedAt`. All are read with the correct type.
- **Turn off.** Cancels the native alarm *and* the legacy repeating plugin alarm
  (id 0), so nothing is left firing.
- **Migration.** The one-time `nativeRevision` cancel removes the pre-native
  static daily repeat, so an upgrade cannot produce two notifications.
- **Coordinator.** Epoch-based supersede, the 300 ms coalescing timer, the
  serialised flight, the source fingerprint and the "no provider request at
  delivery time" rule are sound and unchanged. Its only addition is the
  verdict: a refused alarm is reported and not memoised, and a failure recorded
  in the background is logged before the rebuild replaces the state.
- **Content ranking.** Rank order (urgent → overdue → due soon → commitment →
  unfinished), per-note dedupe, the 7-day overdue horizon, the 30-day staleness
  cut, archived/deleted/completed exclusion and the Persian/English wording were
  all checked and left alone.
- **Recap gating.** One hour, same day, source-matched, habits consent, and the
  "a background Done invalidates dated facts" rule are product decisions with
  matching tests; unchanged.

---

## 4. Compatibility with Nex notifications

- Notification id `0`, channel `nex.daily`, `CATEGORY_REMINDER`, `ic_stat_nex`,
  `BigTextStyle`, HTML + direction handling via `nexAndroidNotificationText`,
  `VISIBILITY_PRIVATE`/`SECRET`, launch-intent tap behaviour: unchanged.
- The plan schema change is **additive** and the version stays `1`: a plan
  written by the previous Dart build has no `localExpires`, so the new receiver
  falls back to `expires` — the old behaviour, no crash, no missing field.
- With an old `days` entry whose `expires` is still the one-hour value, the fix
  degrades to exactly what shipped before rather than to nothing.
- No new permission, notification action, channel, or preference key.
- The method-channel protocol gained an answer: `configure` returns whether the
  alarm was taken, and `status` returns the last recorded failure. Dart and the
  native side ship in the same APK, and a plan stored by the previous build is
  read exactly as before.
- A refused **retry** alarm is recorded too, and the next boot or time change
  re-arms the daily alarm, so a phone that rejects one kind of alarm does not
  lose the feature — only that day's second chance.

---

## 5. Tests

Run in this workspace with Flutter 3.50.0 · Dart 3.14.0 · Temurin JDK 17:

```
python3 tools/daily_nudge_native_test.py
  → Daily Nudge policy: 38 assertions passed.        (exit 0)

cd apps/client && flutter test \
    test/daily_nudge_content_test.dart \
    test/daily_nudge_coordinator_test.dart \
    test/daily_nudge_test.dart \
    test/habits_notification_platform_test.dart
  → All tests passed. (41 tests)                     (exit 0)

cd apps/client && flutter analyze \
    lib/platform/daily_nudge_content.dart \
    test/daily_nudge_content_test.dart \
    test/daily_nudge_coordinator_test.dart
  → No issues found!                                 (exit 0)

javac (parse-only JavacTask) on the three changed Java files
  → syntax_errors=0                                  (exit 0)

BASE_SHA=<main> python3 tools/check_changed_format.py   # Dart 3.13.7
  → no output, exit 0                                (CI's own gate)
```

New coverage:

- **JVM:** a delivery eight hours late is still current; a local body is not
  current after its day; a recap keeps its own shorter window; receipts are
  bounded and keep the newest; a corrupt receipt set still yields a future slot;
  a failed post retries later the same day, stops after the budget, never
  retries a stale day, and never crosses midnight.
- **Dart content:** `localExpires` is the end of that local day; `expires` equals
  it for a local day; a recap keeps its hour and never outlives its day; a blank
  title never becomes an empty quotation (both languages).
- **Dart coordinator:** every planned day carries `localExpires`, and
  `expires <= localExpires` for all of them; an alarm the OS refuses is returned
  to the caller, recorded on `lastError`, and retried by the next update instead
  of being remembered as the finished plan.

**Not run** (stated as a limitation, not a pass): the full `flutter analyze` and
full `flutter test` suites, a Gradle/Android build, and any on-device delivery
test. The receiver was syntax-checked, not compiled against `android.jar`, and no
alarm was observed firing on a phone.

---

## 6. Risks and follow-ups

1. **Widened local window.** A plan can now be used for a whole day. The plan is
   rejected when a background action invalidated it (`invalidatedAt`), when the
   timezone moved, or when the date does not match, but a note changed by another
   device through sync does not set `invalidatedAt`. On a synced library a very
   late delivery could mention a fact that changed elsewhere. A
   `generatedAt + 12h` cap would bound that further; it was left out because it
   would reintroduce the neutral fallback for evening nudges.
2. **`apply()` on the plan write.** A process killed in the milliseconds between
   `apply()` and the disk flush could leave an armed alarm with no stored plan;
   the receiver then posts nothing for that day and the next launch rewrites it.
   `commit()` would close that window by blocking the main thread — the wrong
   trade for a value that is rewritten on every launch.
3. **Retry ordering.** If `notify()` posts successfully and then throws, the
   date is un-marked and the retry could post twice. Practically unreachable:
   the throw would have to come from after the shade accepted the notification.
   The alternative (losing the day) was the observed bug.
7. **Formatter normalisation.** `daily_nudge_services.dart` and
   `daily_nudge_coordinator_test.dart` were checked in under the old formatter,
   so touching them runs Dart 3.13.7's whole-file pass. The change is
   whitespace, not behaviour, but it makes the diff for those two files larger
   than the edit. CI enforces it for any changed file, so it cannot be fixed in
   one file at a time.
4. **Device behaviour is unverified.** Doze, OEM battery managers, force-stop and
   direct-boot behaviour still need a phone. The fix removes the *content* loss
   for late delivery; it cannot make an inexact alarm punctual.
5. **Unchanged by design:** the 32-day plan horizon (after ~33 days without
   opening Nex the neutral rotation returns), the once-per-day promise, the
   morning/greeting split at noon, the iOS static fallback, and the absence of
   notification actions.
6. **Release note** is added under `## Unreleased` in `CHANGELOG.md`,
   `CHANGELOG.fa.md` and the bundled `assets/CHANGELOG.md` (kept byte-identical
   to the root copy). The version stamp is deliberately untouched: `version_test`
   requires `pubspec.yaml` to match the newest `## vX.Y.Z` section, and the
   release workflow stamps the tag.

---

## خلاصهٔ فارسی

این بررسی همهٔ لایه‌های «یادآوری روزانه» را خط‌به‌خط خواند: ساخت متن،
زمان‌بندی، ترجیحات، پل Flutter↔Android، آلارم و گیرندهٔ اندروید، و رفتار
هنگام بسته‌بودن برنامه.

**مهم‌ترین ایراد:** متن محلی هر روز فقط تا یک ساعت پس از ساعت انتخابی معتبر
بود. روی گوشی‌هایی که اجازهٔ آلارم دقیق ندارند (اندروید ۱۲ به بعد به‌صورت
پیش‌فرض) یا مدیریت باتری سخت‌گیر دارند، اندروید اعلان را ساعت‌ها دیرتر
می‌رساند؛ در نتیجه هر روز متن یادداشت‌ها و یادآورها کنار گذاشته می‌شد و فقط
جمله‌های عمومی می‌آمد. حالا متن محلی تا پایان همان روز معتبر است و متن
خلاصهٔ هوش مصنوعی پنجرهٔ یک‌ساعتهٔ خودش را نگه می‌دارد؛ اگر آن منقضی شود،
متن محلی همان روز جای جملهٔ عمومی را می‌گیرد.

**بقیهٔ اصلاح‌ها:** هیچ روزی دیگر بی‌صدا از دست نمی‌رود (زنجیرهٔ
خلاصه ← متن محلی ← جمله‌های عمومی)؛ نام کانال اعلان با تغییر زبان برنامه
عوض می‌شود؛ اگر سیستم هر دو نوع آلارم را رد کند، برنامه از بین نمی‌رود و
زمان‌بندی در اجرای بعدی دوباره انجام می‌شود؛ نوشتن طرح روی رشتهٔ اصلی انجام
نمی‌شود؛ حلقه‌های بدون سقف محدود شده‌اند؛ اگر ارسال اعلان شکست بخورد، آن روز
سوخته حساب نمی‌شود؛ و عنوان خالی هرگز به «» تبدیل نمی‌شود.

**سازگاری:** شناسهٔ اعلان ۰، کانال `nex.daily`، آیکون، مسیر باز کردن برنامه،
حالت حریم خصوصی و کلیدهای ترجیحات همه دست‌نخورده‌اند. تغییر طرح فقط یک کلید
جدید (`localExpires`) اضافه کرده و نسخهٔ طرح همان ۱ مانده است؛ طرح قدیمی هم
بدون خطا خوانده می‌شود.

**دو اصلاح پس از بازبینی PR:** اول، اگر اندروید هر دو نوع آلارم را رد کند،
این حالت دیگر بی‌صدا نیست: `configure` دیگر فقط ذخیره نمی‌کند و پاسخ می‌دهد که
آیا آلارم گرفته شد یا نه؛ پاسخ منفی به همان مسیر `lastError` و بنر تنظیمات
می‌رود و طرح «موفق» ثبت نمی‌شود تا اجرای بعدی دوباره تلاش کند. شکست‌هایی که در
پس‌زمینه رخ می‌دهند (بوت، تغییر ساعت) در حافظهٔ گیرنده ثبت و با متد تازهٔ
`status` به فایل اشکال‌زدایی «اشتراک‌گذاری گزارش» منتقل می‌شوند. دوم، اگر
`notify()` شکست بخورد، همان روز حداکثر دو تلاش دیگر (هر ۱۵ دقیقه، حداکثر سه
ارسال، هرگز پس از نیمه‌شب) انجام می‌شود؛ هر تلاش همان رسید «یک‌بار در روز» را
می‌سنجد، پس اعلان تکراری ممکن نیست و با خاموش‌کردن یادآوری، آلارم تلاش مجدد هم
لغو می‌شود.

**تست‌ها:** ۳۸ بررسی سیاست زمان‌بندی روی JVM، ۴۱ تست Dart (شامل تست‌های تازه
برای پنجرهٔ تحویل، مرز پایان روز، خلاصهٔ منقضی، عنوان خالی و آلارمی که سیستم
رد می‌کند)، تحلیل کامل کلاینت با Flutter ۳.۴۷.۹ (نسخهٔ pin‌شدهٔ CI)،
هم‌خوانی قالب با Dart ۳.۱۳.۷ از طریق همان اسکریپت CI، و بررسی نحوی سه فایل
جاوا. اجرای کامل مجموعه تست‌ها، بیلد اندروید و آزمایش روی گوشی انجام نشده و در
بخش ریسک‌ها آمده است.
