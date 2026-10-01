# Nex 2.0 — Analysis and Roadmap

> **Status:** Proposal · **Written at:** v1.21.0 · **Revised at:** v1.82.0 ·
> **Decides nothing on its own.** What has shipped from it is listed in §13
> and taken out of the plan.
> Anything here that survives review becomes an ADR in
> [`10-decisions.md`](./10-decisions.md) and a row in
> [`08-roadmap.md`](./08-roadmap.md).

This is a design document, not a plan of record. It was written by reading the
code, the schema, the workflows and the docs — not by reading the roadmap and
restating it. Where it contradicts `08-roadmap.md`, the contradiction is the
point and is called out.

The v1.80.2 revision re-measured every number, removed what has shipped since
1.21, corrected what had drifted, and added §4 W6 (proposals from the
revision) and §12 (new product ideas).

---

## 0. A naming collision, first

`08-roadmap.md` uses **v1 / v2 / v3** as *thematic phases*: v1 MVP, v2 Sync &
Continuity, v3 The Intelligence Layer. The release train uses **1.x** as
ordinary semantic versions and is at **1.80.2**.

Those two numbering systems have come apart. Measured against the phase plan,
the app has shipped all of phase v3 — transcription, OCR, tag suggestions,
semantic search, summarisation, an assistant, a daily brief, an on-device
model — and much that no phase anticipated (a private vault, recurring items,
widgets, complete backups, the Persian calendar), while phase v2's headline,
*continuity across devices*, is still missing.

So: **"2.0" in this document means the next major release of the app**, not
phase v2. *Fixed in 1.85:* `08-roadmap.md` now names them Phase 1–3
(ADR-034), so "v2" below always means this document's release 2.0.

---

## 1. Where Nex actually is

Measured at `5deb554` (v1.80.2), not estimated.

| | |
|---|---|
| Dart, total | ~75,000 lines |
| `apps/client` | ~57,600 lines, of which ~11,800 are generated l10n |
| Largest files | `timeline_screen.dart` 4,059 · `note_detail_sheet.dart` 2,865 · `ai_chat_sheet.dart` 2,162 · `ai_provider.dart` 1,994 · `settings_sheet.dart` 1,953 · `nex_preferences.dart` 1,815 · `note_repository.dart` 1,668 |
| Files in `apps/client/lib` over 800 lines (excluding l10n) | 11 |
| `setState` call sites in the client | 247 |
| Test files | 93 client · 19 ui · 21 core · 27 data · 4 ai, plus backend and worker |
| Platforms actually shipping | Android only — the Windows and iOS CI jobs are `if: false` |
| Sync | engine implemented end to end; **no way to set it up in the app** |
| Encryption at rest | none for the library; the private vault uses the platform keystore |
| Telemetry | none, of any kind |
| Search budget in CI | 2,000 notes, 200 ms in every run; 50,000 notes at p95 in its own job (since 1.82) |

**What is genuinely strong**, and should be protected rather than rewritten:

- **The verification culture.** CI deletes `packages/ai` and proves the app
  still builds; analyses `core` and `data` with a Dart SDK that has no Flutter
  in it; runs the TypeScript and Dart merge implementations against one shared
  conformance file; runs a sync matrix against a live PostgreSQL. Release
  failures are fixed at the cause — 1.80.2 moved a flaky SQLite retry out of a
  test and into the data layer, where it protects real captures.
- **The sync core.** Field-aware merge, union-merge for tags, tombstones, `rev`
  and `device_id` on every syncable table, and new tables (`commitments`,
  `memory_records`) deliberately shaped so they can join sync later.
- **Local-first for real.** SQLite + FTS5 in WAL mode, a worker isolate, every
  write transaction through one contention-safe entry point, automatic and
  complete backups, export and import.
- **The comments.** The codebase explains its own reasoning to a degree that
  made this analysis possible in a few hours.

---

## 2. The critique

Six findings, ordered by how much they constrain the product.

### 2.1 Nex has become several products, and only one of them has a spec

`01-product-vision.md` lists seven non-negotiable principles. All seven are
about capture and retrieval: under three seconds, no mandatory fields, timeline
as home, local-first, learnable in thirty seconds.

Nothing in them governs the assistant, the daily brief, the memory store,
translation, the private vault or Recurring — which together are now most of
the app's surface. `ai_chat_sheet.dart` alone is larger than the entire
`packages/core` model layer.

The AI layer and the tools are not wrong; they are **ungoverned**: there is no
principle they can be measured against, so they can only grow. A 2.0 has to
answer, in one sentence, what Nex is now:

- *Nex is a capture inbox that happens to have AI in it* — then the AI surface
  should shrink and subordinate itself to capture and retrieval.
- *Nex is a thinking tool whose front door is instant capture* — then the vision
  document needs principles for the intelligence layer and the tools with the
  same teeth the capture ones have.

**This document proposes the second, with a specific constraint** — the
assistant's job is your own material, which 1.81 made visible with cited notes
(§13). The decision about the vision document is still the owner's.

### 2.2 Sync is built, but continuity is not

The engine works and is tested harder than most of the app. What a user touches
does not exist:

- **There is no way to turn it on.** The settings row was removed on purpose: it
  asked for a base URL and a bearer token nobody could obtain. The code stays
  until there is a pairing flow.
- **Sync never happens on its own.** When a server is configured, it runs only
  on pull-to-refresh.
- **Conflicts have no surface.** `sync_state` has a `'conflict'` value; no
  screen ever shows it.
- **There is no second device.** Windows and iOS are both `if: false` in CI.

The architecture's biggest investment returns nothing to a user today. That is
the clearest gap in the product and, by itself, would justify a major version.

### 2.3 Retrieval — resolved in 1.82

Vectors were JSON text parsed on every search (5.2 s at 10,000 notes), and
keyword search, meaning search and the assistant ranked separately. All of W2
shipped in 1.82; see §13 for what changed and the numbers.

### 2.4 The client's architecture cannot absorb many more features

Three screens carry ~9,100 lines between them, with 247 `setState` call sites
and no dependency injection. `nex_preferences.dart` alone holds 1,815 lines of
settings. There is no state layer beyond a few `ChangeNotifier`s.

The cost shows in the release history. The bug waves of 1.17 → 1.21 — text
direction, per-line direction, selection handles, the selection menu — were four
instances of one missing abstraction: no single place owns "a piece of the
user's own text". The 1.80.x series repeated the pattern with menus and
gestures (outside taps, a tap on the owning card, a swiped card): each surface
re-implements "a tap while something is open only closes it".

### 2.5 The data is not protected, and the app sends some of it away

There is an app lock and a keystore-backed private vault, but **no encryption at
rest for the library**: `nex.sqlite` and the media directory are plaintext.

Since 1.17 the assistant can read a focused note's file text and images, so
that content leaves the device whenever a cloud provider is configured. `09-ai.md`
states general AI privacy principles, but no ADR recorded that decision and
nothing showed the user what was sent. *The second half is fixed in 1.85* (W3.2,
ADR-033); encryption at rest (W3.1) is still open.

### 2.6 The product's own success metrics are unmeasurable

`01-product-vision.md` commits to capture and search under 3 s, search success
above 90% and crash-free capture sessions above 99.9%. With no telemetry of any
kind, none of these is measured. A local-only, opt-in, user-readable instrument
would turn four beliefs into four numbers.

---

## 3. What 2.0 should be

> **Nex 2.0: everything you capture, on every device you own, findable by
> meaning — and still yours.**

| Pillar | One-line test of success |
|---|---|
| **Continuity** | Capture on the phone, walk to the desk, it is already there. |
| **Retrieval** | One ranked answer across text, meaning, time and type — at 50,000 notes. |
| **Trust** | The device is a safe, and the app can show you exactly what has left it. |
| *(Foundation)* | The next feature costs what it should, not what four screens make it cost. |

The version identity is deliberately **not** "more AI". The intelligence layer
is the most developed part of the app; its grounding shipped in 1.81 (§13).

---

## 4. Workstreams

Each item: the problem, the proposal, the cost, and what it must not break.

### W1 — Continuity

**W1.1 Identity and pairing.** The desktop shows a QR code (or a six-word code),
the phone scans it, the server issues a per-device token. Self-hosting stays
first-class behind *Advanced*. No email, no password; a device pair is the
identity. This is also what brings the sync row back to Settings.
*Must not break:* the app stays fully usable with no pairing at all.

**W1.2 Sync that happens by itself.** Android `WorkManager`: periodic, on
connectivity regained, on app background, and a debounced push a few seconds
after a capture settles. Status is a quiet indicator, never a modal.
*Must not break:* capture never waits for sync; no sync on metered connections
unless allowed.

**W1.3 Media sync.** Content-addressed, resumable, chunked transfer keyed by the
existing `media_hash`; metadata and thumbnails first, full media on open, with a
per-device cache budget.
*Must not break:* a note whose media has not arrived still opens and says so.

**W1.4 A conflict surface.** "This note changed in two places": both versions,
keep mine / keep theirs / keep both. Rare by design, invisible today.

**W1.5 The second device.** Recommendation: **Windows before iOS.** The target
still builds and the job is one `if: false` away; iOS (signing, store review,
background execution) belongs in 2.1.

*W1.6 shipped in 1.87 — see §13.* Left open: the complete-backup format
encrypts settings and keys but not the notes, so a copy in a cloud folder is
readable by that cloud. Encrypting the library file belongs with W3.1/W3.3.

### W2 — Retrieval

All of W2 shipped in 1.82 — see §13.

### W3 — Trust

**W3.1 Encryption at rest.** SQLCipher for the database, media encrypted with a
Keystore-held key released by the app lock. **The highest-risk item in the
document**: an in-place migration of existing libraries, and a new backup
format. Ship only behind a proved, reversible migration tested against a
corrupted run; consider new installs first.

*W3.2 shipped in 1.85 — see §13.*

**W3.3 End-to-end encryption for sync — partial and honestly labelled.** Encrypt
content and media with a pairing-derived key; leave ids, `rev` and timestamps in
the clear so merge works, and say so. Design in 2.0, ship in 2.1 unless a hosted
service for other people is planned.

*W3.4 shipped in 1.89 — see §13.*

### W4 — Foundation (invisible, and first)

*W4.1 shipped in 1.86 — see §13.*

*W4.2 shipped in 1.88 — see §13.* Left open: three service classes are
still one class of over 800 lines each — `db_worker.dart`, `nex_services.dart`
and `reminders.dart`. Tests subclass `NexServices`, so splitting it into
extensions would turn overridable methods into static ones; it waits for a
reason to touch them.

*W4.3 shipped in 1.85 — see §13.*

*W4.4 shipped in 1.88 — see §13.*

*W4.5 shipped in 1.86 — see §13.*

### W7 — The home screen *(from §11, planned at 1.88)*

*W7.1, W7.2, W7.3 and W7.5 shipped in 1.90 — see §13.*

**W7.4 Empty states that act.** An empty page offers a shortcut to capture its
first item instead of only explaining itself. (Recurring's empty page does
this since 1.90; the rest are still to do.)

### W5 — Product

All of W5 shipped in 1.81 — see §13.

### W6 — Proposals from the v1.80.2 revision *(new)*

*W6.1's automated half shipped in 1.87 — see §13.* Left open: a TalkBack
session on a real phone (reading order, what each card announces), and the
vault screens, which the audit cannot reach without an unlock.

*W6.2 shipped in 1.86 — see §13.*

*W6.3 shipped in 1.89 — see §13.* Not done as written: an emulator on a CI
runner can only run a debug build, whose frame times say nothing about a phone.
The CI budget runs in the test VM instead, and a real phone's numbers come from
W3.4 on that phone.

*W6.4 shipped in 1.85 — see §13.*

**W6.5 Vault health.** Weak, reused and old password warnings, computed on the
device only; and TOTP codes stored alongside a login, so the vault can replace a
separate authenticator app.

---

## 5. Priorities

**Must have for 2.0:**

1. W1.1 + W1.2 pairing and automatic sync
2. W1.5 a second device actually shipping *(Windows)*

**Should have:**

3. W1.3 media sync
4. W3.1 encryption at rest — only when the migration is proved
5. W7.4 empty states that act — the rest of W7 shipped in 1.90
6. W6.1 on-device TalkBack pass, W1.4 conflict surface

**Could have / deferred to 2.1:**

8. W3.3 end-to-end encrypted sync
9. iOS
10. W6.5 vault health — land opportunistically

---

## 6. Sequence

Release numbers are indicative; the ordering is the argument.

| Release | Theme | Contents |
|---|---|---|
| ~~1.81~~ | *Shipped* | W5.1–W5.4 and W6.6 — see §13 |
| ~~1.82~~ | *Shipped* | W2.1–W2.4, retrieval — see §13 |
| ~~1.83~~ | *Shipped* | The octopus: new icon set and opening animation — see §13 |
| ~~1.84~~ | *Shipped* | Nex's own camera, the wordmark in the header — see §13 |
| ~~1.85~~ | *Shipped* | Foundation I: phase names fixed · W3.2 disclosure screen + ADR-033 · W4.3 harness · W6.4 nightly stress — see §13 |
| ~~1.86~~ | *Shipped* | Foundation II: W4.1 text surface · W4.5 tap rule · W6.2 goldens — see §13. W4.2 continues as files are touched |
| ~~1.87~~ | *Shipped* | Safety net: W1.6 backup to a chosen folder · W6.1 accessibility audit — see §13 |
| ~~1.88~~ | *Shipped* | Foundation III: W4.4 AI layer into its package · W4.2 screens and preferences split — see §13 |
| ~~1.89~~ | *Shipped* | Measured: W6.3 timeline budget · W3.4 local, opt-in measurements — see §13 |
| ~~1.90~~ | *Shipped* | The home screen: W7.1 sticky day · W7.2 density · W7.3 card opens into its note · W7.5 bulk selection · Recurring as a page · five palettes — see §13 |
| **1.91** | Empty states | W7.4 empty states that act |
| *later* | Continuity | W1.1 pairing · W1.2 background sync · W1.3 media sync · W1.4 conflict surface — the owner has put sync aside for now |
| *later* | The second device | W1.5 Windows un-paused, re-qualified, released |
| *later* | Trust | W3.1 encryption at rest, behind a proved migration |
| **2.0** | The release | Docs and vision rewritten · threads and citations synced across devices |

- **The invisible work is first on purpose.** Retrieval and the shared UI
  primitives are what the visible work is made of.
- **2.0 is a small release.** By the time it ships, almost everything is already
  in users' hands.

---

## 7. What 2.0 deliberately does not do

- **Collaboration, sharing, multi-user.** It would change what the product is.
- **Folders, nested tags, databases, templates.** Threads (§13) are the only
  concession, and they are post-capture and non-containing by design.
- **A web client.** A third rendering of every surface and a different security
  model.
- **A plugin API or scripting.** It would freeze internals that are still moving.
- **Hosted accounts for other people.** The moment Nex holds other people's
  notes, it needs a security programme, a privacy policy and an on-call rotation.

---

## 8. Exit criteria for 2.0

1. A note captured on Android appears on the desktop **within 60 seconds**, both
   devices idle and online, with no user action.
2. Concurrent edits on two devices converge, including tag union and deletion,
   in the conformance matrix extended to media.
3. p95 fused search **under 300 ms at 50,000 notes** on a mid-range Android
   device, asserted in CI.
4. Every AI request appears in the disclosure log; a user who never configured
   a provider has an empty one.
5. Uninstall-reinstall-restore returns database, media and settings, with
   encryption on, verified against a deliberately corrupted archive.
6. `make check` green; no file in `apps/client/lib` over 800 lines except
   generated l10n.
7. The vision document has principles for the intelligence layer and the tools
   with the same teeth as the capture ones, and the app obeys them.

---

## 9. Risks, named

| Risk | Why it is real | What reduces it |
|---|---|---|
| **The encryption migration loses someone's notes** | It rewrites the database in place on a device nobody can see | Ship last; verified backup first; restore test against a corrupted archive in CI |
| **Two platforms, one tester** | Every bug so far was found by the owner on a real phone | Un-pause the Windows CI job before writing Windows features |
| **Threads drift into an organisation system** | One product meeting away from folders | The kill criteria in §13, held on every change to them |
| **Background sync burns battery** | It always does, the first time | Explicit budget, measured on a device, conservative default |
| **The foundation work is skipped because it is invisible** | It always is | Scheduled first; every feature after it is cheaper |
| **Feature breadth keeps outrunning the foundation** | 1.60–1.80 added a vault, Recurring, icons and effects in quick succession | Each 1.8x release carries at least one W4/W6 item |

---

## 10. Questions the owner has to answer first

1. **What is Nex at 2.0** — a capture inbox with AI in it, or a thinking tool
   with an instant front door? (§2.1)
2. **Windows or iOS as the second device?** This document says Windows.
3. **Will Nex ever hold other people's notes** (a hosted service), or is
   self-host plus pairing the permanent shape? Decides W3.3 and §7.
4. **Is encryption at rest worth a migration risk to existing users?** Possibly
   "yes, new installs first".
5. ~~**Is any measurement acceptable**, even local, opt-in and never transmitted?~~
   Answered at 1.89: local and opt-in, yes — W3.4, ADR-036.

---

## 11. ایده‌های بازمانده

پیشنهادهای قابل بررسی، نه تصمیم یا تعهد انتشار. موارد انجام‌شده (جستجوهای
ذخیره‌شده، همهٔ موارد مرکز Recurring و جای «ابزارها» در نوار پایین) حذف
شده‌اند. عملیات گروهی و همهٔ ایده‌های ظاهر و تجربهٔ کاربری در ۱.۸۸ برنامه‌ریزی
شدند و به W7 رفتند؛ اسکن چندصفحه‌ای به تصمیم مالک کنار گذاشته شد.

### امکانات

1. **تاریخچهٔ تغییرات یادداشت:** دیدن نسخه‌های قبلی و بازگرداندن یک نسخه.
2. **پیوند دوطرفهٔ یادداشت‌ها:** دیدن یادداشت‌های مرتبط و مسیر رفت‌وبرگشت میان آن‌ها.
3. **بازی فکری DbsNex:** یک بازی فکری کوچک داخل برنامه.
4. **حالت عیب‌یابی:** بخشی که به‌طور پیش‌فرض خاموش است و اگر روشن شود، برنامه را
   پایش و کنترل می‌کند و گزارش می‌دهد.
5. **فلسفهٔ اختاپوس:** معرفی فلسفهٔ نشان اختاپوس («یک ذهن، هزار ارتباط») در برنامه.
6. **خاموش‌کردن خلاصهٔ هوشمند:** گزینه‌ای در تنظیمات برای خاموش‌کردن smart summary،
   برای کسانی که از مصرف زیاد توکن ناراضی‌اند.
7. **ثبت دورهٔ قاعدگی:** امکان ثبت و پیگیری قاعدگی بانوان.
8. **Nex شریکی:** اتصال دو Nex و همگام‌بودن بخش مشخصی از یادداشت‌ها با شریک.
9. **دستگیره‌های انتخاب متن:** حل مشکل برعکس‌بودن دستگیره‌های انتخاب متن.

---

## 12. ایده‌های خلاقانه (مستقل از نقشهٔ ۲.۰)

هر کدام باید با اصل «ثبت زیر سه ثانیه و بدون فیلد اجباری» سنجیده شود.

1. **این روز در گذشته:** در خلاصهٔ روزانه، یادداشتی از همین روز در سال‌ها یا
   ماه‌های قبل، فقط وقتی واقعاً چیزی هست؛ بدون هوش مصنوعی هم کار می‌کند.
2. **کپسول زمان:** یادداشتی که تا تاریخ انتخابی پنهان می‌ماند و همان روز با
   اعلان برمی‌گردد — نامه به خودِ آینده.
3. **ثبت هوشمند از کلیپ‌بورد:** با بازکردن اپ، اگر پیوند یا متنی تازه کپی شده،
   یک کپسول «ذخیره شود؟» پیشنهاد می‌شود؛ فقط روی دستگاه و قابل خاموش‌کردن.
4. **یادآوری مکانی:** «وقتی به خانه رسیدم یادم بینداز»؛ مکان فقط روی گوشی
   پردازش می‌شود و به هیچ سرویسی نمی‌رود.
5. **مرور هفتگی به شکل استوری:** چند کارت تمام‌صفحه از هفته — عکس‌ها، کارهای
   انجام‌شده، برچسب‌های پرتکرار — که با یک لمس ورق می‌خورند.
6. **کارت‌های مرور (یادگیری فاصله‌دار):** هر یادداشتی را می‌توان «برای مرور»
   علامت زد تا در فاصله‌های افزایشی دوباره نشان داده شود.
7. **ثبت با برچسب NFC یا QR:** برچسبی روی میز، ماشین یا یخچال که با نزدیک‌کردن
   گوشی مستقیم ثبت را با برچسب از پیش تعیین‌شده باز می‌کند.
8. **حالت نوشتن متمرکز:** ویرایشگر تمام‌صفحه با پیمایش ماشین‌تحریری، شمارش
   کلمه و بدون هیچ دکمهٔ دیگر؛ برای یادداشت‌های بلند.
9. **یادداشت دست‌نویس و طرح:** بوم سادهٔ قلم برای کشیدن یا نوشتن با دست، که
   با OCR روی دستگاه قابل جستجو می‌شود.
10. **ثبت از ساعت هوشمند (Wear OS):** یک لمس برای یادداشت صوتی که روی گوشی
    ذخیره و رونویسی می‌شود.

---

## 13. Done

Taken out of the plan above when they shipped. Each line is what a person can
now do; the commit history has the rest.

### In 1.91.1 — fixes from the owner's testing

- **The keyboard rule is narrowed (ADR-038).** Only the settings search
  swallows the touch that closes the keyboard; everywhere else touches work
  as before 1.91.0. Its bug — every touch unfocused — is gone with it.
- **The native editor is a texture layer.** Hybrid composition made every
  frame wait on Android's: the editor opened and scrolled with lag. Its
  fonts are read at startup.
- **The coloured wave is back**; the light-blue drop out of the + button
  is gone.

### In 1.91.0 — typing in two languages, and the keyboard

- **Each paragraph edits in its own direction (ADR-037).** Multi-line fields
  are `NexTextField`: Android's own `EditText` (first-strong direction per
  paragraph, system handles and menu, formatting added), Flutter's field
  elsewhere. Single-line fields state their direction; a rule test enforces
  both.
- **A touch outside the field only closes the keyboard (ADR-038).** The
  app-wide dismisser stops that touch in hit testing; the field, other
  fields, a field's dialog and controls marked `NexTypingAction` (Send,
  Save) still work with one touch.

### In 1.90.1 — fixes from the owner's testing

- **Backups on the phone.** The media store compared a resolved blob path
  with an unresolved root; Android reaches the app folder through a symlink,
  so every backup after the first and every folder copy failed with "Unsafe
  media blob". Both sides are resolved now; a failed folder copy shows the
  error's own wording.
- **Update download survives Back.** While an update downloads, Back on the
  home screen sends Nex to the background instead of finishing the Activity
  (and the engine the download runs in).
- **Polish.** No flash at the end of a card opening; recovery codes copy with
  a tap; pinch folds animate; Card size sits under Text & UI size; the
  Recurring editor no longer opens the keyboard and reads as one form;
  palettes reach text fields, switches and outlined buttons; the last of the
  assistant's multicoloured light is gone.

### In 1.90.0 — the home screen

- **W7.1 The day stays on screen.** Scrolled past the top, the day of the card
  passing under the filter row is named there (weekday and date), and follows
  the list. It hangs from the pinned filter row in a fixed-height slot, so
  changing it relays out nothing else — the W6.3 budget holds.
- **W7.2 Card size.** Settings → Appearance → Card size: compact, standard or
  easier to read. `NexCardDensity` in `packages/ui` sets the padding, the icon
  box and the preview lines; the timeline's fixed card height follows it.
- **W7.3 A card opens into its note.** Tapping a card grows the note's sheet out
  of the card's own outline while the card — icon, title, tag dots — holds still
  over it and fades as the note's content fades in. Closing, dragging and
  animations off in the system are the ordinary sheet.
- **W7.5 Several notes at once.** The owner's design, as written: Select heads
  every card's hold menu; taps pick and put back; none left ends it; the dock
  gives way to a bar with the count, tag, thread, pin, share, copy, delete (one
  Undo for all) and close. Back ends it too. Swipes rest while picking.
- **Recurring is a page.** It was a sheet. Now a page with what it is for, the
  overdue / today / next-7-days numbers (each one a filter), payments in the
  next 30 days, a list/calendar switch and grouped cards; the editor is a full
  page in sections.
- **Look.** Five new palettes (Isfahan turquoise, Saffron, Midnight, Deep sea,
  Graphite), each with its own surfaces and checked for contrast; a change of
  look opens out as a circle from the tap that asked for it; filled buttons in
  palettes draw their icon in their own colour again. The logotype is the app
  icon and the header wordmark is a little smaller.
- **Fixes.** Folder backup falls back to writing without a rename and says why
  it failed; settings search results stay above the keyboard; a new or removed
  profile photo shows at once; the assistant can set "remind me Saturday at 9"
  in one step; threads are off by default.

### In 1.89.0 — measured

- **W6.3 Timeline budget.** `apps/client/test/performance/timeline_budget_test.dart`
  seeds 5,000 notes and holds three things to a budget in its own CI job
  (`timeline-budget`, tag `budget`): opening the timeline, a steady 600-frame
  drag past the first window, and a capture reaching the top. Exact counts do
  the guarding — the first read is one 200-note window, at most 12 cards are
  built on the first frame and 20 stay alive while scrolling, and after the
  recap folds on the first scroll nothing already built rebuilds. CPU-time
  limits (open < 1 s, scroll p90 < 50 ms and p99 < 120 ms, a window-loading
  frame < 500 ms, capture to screen < 600 ms) sit about 2.5× above what they
  measured. A `setState` per scroll frame fails both kinds.
- **W3.4 Speed and reliability, on the phone.** Settings → About → Speed and
  reliability, off by default: cold start to the library and to the timeline,
  capture from opening to saved, search to the note opened, and sessions with
  a capture that ran without an error. One file beside the crash log; never
  sent or backed up; no content; switching off deletes it. The feedback sheet
  can attach it as text, shown before sending, unticked every time. ADR-036.

### In 1.88.0 — foundation III

- **W4.4 The AI layer lives in its package.** The cloud provider adapters, the
  assistant's actions and the record of what left the device moved from
  `apps/client/lib/platform` into `packages/ai` as `package:nex_ai/cloud.dart`,
  with their tests. The on-device runtime stays `package:nex_ai/nex_ai.dart`,
  imported only by the "ai" flavor's entry point. CI's deletion proof now
  removes the on-device runtime (library, plugin, entry point) and proves
  core, data, ui, the rest of `packages/ai` and the standard client still
  build; it also asserts core, data and ui never import `nex_ai`. ADR-035.
- **W4.2 The mega-screens split.** `TimelineModel`, a `ChangeNotifier`, owns
  what the timeline shows — notes, filters, paging, folded groups, recurring
  items, retiring spent reminders — and has its own test. The timeline, note
  detail, settings, chat, vault and recurring sheets keep their state and
  lifecycle in the original file; leaf widgets moved to part files and larger
  States' behaviour into private extensions by topic. `nex_preferences.dart`
  is one mixin per domain under `platform/preferences/`. Files over 800 lines
  in `apps/client/lib`: 11 → 5 (`timeline_screen.dart` 4,170 → 700,
  `nex_preferences.dart` 1,906 → 613).

### In 1.87.0 — safety net

- **W1.6 Automatic copy to a folder.** Settings → Data & backup: Android's
  folder picker (any SAF tree — the phone, Google Drive, Nextcloud,
  Syncthing), the grant kept across restarts. Once a day while Nex is open a
  complete backup is written there as `Nex-auto-<UTC time>.nexfull` (through
  a `.partial` renamed when whole); the newest three of Nex's own are kept and
  nothing else in the folder is touched. One recovery code, shown with the
  must-confirm dialog, kept in secure storage and shown again behind the app
  lock. Never the private vault. The folder and its code do not travel in
  backups. The screen says the notes in the file are not encrypted.
- **W6.1 Accessibility audit.** `apps/client/test/accessibility_audit_test.dart`
  runs Flutter's labelled-target, target-size and text-contrast guidelines over
  seven main screens in English/light and Persian/dark at 2× text. It found and
  this release fixes: a screen-wide nameless tap area on the timeline, a
  nameless 48px search pill around a 20px field, an invalid pinned filter row
  that broke the timeline at large text, and two overflows at large text.

### In 1.86.0 — foundation II

- **W4.5 One tap rule.** `NexTapGuard` / `NexTapGuarded` in `packages/ui`: a
  screen holds what is open and how to close it; a guarded control is inert
  while anything is open, so the first tap closes it and presses nothing.
  Opening a second thing closes the first. The timeline's swiped card and a
  card's hold menu both register with it; the swipe-only helper and the menu's
  own absorber are gone.
- **W4.1 One text surface.** `NexTextSurface` (formerly `NexBodyText`) decides
  direction, alignment, selection and the selection menu for the user's words,
  as a full-width block (a direction per line where lines disagree) or hugged
  (`.line` for single ellipsised lines). Checklist lines, link headlines, chat
  turns and the translation result moved onto it.
- **W6.2 Golden pictures.** 26 pictures in `apps/client/test/goldens/`: card,
  hold menu, capsule notice and detail sheet in LTR/RTL × light/dark, and the
  card in all five palettes, drawn with the app's own fonts.

### In 1.85.0 — foundation I

- **W3.2 What left this device.** Every request to an AI provider is recorded
  at the HTTP client every `CloudAIAdapter` uses, in both isolates: when, which
  provider, host only, purpose, content kind, size, and the notes or media it
  came from — never the content, path or key. Settings → Security reads and
  clears it; it is never uploaded and not in backups. ADR-033 records what may
  be sent.
- **W4.3 Test harness.** `NexTestHarness.create()` / `pumpNexApp()` in
  `apps/client/test/support/nex_harness.dart`; seventeen widget-test files moved
  onto it. The rest keep setups it does not model and move as they are touched.
- **W6.4 Nightly stress.** `.github/workflows/stress.yml`: the race-sensitive
  tests fifty times each and both suites shuffled, every night;
  `tools/stress_repeat.sh` names the failing run. The rule "a retry is never the
  fix" is in `06-development.md`.
- **Phase names.** `08-roadmap.md` says Phase 1–3 with a status each (ADR-034).

### In 1.84.0 — the camera

- **Nex's own camera.** Photo opens a panel over the timeline with the live
  view, a shutter, back and a ⋮ menu for switching camera and flash; it falls
  back to the phone's camera app when no camera opens.
- **The wordmark in the header,** painted from `docs/nex_logo_type.svg`.

### In 1.83.0 — the octopus

- **New identity.** The octopus mark is the app icon on Android (adaptive,
  themed and legacy), iOS and Windows, and the notification, Quick Settings
  tile and widget glyph are drawn from its own vector. The header mark is
  painted from the same paths, so it stays sharp at any size.
- **Opening animation.** Android's splash shows only the eyes; Flutter picks
  up on the same pixels and grows the octopus around them, pulls six scattered
  fragments into its arms, then brings in the wordmark and "One mind. A
  thousand connections." Reduced motion shows the final frame.
- **Icon switcher.** The five alternatives are the designer's set plus the
  previous mark, so nobody who chose an alternative loses their icon.
  `tools/generate_brand_assets.py` rebuilds all of it from `docs/`.

### In 1.82.0 — retrieval

Measured with `packages/data/test/retrieval_budget_test.dart` (50,000 notes,
1,536-dimension embeddings, a desktop-class CI runner).

- **W2.1 Vectors out of JSON.** Each vector is stored as unit-length float32
  plus an int8 copy with its scale; old JSON rows are re-encoded on open. The
  database isolate keeps the int8 copies in memory; past 4,000 notes a
  sign-bit pass picks the candidates first. At 10,000 notes a meaning search
  went from 5.2 s to 44 ms and the database from 295 MB to 80 MB. Results
  match scoring every vector exactly in small libraries; with the sign pass,
  recall of the true top 10 on clustered vectors stays at 95% or more.
- **W2.2 One ranked list.** Keyword matches ranked by BM25, meaning matches
  held to the same filters, fused by reciprocal rank with small recency,
  named-type and pinned nudges. Keyword results show at once and the fused
  list replaces them when the query's embedding arrives (cached per query);
  meaning-only results are marked "Found by meaning".
- **W2.3 A budget at real size.** Keyword p95 91 ms, meaning 66 ms, fused
  164 ms at 50,000 notes (limits 150/150/250 ms), in its own CI job. Getting
  there took an FTS5 prefix index for 1–3 characters (a short prefix while
  typing: 150 ms → under 40), skipping the notes join when a search has no
  filters, and loading result tags in one query.
- **W2.4 The assistant retrieves the same way.** Its own searches use the
  fused ranking, and every question brings the notes that best match it into
  the context, so answers — and their cited notes — come from the notes about
  the question, not only the most recent ones.
- *Not yet:* the phone budget (exit criterion 3) is measured on a runner, not
  a mid-range phone; the in-memory index costs about 1.6 KB per note at 1,536
  dimensions (≈ 80 MB at 50,000).

### In 1.81.0

- **W5.1 The assistant answers from your notes, and shows which.** An answer
  that used notes ends with them as chips that open them; an id that is not a
  real, undeleted note makes no chip. With "Stay in my notes" off, an answer
  from general knowledge says so under it. The context it cites from comes
  from the fused retriever since 1.82 (W2.4).
- **W5.2 Capture from anywhere.** A Quick Settings tile ("Nex capture") opens
  the capture sheet, behind the unlock on a locked phone; an opt-in silent
  notification (Settings → Capture) has Note, Voice and Photo buttons and
  returns after a reboot.
- **W5.3 Threads.** Named views over notes about the same thing (Library →
  Threads, a note's details, the hold menu). After a capture closes, a note
  that clearly continues a thread — shared significant words, or the same
  link site — is offered to it in one capsule; two clearly related loose notes
  can start one. No model is involved. *Not yet:* threads are local and not in
  export archives or sync.
- **W5.4 Recurring calendar and attachments.** A week or month calendar with
  how busy each day is; the next occurrence can be moved from it without
  moving the schedule. An item can carry receipt photos, linked notes and one
  vault card, which opens only through the vault's unlock and is never part
  of what the assistant or the brief reads.
- **W6.6 Settings search.** One field finds any row, including by what the
  page it opens contains; a switch found there works there.

### Threads — kill criteria

Threads stay only while all of these hold. Breaking any one means removing the
feature, not adjusting it.

1. **Never before the save.** No thread choice appears in any capture flow,
   and nothing about a thread can delay a capture.
2. **Never required.** No note has to be in a thread, and no screen asks for
   one.
3. **Never a container.** A note in a thread is still on the timeline, in
   search and under its tags; deleting a thread changes no note.
4. **Rarely offered, never twice.** At most one capsule per capture, only on a
   clear match, and a setting turns it off. If people turn it off more than
   they use it, the offer goes.
5. **No hierarchy.** No thread inside a thread, no ordering of threads by
   hand, no thread-only notes.

---

## Appendix — how the numbers in §1 were obtained

```bash
find apps/client/lib packages/*/lib -name '*.dart' -exec cat {} + | wc -l
find apps/client/lib packages/*/lib -name '*.dart' -not -path '*/l10n/*' -exec wc -l {} + | sort -rn | head
find apps/client/lib -name '*.dart' -not -path '*/l10n/*' -exec wc -l {} + | awk '$1>800 && $2!="total"' | wc -l
grep -rc 'setState(' apps/client/lib --include='*.dart' | awk -F: '{s+=$2} END {print s}'
for d in apps/client packages/ui packages/core packages/data packages/ai; do find $d/test -name '*_test.dart' | wc -l; done
grep -n 'if: false' .github/workflows/ci.yml        # the Windows and iOS jobs
make budget                                          # the 50,000-note retrieval p95s (W2.3)
grep -rc 'Semantics(\|semanticLabel\|tooltip:' apps/client/lib --include='*.dart' | awk -F: '{s+=$2} END {print s}'
```
