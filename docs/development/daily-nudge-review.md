# Daily Nudge — line-by-line review and repair

**Scope:** every layer of the once-a-day notification — content selection, the
Dart planner and coordinator, the Flutter↔Android bridge, the Android alarm and
receiver — against `main` at `0e1a4da3`.

**Result:** nine defects fixed across `daily_nudge_content.dart`,
`NexDailyDeliveryPolicy.java` and `NexDailyNudgeReceiver.java`; the Dart
coordinator, the bridge and the notification contract were reviewed and are
unchanged. Tests: 34 JVM policy assertions and 30 Dart tests pass, the three
changed Dart files analyze clean, and the Java sources parse clean.

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

### DN-05 (medium) — a rejected alarm killed the feature until the next launch

`schedule()` guarded `setExactAndAllowWhileIdle` but called
`setAndAllowWhileIdle` outside any `try`, and `onReceive` swallowed everything.
A ROM that refuses both left no alarm and no trace. Both paths are guarded now;
the stored plan and preferences survive, so the next launch or boot re-arms it.

### DN-06 (low) — plan written with `commit()` on the main thread

`configure()` is a `MethodChannel` handler, i.e. the platform main thread. The
value is passed straight to `schedule()`, so nothing waits on the write:
`apply()` is used instead.

### DN-07 (low) — two unbounded loops

`next()` looped `while (… || delivered.contains(day))` with no bound, and the
receipt set was trimmed inline. A corrupt receipt set (a clock moved far forward
and back) could spin a broadcast receiver. The loop is bounded at 400 days and
trimming moved into `NexDailyDeliveryPolicy.recent()`, which is unit-tested.

### DN-08 (low) — a failed post spent the day

The receipt was committed before `notify()`; if `notify()` threw, the date stayed
marked and the nudge was lost until tomorrow. The date is rolled back on failure
so the next broadcast can deliver it.

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
  serialised flight, the source fingerprint, and the "no provider request at
  delivery time" rule are sound; no change needed.
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

---

## 5. Tests

Run in this workspace with Flutter 3.50.0 · Dart 3.14.0 · Temurin JDK 17:

```
python3 tools/daily_nudge_native_test.py
  → Daily Nudge policy: 34 assertions passed.        (exit 0)

cd apps/client && flutter test \
    test/daily_nudge_content_test.dart \
    test/daily_nudge_coordinator_test.dart
  → All tests passed. (30 tests)                     (exit 0)

cd apps/client && flutter analyze \
    lib/platform/daily_nudge_content.dart \
    test/daily_nudge_content_test.dart \
    test/daily_nudge_coordinator_test.dart
  → No issues found!                                 (exit 0)

javac (parse-only JavacTask) on the three changed Java files
  → syntax_errors=0                                  (exit 0)
```

New coverage:

- **JVM:** a delivery eight hours late is still current; a local body is not
  current after its day; a recap keeps its own shorter window; receipts are
  bounded and keep the newest; a corrupt receipt set still yields a future slot.
- **Dart content:** `localExpires` is the end of that local day; `expires` equals
  it for a local day; a recap keeps its hour and never outlives its day; a blank
  title never becomes an empty quotation (both languages).
- **Dart coordinator:** every planned day carries `localExpires`, and
  `expires <= localExpires` for all of them.

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
3. **Receipt rollback.** If `notify()` posts successfully and then throws, the
   date is un-marked and a later broadcast could post twice. Practically
   unreachable, and the alternative (losing the day) was the observed bug.
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

**تست‌ها:** ۳۴ بررسی سیاست زمان‌بندی روی JVM، ۳۰ تست Dart (شامل تست‌های تازه
برای پنجرهٔ تحویل، مرز پایان روز، خلاصهٔ منقضی و عنوان خالی)، تحلیل بدون خطای
سه فایل Dart و بررسی نحوی سه فایل جاوا. اجرای کامل مجموعه تست‌ها، بیلد
اندروید و آزمایش روی گوشی انجام نشده و در بخش ریسک‌ها آمده است.
