# Nex 2.6.19 — performance review and fixes

> Status: completed · Scope: whole-app performance review against `main`
> at `f960d05` (v2.6.18), with root-cause fixes shipped as v2.6.19.
> Toolchain: Flutter 3.47.9 / Dart 3.13.7 (the repo's own pin), pure-Dart
> test suites, micro-benchmarks and the tagged retrieval budgets.

## What was reviewed

The whole request path a phone actually runs: startup
(`main.dart` → `entry_bootstrap` → `bootstrap_host` → `NexServices.bootstrap`
→ the db worker's open-time repair), the timeline (list diffing, grouping,
cards, sticky headers, the smart summary header), capture (text, photo,
voice, file, link), search (FTS5 + the two-stage vector index + the
controller's debouncing), the note detail sheet, isolates and threading
(every heavy operation's isolate placement), and the data layer's SQL
against 300 / 3,000 / 20,000-note mixed libraries (text, checklists,
voice, photo, file, link; ~40% with attachments; ~70% tagged).

Benchmarks: best-of-N over the real repository and schema, on disk
(temp directories, `synchronous = NORMAL` under WAL — the shipped
configuration). The 50,000-note tagged budget suite
(`retrieval_budget_test.dart`) was run as-is.

## The findings that mattered

### PERF-01 — every note write scanned the whole search index

`notes_fts` stores the note id in an **UNINDEXED** column, so
`DELETE FROM notes_fts WHERE note_id = ?` cannot use the index: it reads
every indexed note to find the one being removed. That statement ran
inside the transaction of **every** write — capture, content edit, caption,
title, transcript/OCR arrival, tag change, soft delete, undelete,
attachment change, sync apply, import — making each write linear in the
library.

- Measured: 4.4 ms at 20,000 notes per write on a desktop-class core
  (0.6 ms at 3,000; 0.2 ms at 300) — a phone pays multiples of that, and
  it grows with the library: at 50,000 notes every capture carries tens
  of milliseconds of pure waste, inside the write transaction, on the
  isolate that also answers the timeline.
- Seeding rate collapsed accordingly: 700 notes/s at 3,000, 222 at 20,000.

**Fix:** key each search row by the note's own `notes.rowid`. FTS5 keeps a
B-tree on its rowid (the docid), so `DELETE … WHERE rowid = ?` is one
lookup. `NexDatabase._alignFtsRowids()` re-keys existing libraries once,
in one transaction, copying the index's own (already folded) content —
never recomputing note text: 187 ms for a 31,958-row index. A marker in
`nex_meta` makes it once-only; a second open measures 1 ms. Writers
(`_upsertFts`, `softDelete`, `applyRemoteNote`, `setCaption`, `_reindex`,
and the scheduled-note move) delete by the key; a note whose row is
already gone falls back to the label scan, unchanged.

- After: **capture 0.13 ms at 20,000 notes — 31× faster**, and flat
  across library sizes (0.18 / 0.13 / 0.13 ms at 300 / 3,000 / 20,000).
  Seed rate: 2,400 notes/s at 20,000.

### PERF-02 — the open-time repair re-read the whole index, per batch

`repairSearchIndex` runs at every worker boot, before the first request
is served. Its membership question —
`id NOT IN (SELECT note_id FROM notes_fts)` — re-derived every row's
label by scanning the FTS table, once per batch statement; its orphan
check joined every search row to its note by label and read the note in
full.

- Measured: 60 ms per batch at 20,000 notes (150 ms at 50,000), on every
  open, before the timeline can load.
- The versioned rebuild path (which a fresh library or a future
  `search_text_version` bump walks) reindexed every note through the old
  delete: 108 s at 20,000 notes.

**Fix:** both questions are now asked in docids. With the re-keying
above, a search row's rowid *is* its note's, so the membership subquery
reads the docid B-tree alone and the orphan check probes the notes'
B-tree per row; the `deleted_at IS NULL` arm of the orphan check keeps
the old meaning exactly (a soft-deleted note's search row goes with it).

- After: one batch 20 ms at 20,000; the healthy-open repair ≈ 25 ms
  (orphan scan + one batch) where it was ≈ 120 ms; the rebuild walk,
  where it ever applies, is 47× faster (2.3 s at 32,000 rows).

### PERF-03 — the tag filter row's counts read every tagged note in full

`tagUsage(timelineOnly: true)` — which the timeline model runs after
**every** stream delivery: every capture, edit, delete and scroll-page
append — LEFT-JOINs every `note_tags` row to its note through the notes
primary key, which reads the whole note row (content, transcripts and
all) to evaluate three flags. `hasUntaggedTimelineNotes` and the
set-aside release read the same columns the same way.

- Measured: 43 ms at 20,000 notes, per delivery, on the worker isolate —
  the work the next capture queues behind. `releaseDueSetAside`:
  2.6 ms; a tag-filtered timeline page: 11 ms.

**Fix:** `idx_notes_home (id, deleted_at, set_aside_at, set_aside_until)` —
a covering index for exactly those probes. The join plans now read
`SEARCH n USING COVERING INDEX idx_notes_home` and never touch the row.
Entries change only on writes that already maintain the table's other
indexes (a content edit leaves every indexed value untouched).

- After: 25 ms at 20,000 (the remaining cost is the per-`note_tags`
  covering probe — index-optimal for a whole-library count);
  `releaseDueSetAside` 0.7 ms; the tag-filtered page 4.6 ms.

### The guard that comes with the re-keying

`user_version` goes 2 → 3 **in the same transaction as the FTS re-key and migration marker**. This closes the crash window in which an older APK could see an upgraded search index under a stale schema stamp. An older APK (2.6.18) opening a re-keyed
library would write index rows keyed the old way, stranding rows the new
build can no longer address — so the older build now refuses the library,
which is exactly what the stamp exists for (DATA-06, the Cafe Bazaar /
Myket downgrade case). Existing libraries upgrade transparently; restores
and backups travel the new keying with them (`VACUUM INTO` copies rowids
as they are; restores replace the file whole, then migrate).

## Regression evidence

- `packages/core`: 278 tests — all passed (untouched; run to confirm).
- `packages/data`: 360 tests — all passed, including 10 new tests in
  `test/fts_rowid_alignment_test.dart` pinning the migration from a
  2.6.18-shaped library, the write paths under the new key, the repair's
  orphan/trash semantics, the scheduled-note move, and the downgrade
  stamp.
- `packages/ui`: 369 — all passed. `packages/ai`: 258 — all passed.
- `apps/client`: full suite (incl. FTS consistency, restore safety,
  version/whats-new gates) — all passed on the patched tree.
- Tagged 50,000-note retrieval budgets: standout p95 46.9 ms
  (budget 150), fused search p95 86.9 ms (budget 250) — pass, unchanged.
- `dart analyze --fatal-infos`: clean on core and data; the changed files
  are `dart format`-clean under the repo's pinned toolchain.

## What was reviewed and deliberately left alone

The timeline list (SliverAnimatedList with longest-increasing-subsequence
diffing, viewport-limited entrances, one repaint boundary per folding
row — the 761 ms trigger frame of F-04 is still guarded); the timeline
model's snapshot-equality suppression, window growth and trimming; the
search controller's 150 ms debounce, staged keyword→semantic delivery
and race guard; the two-stage vector index (nearest 3.4 ms, standout
4.4 ms over 50,000 in-memory vectors — measured); the note card's fixed
envelope, `cacheWidth`-sized image decodes and memoized long previews;
`compute`/`Isolate.run` on every CPU-heavy UI-side step (photo
encode/rotate, hashing, docx read, backup zip); the worker's serial
request chain with its background-command exception; the splash floor
racing bootstrap rather than gating it.

Measured and accepted, with reasons:

- bm25 ranking of a query that matches every note: 22–27 ms at 20,000 —
  the cost of ranking 20,000 real matches, within the 200 ms budget and
  far within the measured 50k budget suite.
- `nearestMiss` (the "did you mean" pass) 57 ms at 20,000 — runs only when
  a search found nothing, off the UI isolate.
- `tagUsage` remains one whole-library count per timeline delivery by
  design (the pills show library-wide counts); it is now index-covered
  and off-thread. Throttling it would trade freshness for little.

Not verifiable in this workspace (no device, no emulator): cold start to
first frame on a phone, Impeller raster-thread behaviour, memory with the
on-device model resident. The manual checklist below covers those.

## Manual verification checklist (real device)

1. **Upgrade path** — install 2.6.19 over a real 2.6.18 library (do not
   uninstall). First open migrates under the splash: notes, tags,
   reminders, vault, attachments and preferences intact. Search finds
   pre-upgrade notes by their words. Second open shows no repeat
   migration (no multi-second pause before the timeline).
2. **Downgrade guard** — attempt to open the migrated library with the
   2.6.18 APK: it must refuse with the library untouched, not write to it.
3. **Capture latency at size** — on a large library (5k+ notes), capture
   a text note, a photo, a voice note and a file; each should return to
   the timeline immediately, with the new card on top.
4. **Scroll** — with the mixed-media library, scroll deep (several page
   loads), fold/unfold date groups, filter by a tag and by Untagged, open
   and close details — no stutter, no duplicate cards.
5. **Search** — type a common word progressively; results narrow
   incrementally; a nonsense query offers at most one nearest-miss.
   Persian words with ZWNJ still match across spellings.
6. **Trash and undo** — delete a note (undo restores it findable), purge
   one from Recently Deleted (search must forget it), restore a backup
   taken before the purge in a safe test environment.
7. **Set aside** — set notes aside with and without a return time; the
   returning ones reappear on schedule.
8. **Scheduled notes** — schedule a note; its words leave search until
   released; after release they are findable again.
9. **Reminder flows** — one-off and recurring reminders fire, tap through
   after unlock, and a rung one-off retires when opened.
10. **Themes and motion** — Light/Dark/Night across the above, and once
    more with Android's Remove animations on.
