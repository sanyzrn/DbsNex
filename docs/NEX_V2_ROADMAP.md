# Nex 2.0 — Analysis and Roadmap

> **Status:** Proposal · **Written at:** v1.21.0 · **Decides nothing on its own.**
> Anything here that survives review becomes an ADR in
> [`10-decisions.md`](./10-decisions.md) and a row in
> [`08-roadmap.md`](./08-roadmap.md).

This is a design document, not a plan of record. It was written by reading the
code, the schema, the workflows and the docs — not by reading the roadmap and
restating it. Where it contradicts `08-roadmap.md`, the contradiction is the
point and is called out.

---

## 0. A naming collision, first

`08-roadmap.md` uses **v1 / v2 / v3** as *thematic phases*: v1 MVP, v2 Sync &
Continuity, v3 The Intelligence Layer. The release train uses **1.x** as
ordinary semantic versions and is at **1.21.0**.

Those two numbering systems have come apart. Measured against the phase plan,
the app at 1.21 has already shipped most of phase v3 — transcription, OCR, tag
suggestions, semantic search, summarisation, an assistant, a daily brief — while
phase v2's headline, *continuity across devices*, is the thing still missing.
The plan was executed out of order, and the order it was executed in is the
easier order.

So: **"2.0" in this document means the next major release of the app**, not
phase v2. The first thing to do with this document is fix the collision — either
renumber the phases in `08-roadmap.md` or stop using v-numbers for them.

---

## 1. Where Nex actually is

Measured at `5753ac0`, not estimated.

| | |
|---|---|
| Dart, total | ~63,000 lines |
| `apps/client` | ~47,700 lines, of which ~10,300 are generated l10n |
| Largest files | `timeline_screen.dart` 3,785 · `note_detail_sheet.dart` 2,675 · `ai_chat_sheet.dart` 2,079 · `ai_provider.dart` 1,915 · `note_repository.dart` 1,488 |
| `setState` call sites in the client | 187 |
| Tests | 75 client · 19 ui · 20 core · 22 data, plus backend and worker |
| Platforms actually shipping | Android only — the Windows and iOS CI jobs are `if: false` |
| Sync | implemented end to end, **manual only** |
| Encryption at rest | none |
| Telemetry | none, of any kind |

**What is genuinely strong**, and should be protected rather than rewritten:

- **The verification culture.** CI does not merely run tests: it deletes
  `packages/ai` and proves the app still builds; it analyses `core` and `data`
  with a Dart SDK that has no Flutter in it, so the absence of a Flutter
  dependency is proved by construction; it runs the TypeScript and Dart merge
  implementations against one shared conformance file; it runs a sync matrix
  against a live PostgreSQL. Very few projects this size have any of that.
- **The sync core.** Field-aware merge, union-merge for tags, tombstones, `rev`
  and `device_id` on every syncable table, and new tables (`commitments`,
  `memory_records`) deliberately shaped so they can join sync later without a
  schema redesign. The hard, invisible half is done.
- **Local-first for real.** SQLite + FTS5, a worker isolate, backup archives,
  export. The app is fully usable with no network and no account.
- **The comments.** The codebase explains its own reasoning to a degree that
  made this analysis possible in a few hours.

---

## 2. The critique

Six findings. They are ordered by how much they constrain the product, not by
how hard they are to fix.

### 2.1 Nex has quietly become two products, and only one of them has a spec

`01-product-vision.md` lists seven non-negotiable principles. All seven are
about capture and retrieval: under three seconds, no mandatory fields, timeline
as home, local-first, learnable in thirty seconds.

Nothing in them governs the assistant, the daily brief, commitments, the memory
store, translation or chat — which are now among the largest and most complex
surfaces in the app. `ai_chat_sheet.dart` alone is 2,079 lines, larger than the
entire `packages/core` model layer.

This is not an argument that the AI layer is wrong. It is an argument that it is
**ungoverned**: there is no principle it can be measured against, so it can only
grow. A 2.0 has to answer, in one sentence, what Nex is now. Two honest answers:

- *Nex is a capture inbox that happens to have AI in it* — then the AI surface
  should shrink and subordinate itself to capture and retrieval.
- *Nex is a thinking tool whose front door is instant capture* — then the vision
  document is out of date and needs principles for the intelligence layer with
  the same teeth the capture ones have.

**This document proposes the second, with a specific constraint** (§4.5). But
the decision is the owner's and everything else in §4 is cheaper once it is made.

### 2.2 Sync is built, but continuity is not

The engine works and is tested harder than most of the app. What a user touches
does not exist:

- **Configuration is a raw base URL and a bearer token** typed into a dialog
  (`settings_sheet.dart`). There is no account, no pairing, no discovery.
- **Sync never happens on its own.** It runs on pull-to-refresh and on a "Sync
  now" button. Close the app after capturing and the note stays on the device
  until you next pull the timeline.
- **Conflicts have no surface.** `sync_state` has a `'conflict'` value and the
  merge logic can produce it; no screen ever shows it.
- **There is no second device.** The Windows job is `if: false` and the iOS job
  is `if: false`. The thing sync exists for has nowhere to sync *to*.

So the architecture's biggest investment currently returns almost nothing to a
user. That is the clearest gap in the product and, by itself, would justify a
major version.

### 2.3 Retrieval will not scale, and there are three of it

`note_embeddings` stores each vector as `values_json TEXT`, and
`listEmbeddings()` selects **every row** and parses each vector by splitting a
string and calling `double.parse` per element. For 10,000 notes at 1,536
dimensions that is roughly 15 million `double.parse` calls per semantic search,
plus the garbage that comes with them. On a mid-range Android phone that is not
a sub-three-second search; on 50,000 notes it is not a search at all.

Separately, there are three retrieval paths that do not know about each other:
FTS5 over `content`/`transcript_text`/`ocr_text`; the embedding scan; and the
assistant, which builds its own context from its own query. They rank
separately and improve separately.

"Finding information feels instantaneous" is a non-negotiable principle. It is
currently protected by the fact that nobody has enough notes yet.

### 2.4 The client's architecture cannot absorb another feature

Three screens carry 8,500 lines between them, with 187 `setState` call sites and
no dependency injection. There is no state layer: `NoteSearchController` and
`UpdateService` are `ChangeNotifier`s, and everything else is widget state.

The cost is already being paid, and it is visible in the release history. The
bug waves of 1.17 → 1.21 — text direction, then per-line direction, then
selection handles, then the selection menu — were **four instances of one
missing abstraction**. There is no single place that owns "a piece of the user's
own text", so every surface re-derived direction, selection and menu behaviour
by hand, and each fix had to be applied N times and was forgotten at N+1. The
menu filter was written once in 1.5.5 and was silently wrong everywhere else for
sixteen minor versions, because it lived inside one screen.

This is the strongest argument in the document for spending a release on
foundations before features.

### 2.5 The data is not protected, and the app now sends it away

There is an app lock with biometrics, and a backup archive. There is **no
encryption at rest**: `nex.sqlite` and the media directory are plaintext on
disk. An app lock is a screen, not a safe.

Meanwhile, since 1.17 the assistant can read a focused note's file text and its
images, so that content leaves the device whenever a cloud provider is
configured. The privacy consequence of that change was raised at the time and
**no ADR was ever written**. For an app whose README says "your notes are
yours", the gap between the claim and the guarantee is the largest honesty debt
in the project.

### 2.6 The product's own success metrics are unmeasurable

`01-product-vision.md` commits to: median capture under 3 s, median
search-to-result under 3 s, search success rate above 90%, crash-free capture
sessions above 99.9%.

There is no telemetry of any kind, so none of these is measured. That is a
defensible privacy choice, but it means every performance claim in the docs is a
belief. A local-only, opt-in, user-readable instrument would cost little and
would turn four beliefs into four numbers.

---

## 3. What 2.0 should be

> **Nex 2.0: everything you capture, on every device you own, findable by
> meaning — and still yours.**

Three pillars, plus a foundation that makes them affordable.

| Pillar | One-line test of success |
|---|---|
| **Continuity** | Capture on the phone, walk to the desk, it is already there. |
| **Retrieval** | One ranked answer across text, meaning, time and type — at 50,000 notes. |
| **Trust** | The device is a safe, and the app can show you exactly what has left it. |
| *(Foundation)* | The next feature costs what it should, not what four screens make it cost. |

The version identity is deliberately **not** "more AI". The intelligence layer
is already the most developed part of the app; what it lacks is grounding, not
capability (§4.5).

---

## 4. Workstreams

Each is written as: the problem, the proposal, the cost, and what it must not
break.

### W1 — Continuity

**W1.1 Identity and pairing.** Replace "type a URL and a bearer token" with a
pairing flow: the desktop shows a QR code (or a six-word code), the phone scans
it, the server issues a per-device token. Self-hosting stays first-class — the
URL field moves behind *Advanced*, it does not disappear. No email, no password,
no account recovery in 2.0; a device pair is the identity.
*Cost:* a pairing endpoint, a short-lived pairing token, a QR scanner.
*Must not break:* the app has to stay fully usable with no pairing at all.

**W1.2 Sync that happens by itself.** Android `WorkManager`: periodic sync,
sync on connectivity regained, sync on app background, and a debounced push a
few seconds after a capture settles. The "Sync now" button stays for the
impatient. Status becomes a quiet indicator, never a modal.
*Cost:* moderate — the sync entry point already exists (`NexServices.syncNow`);
this is scheduling, backoff and battery behaviour.
*Must not break:* capture must not wait for sync, ever. Sync must not run on
metered connections unless allowed.

**W1.3 Media sync.** Content-addressed blob transfer keyed by the existing
`media_hash`, resumable and chunked, with lazy download — metadata and
thumbnails first, full media on open, with a per-device cache budget. This is
the piece that makes photo and voice notes actually portable.
*Cost:* the largest single item in W1. New server storage, new failure modes.
*Must not break:* a note whose media has not arrived yet must still open, and
must say so rather than look broken.

**W1.4 A conflict surface.** One screen: "this note changed in two places",
both versions, keep mine / keep theirs / keep both as two notes. Rare by design,
invisible today.
*Cost:* small. The data already exists.

**W1.5 The second device.** Recommendation: **un-pause Windows before starting
iOS.** The Windows target still builds, the job exists and is one `if: false`
away from running, and Android ⇄ Windows is the pairing `08-roadmap.md` already
promised. iOS is a genuinely larger programme — signing, store review, a
different media pipeline, a different background-execution model — and belongs
in 2.1.
*Cost:* Windows is mostly re-enabling and re-qualifying; iOS is a quarter.
*Must not break:* nothing on Android. Desktop is additive.

### W2 — Retrieval

**W2.1 Get vectors out of JSON.** Store embeddings as a `BLOB` of packed
`float32` instead of a JSON string, and add an `int8`-quantised copy for a first
pass. Search becomes: scan the quantised buffer (typed, no allocation, no
parsing), take the top ~200, re-rank those exactly against the float32 vectors.
*Why this and not a vector extension:* `sqlite-vec` or `sqlite-vss` would mean
bundling a native library per platform, which collides directly with the
packaging story and with `packages/data` being pure Dart. A two-stage
quantised scan is a few hundred lines, needs no native dependency, and should
be one to two orders of magnitude cheaper than the current path. **Measure
before committing** — if a benchmark says otherwise, take the native route with
open eyes.
*Cost:* moderate, plus a migration that re-encodes existing rows (embeddings
are derivable, so the fallback is a re-embed).

**W2.2 One ranked result, not three modes.** Fuse the FTS rank and the vector
similarity with reciprocal-rank fusion, then apply recency and type boosts.
The user types once and gets one list.
*Cost:* small once W2.1 lands. Mostly ranking design and tests.

**W2.3 A retrieval budget in CI.** Seed 50,000 synthetic notes, assert p95
query latency for keyword, semantic and fused search. The repo already has a
performance-budget habit; this extends it to the thing a non-negotiable
principle depends on.
*Cost:* small, high value. It is the only way the "under 3 seconds" promise
stops being folklore.

**W2.4 The assistant retrieves through the same path.** Today it assembles its
own context. Point it at the fused retriever so there is one ranking to improve
and one place where "what did Nex consider?" can be answered.
*Cost:* small. Mostly deletion.

### W3 — Trust

**W3.1 Encryption at rest.** SQLCipher for the database, and encrypt media files
with a key held in the Android Keystore, released by the existing app-lock flow.
*Cost:* real, and this is the **highest-risk item in the whole document**: it
requires migrating existing user databases in place, and the backup archive
format changes with it. It needs a migration that is provably reversible, tested
against a corrupted run, before it ships to anybody.
*Must not break:* backup and restore, export, and the worker isolate's access.

**W3.2 A "what left this device" screen.** A local audit log: which provider,
which note, what kind of content (text / file text / image), when. Written
whenever an AI request is made, readable and clearable by the user, never
uploaded. This also discharges the privacy ADR that has been open since 1.17 and
makes the disclosure concrete rather than a sentence in settings.
*Cost:* small. Highest ratio of trust gained to work done in this document.

**W3.3 End-to-end encryption for sync — partial, and honestly labelled.**
Encrypt `content` and media bytes with a key derived at pairing time and never
sent to the server; leave ids, `rev` and timestamps in the clear so field-level
merge still works. Say plainly in the UI that metadata is not encrypted, because
it is not.
*Cost:* high, and it forecloses any future server-side search.
*Recommendation:* design it in 2.0, ship it in 2.1, unless the owner intends to
run a hosted service for other people — in which case it moves up.

**W3.4 Local, opt-in metrics.** Time-to-stored-note, search-to-open, crash-free
capture sessions, kept on-device, shown to the user in Settings, exportable with
feedback. Never transmitted silently.
*Cost:* small. Turns four undefended claims into four numbers.

### W4 — Foundation (invisible, and first)

**W4.1 One text surface.** A single `NexTextSurface` layer in `packages/ui` that
owns, for every piece of the user's own text: direction (and the real
`Directionality`, not just the argument), selection on/off, the selection menu,
selection styling, and the per-line versus single-paragraph decision. Every
screen goes through it.
*Why:* this is the abstraction whose absence caused four consecutive bug waves
(§2.4). It is also **cheap** — most of the logic already exists, scattered.
*This is the highest-value item in the document per hour spent.*

**W4.2 Split the three mega-screens.** A view-model per screen —
`ChangeNotifier` is enough, matching what the codebase already uses; not a
framework migration. Target: no file in `apps/client/lib` over ~800 lines.
*Cost:* steady, boring, and it makes everything after it cheaper.

**W4.3 A real test harness.** `pumpNexApp()` that assembles the service graph
once, so tests stop hand-rolling it and new tests stop being expensive to write.

**W4.4 Resolve the `packages/ai` fiction.** CI proves the package is deletable,
but the AI code that matters — 1,915 lines of provider, wire formats,
embeddings, attachments — lives in `apps/client/lib/platform/ai_provider.dart`.
Either move the provider layer into `packages/ai`, where it can be tested
without booting the app and where the deletion proof would mean something, or
drop the package and the proof. **Recommendation: move it.**

### W5 — Product

**W5.1 Ground the assistant in the notes.** Make the assistant *answer from your
notes*, with citations, and make it say so when it is answering from the model's
general knowledge instead. Concretely: every answer carries the notes it used as
tappable chips; a toggle decides whether answering without any note is allowed
at all.
*Why:* it is the one thing a general chat app cannot do, it consumes the
retrieval work directly, and it gives the AI layer the principle it currently
lacks — *the assistant's job is your own material*. This is the governance
answer to §2.1.

**W5.2 Capture surfaces that cost nothing.** A Quick Settings tile and a
notification-shade capture action. Small, squarely on-identity, and they move
the number the vision document actually cares about.

**W5.3 Threads — the one new idea worth a major version.** Notes about the same
thing accrete without folders. After a capture is already saved, if the app
believes it continues something — same entity, same link, same day, high
retrieval similarity — it offers a single tap: *add to "kitchen renovation"*.
Never before the save, never a required field, always dismissible, and a thread
is a view rather than a container so a note can belong to several or none.
*Why it is not the folders the product exists to avoid:* it is post-capture,
suggested rather than imposed, and it is a lens over the timeline rather than a
place notes are moved into.
*Risk:* this is exactly the feature that could drift into an organisation system
and contradict the product's identity. It needs a prototype, a written kill
criterion, and the owner's judgement before any of it is built.

---

## 5. Priorities

**Must have for 2.0** — without these it is a 1.22, not a 2.0:

1. W4.1 one text surface, W4.3 test harness *(cheap, and everything else rides on them)*
2. W2.1 + W2.2 + W2.3 retrieval that scales and fuses
3. W1.1 + W1.2 identity and automatic sync
4. W1.5 a second device actually shipping *(Windows)*
5. W3.2 the disclosure screen, and the ADR that should have been written in 1.17
6. W5.1 the grounded assistant

**Should have:**

7. W1.3 media sync — without it, continuity is text-only
8. W3.1 encryption at rest — high value, highest risk; ship it only when the migration is proved
9. W4.2 screen decomposition — continuous, not a milestone
10. W3.4 local metrics
11. W1.4 conflict surface

**Could have / explicitly deferred to 2.1:**

12. W5.3 Threads — prototype in the 2.0 cycle, ship only on evidence
13. W3.3 end-to-end encrypted sync
14. iOS
15. W4.4 moving the AI layer into its package — worth doing, not worth blocking on
16. W5.2 quick-capture surfaces — cheap enough to land opportunistically

---

## 6. Sequence

Release numbers are indicative; the ordering is the argument.

| Release | Theme | Contents |
|---|---|---|
| **1.22** | Foundation | W4.1 text surface · W4.3 harness · W4.2 begins · W3.2 disclosure screen + the 1.17 ADR |
| **1.23** | Retrieval, invisible | W2.1 vectors out of JSON · W2.3 the 50k budget test in CI |
| **1.24** | Retrieval, visible | W2.2 fused ranking · W2.4 assistant on the same retriever |
| **1.25** | Continuity I | W1.1 pairing · W1.2 background sync · W1.4 conflict surface |
| **1.26** | Continuity II | W1.3 media sync · W3.4 local metrics |
| **1.27** | The second device | W1.5 Windows un-paused, re-qualified, released |
| **1.28** | Trust | W3.1 encryption at rest, behind a proved migration |
| **2.0** | The release | W5.1 grounded assistant · docs and vision rewritten · Threads only if the prototype earned it |

Two things about this order:

- **The invisible work is first on purpose.** Retrieval and the text surface are
  what the visible work is made of, and doing them after would mean doing the
  visible work twice.
- **2.0 is a small release.** By the time it ships, almost everything is already
  in users' hands. That is the intent: a major version should be the moment the
  story becomes true, not a big bang that risks everything at once.

---

## 7. What 2.0 deliberately does not do

- **Collaboration, sharing, multi-user.** `08-roadmap.md` rules it out
  indefinitely and it is right: it would change what the product is.
- **Folders, nested tags, databases, templates.** Same reason. Threads (W5.3) is
  the only concession, and it is post-capture and non-containing by design.
- **A web client.** It would mean a third rendering of every surface and a
  fundamentally different security model.
- **A plugin API or scripting.** Nothing has asked for it, and it would freeze
  internals that are still moving.
- **Hosted accounts for other people.** Self-hosting and device pairing keep the
  operational surface at zero. The moment Nex holds other people's notes, it
  needs a security programme, a privacy policy and an on-call rotation.

---

## 8. Exit criteria for 2.0

Numbers, so it can fail honestly:

1. A note captured on Android appears on the desktop **within 60 seconds** with
   both devices idle and online, with no user action on either.
2. Concurrent edits on two devices converge correctly, including tag union and
   deletion, in the existing conformance matrix, extended to media.
3. p95 fused search latency **under 300 ms at 50,000 notes** on a mid-range
   Android device, asserted in CI.
4. Every AI request appears in the disclosure log; the log is readable and
   clearable; a user who has never configured a provider has an empty one.
5. Uninstall-reinstall-restore returns database, media and settings, with
   encryption on, verified against a deliberately corrupted archive.
6. `make check` green; no file in `apps/client/lib` over 800 lines except
   generated l10n.
7. The vision document has principles for the intelligence layer with the same
   teeth as the capture ones, and the assistant obeys them.

---

## 9. Risks, named

| Risk | Why it is real | What reduces it |
|---|---|---|
| **The encryption migration loses someone's notes** | It rewrites the database in place on a device the developer cannot see | Ship last; forward-only migration with a verified backup taken first; a restore test against a corrupted archive in CI |
| **Two platforms, one tester** | Every bug in this project has been found by the owner on a real phone. Windows doubles that surface | Un-pause the Windows CI job *before* writing Windows features; treat its re-qualification as a release of its own |
| **The ANN work becomes a rabbit hole** | Vector search is a field with no natural stopping point | Benchmark first, set the budget (W2.3) before the implementation, and accept the quantised two-stage scan if it clears the budget |
| **Threads drifts into an organisation system** | It is one product meeting away from being folders | A written kill criterion before a line of code; if it needs a mandatory field or a pre-capture decision, it is dead |
| **Background sync burns battery** | It always does, the first time | Budget it explicitly; measure on a real device; default to conservative and let the user loosen it |
| **The foundation work is skipped because it is invisible** | It always is | It is scheduled first, and every feature after it is cheaper for it — that is the argument to hold |

---

## 10. Questions the owner has to answer first

Nothing below can be decided by reading the code.

1. **What is Nex at 2.0** — a capture inbox with AI in it, or a thinking tool
   with an instant front door? §2.1. Everything else is cheaper once this is
   answered.
2. **Windows or iOS as the second device?** This document says Windows, on
   evidence, but it is a market decision as much as a technical one.
3. **Will Nex ever hold other people's notes** (a hosted service), or is
   self-host plus device pairing the permanent shape? It decides whether W3.3
   moves up and how much of §7 stays true.
4. **Is encryption at rest worth a migration risk to existing users?** The
   answer might be "yes, but only for new installs first".
5. **Is any measurement acceptable at all**, even local and opt-in and never
   transmitted? If not, §2.6 stands permanently and the vision's metrics should
   be removed rather than left unmeasured.

---

## 11. ایده

این‌ها پیشنهادهای قابل بررسی‌اند، نه تصمیم یا تعهد انتشار. هر مورد باید با
اصول محصول و اولویت‌های بالا سنجیده شود.

### امکانات

1. **تاریخچهٔ تغییرات یادداشت:** دیدن نسخه‌های قبلی و بازگرداندن یک نسخه.
2. **مجموعه‌های هوشمند:** ذخیرهٔ جستجوها به‌صورت نماهای پویا، بدون انتقال یادداشت
   به پوشه یا افزودن مرحله به ثبت سریع.
3. **پیوند دوطرفهٔ یادداشت‌ها:** دیدن یادداشت‌های مرتبط و مسیر رفت‌وبرگشت میان آن‌ها.
4. **عملیات گروهی:** انتخاب چند یادداشت برای برچسب‌گذاری یا بایگانی یک‌جا.
5. **اسکن چندصفحه‌ای:** ثبت چند صفحهٔ سند در یک یادداشت، با امکان مرتب‌کردن صفحات.

### ظاهر و تجربهٔ کاربری

1. **انتقال پیوسته به جزئیات:** بازشدن کارت با حفظ جای تصویر و عنوان.
2. **تراکم قابل انتخاب فهرست:** دو حالت فشرده و خواناتر برای کارت‌ها.
3. **سرصفحهٔ چسبان روزها:** نمایش تاریخ روز هنگام پیمایش یادداشت‌های قدیمی.
4. **پیش‌نمایش زندهٔ ظاهر:** دیدن اثر تم و رنگ تأکیدی پیش از خروج از تنظیمات.
5. **راهنمای کاربردی صفحه‌های خالی:** میان‌بر ثبت اولین محتوای مرتبط به‌جای متن
   صرفاً توضیحی.

---

## Appendix — how the numbers in §1 were obtained

```bash
find apps/client/lib packages/*/lib -name '*.dart' -exec cat {} + | wc -l
find apps/client/lib -name '*.dart' -exec wc -l {} + | sort -rn | head
grep -rc 'setState(' apps/client/lib --include='*.dart' | awk -F: '{s+=$2} END {print s}'
grep -n 'if: false' .github/workflows/ci.yml        # the Windows and iOS jobs
grep -n 'values_json' packages/data/lib/repositories/note_repository.dart
```
