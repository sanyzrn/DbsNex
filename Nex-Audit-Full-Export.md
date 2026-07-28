# Nex — Technical Audit (Full Export)

**Repository:** [sanyzrn/DbsNex](https://github.com/sanyzrn/DbsNex)  
**Audit commit:** `main @ 426dab1` — 27 Jul 2026 · PR #48  
**Stack:** Flutter 3.35.5 client (Android · Windows · iOS compile-checked) · pure-Dart core/data/ai packages · Flutter ui package · Node 22 / Express 4 / PostgreSQL 16 backend · 11-job GitHub Actions pipeline

**Status:** 41 of 42 previous findings resolved, 1 carried over.

**Highlights since the previous audit:**

- Backend boots on its declared engine — engines ≥22.6, tsconfig on nodenext, an emitting build config, dist/ artifact and a Dockerfile.
- Full tenancy boundary landed: users/devices/pairing_codes tables, SHA-256 device bearer tokens, requireDevice on every data route, user_id on every query.
- Push is fully transactional with FOR UPDATE row locks; tag identity is (user_id, lower(name)); rev is server-authoritative.
- The timestamp watermark is gone — notes and tags carry BIGSERIAL seq columns and the cursor is DB-derived.
- localeCompare ordering replaced with epoch-millisecond comparison; a 12-case spec/merge-conformance corpus is run against both the TS and Dart implementations in CI.
- Device identity is a persisted UUID; all SQLite work runs on a worker isolate behind the NexDb interface; restore returns RestartRequired.
- File-based migration runner with schema_migrations + advisory lock; five numbered migrations.
- CI pins Flutter via .fvmrc, uses npm ci with caching, has concurrency control, timeouts, an iOS job, a real ai-deletion-proof, and a single ci-green required check.

---

## Table of Contents

- [Tab 1 — Current Issues & Improvements](#tab-1--current-issues--improvements)
- [Recurring Themes](#recurring-themes)
- [Tab 2 — World-Class Vision](#tab-2--world-class-vision-no-constraints)

---

## Tab 1 — Current Issues & Improvements

**Total open findings:** 27 — P0: 4, P1: 7, P2: 16

### NEX-01 — Pull cursor jumps past notes that were never sent — permanent, silent note loss

- **Priority:** P0
- **Category:** Data Integrity
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/sync-service.ts`
- **Effort:** S — 2 h + a regression test that pages with interleaved tag writes

**Summary**  
`pullChanges` pages the notes query with `LIMIT $4` but runs the tags query with no limit, then sets the returned cursor to the maximum `seq` across *both* result sets. When a tag's seq exceeds the last note's seq in a truncated page, the next pull starts above notes that were never delivered.

**Root cause**  
The cursor is a single scalar shared by two independently-scoped queries. Notes are bounded by `LIMIT env.SYNC_PAGE_SIZE` (default 500); tags are bounded by nothing. Both loops feed the same `cursor` variable, so the watermark tracks the furthest-advanced stream rather than the safe common floor. `has_more` correctly reports that the notes page was truncated, but the cursor handed back has already skipped the remainder.

**Impact**  
Concretely: 900 notes change, then one tag is touched (seq 1200). Page one returns notes seq 1–500, `has_more: true`, and `cursor: 1200`. The next pull asks for `seq > 1200`. Notes 501–900 are never returned to that device again, by any future sync. This is unrecoverable without a manual cursor reset, and nothing surfaces an error — the client simply never sees the notes.

**Fix**  
Bound the cursor by the notes page whenever it is truncated. Page the tags query too, and derive the cursor as the minimum of the two stream frontiers when either is incomplete.

**Before:**
```ts
const notesRes = await client.query(
  `... WHERE n.user_id = $1 AND n.seq > $2 ... LIMIT $4`,
  [input.user_id, sinceSeq, input.device_id, limit],
);
const tagsRes = await client.query(
  `SELECT ... FROM tags WHERE user_id = $1 AND seq > $2 ORDER BY seq ASC`,
  [input.user_id, sinceSeq],          // <-- no LIMIT
);

let cursor = sinceSeq;
for (const row of notesRes.rows) {
  if (BigInt(row.seq) > BigInt(cursor)) cursor = String(row.seq);
}
for (const row of tagsRes.rows) {     // <-- can outrun the notes page
  if (BigInt(row.seq) > BigInt(cursor)) cursor = String(row.seq);
}
return { notes, tags, cursor, has_more: notesRes.rowCount === limit };
```
**After:**
```ts
const notesRes = await client.query(/* ... */ `LIMIT $4`, [...]);
const tagsRes  = await client.query(
  `SELECT id, name, color, created_at, seq
     FROM tags
    WHERE user_id = $1 AND seq > $2
    ORDER BY seq ASC
    LIMIT $3`,
  [input.user_id, sinceSeq, limit],
);

const notesTruncated = notesRes.rowCount === limit;
const tagsTruncated  = tagsRes.rowCount === limit;

const lastSeq = (rows: { seq: string }[]) =>
  rows.length ? BigInt(rows[rows.length - 1]!.seq) : null;

const noteFrontier = lastSeq(notesRes.rows);
const tagFrontier  = lastSeq(tagsRes.rows);

// A truncated stream caps the cursor: never advance past a row we did
// not send. An exhausted stream imposes no cap.
const caps = [
  notesTruncated ? noteFrontier : null,
  tagsTruncated  ? tagFrontier  : null,
].filter((v): v is bigint => v !== null);

const reached = [noteFrontier, tagFrontier]
  .filter((v): v is bigint => v !== null);

let cursor = BigInt(sinceSeq);
if (reached.length) cursor = reached.reduce((a, b) => (a > b ? a : b));
if (caps.length)    cursor = caps.reduce((a, b) => (a < b ? a : b), cursor);

return {
  notes, tags,
  cursor: cursor.toString(),
  has_more: notesTruncated || tagsTruncated,
};
```

---

### NEX-02 — SyncClient reads a response field the server stopped sending — every sync is a full re-download

- **Priority:** P0
- **Category:** Protocol Drift
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`, `apps/backend/src/services/sync-service.ts`
- **Effort:** S — 3 h including cursor persistence in the repository

**Summary**  
`SyncClient` sets its watermark from `pullJson['server_time']`. `pullChanges` returns `{ notes, tags, cursor, has_more }` — there is no `server_time` key. The cast to `String?` yields null, so `since` is never sent and every pull restarts from seq 0.

**Root cause**  
The server migrated from a timestamp watermark to a BIGSERIAL cursor (migration `0004_sync_cursor.sql`) and renamed the field accordingly. The Dart client was never updated. Because the field is read with `as String?` rather than `as String`, the mismatch degrades silently instead of throwing.

**Impact**  
Incremental sync does not exist. Every sync cycle re-transmits the entire corpus that did not originate on the calling device, re-parses it, and re-applies every row through `applyRemoteNote`. On a 10k-note library that is a multi-megabyte response and thousands of local writes per sync — on mobile data, on battery. It also makes `has_more` unreachable in practice for small libraries, which is why nothing has noticed.

**Fix**  
Read `cursor`, persist it across process restarts, and fail loudly on a missing field rather than degrading to a full pull.

**Before:**
```dart
final pullJson = jsonDecode(pullRes.body) as Map<String, dynamic>;
_lastPullWatermark = pullJson['server_time'] as String?;   // always null
```
**After:**
```dart
final pullJson = jsonDecode(pullRes.body) as Map<String, dynamic>;

final cursor = pullJson['cursor'];
if (cursor is! String) {
  // A protocol change must not silently degrade into a full re-download.
  throw StateError('sync pull: server returned no cursor');
}
_lastPullWatermark = cursor;
// Survive process restart — an in-memory watermark restarts from zero on
// every cold launch even when the field name is right.
repo.setSyncCursor(cursor);
```

---

### NEX-03 — The outbox is cleared for notes the server explicitly refused

- **Priority:** P0
- **Category:** Data Integrity
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`, `apps/backend/src/services/sync-service.ts`
- **Effort:** M — 1 day, including a rejected-write case in the matrix

**Summary**  
`pushChanges` skips any note whose write was rejected as stale (`if (!written) continue;`) and omits it from `merged`. The client ignores the response entirely and calls `repo.markSynced(note.id)` for every note it sent.

**Root cause**  
`writeNote` guards the upsert with `WHERE notes.user_id = EXCLUDED.user_id AND notes.rev <= EXCLUDED.rev`. A device that edited offline while another device advanced the revision produces no returned row. The server communicates this by leaving the id out of `merged` — a signal the client never reads. The loop `for (final note in pendingNotes) repo.markSynced(note.id);` is unconditional.

**Impact**  
The exact scenario the outbox exists for — an offline edit that loses a race — is the one that silently discards the edit. The note is marked synced locally, never re-sent, and the local and server copies diverge permanently. The user sees their text on the device that wrote it and nowhere else, with no error and no retry.

**Fix**  
Mark synced only the ids the server acknowledged. Leave the rest pending so the next cycle re-pushes them after the pull has advanced the local revision.

**Before:**
```dart
final pushJson = jsonDecode(pushRes.body) as Map<String, dynamic>;

for (final note in pendingNotes) {
  // Tombstones must leave the outbox too once the server has them.
  repo.markSynced(note.id);
}
```
**After:**
```dart
final pushJson = jsonDecode(pushRes.body) as Map<String, dynamic>;

// The server returns [{id, rev}] for writes it actually accepted and omits
// anything it rejected as stale. Anything not in this set stays pending and
// is retried after the pull below advances the local revision.
final accepted = <String, int>{
  for (final entry in (pushJson['merged'] as List? ?? const []))
    (entry as Map)['id'] as String: entry['rev'] as int,
};

for (final note in pendingNotes) {
  final rev = accepted[note.id];
  if (rev == null) continue;                 // rejected — keep in outbox
  repo.markSynced(note.id, serverRev: rev);  // adopt the authoritative rev
}
```

---

### NEX-04 — `tag_remap` is returned by the server and discarded by the client

- **Priority:** P0
- **Category:** Protocol Drift
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`, `apps/backend/src/services/sync-service.ts`
- **Effort:** M — 1 day

**Summary**  
`upsertTag` conflicts on `(user_id, lower(name))` and returns the canonical id, which `pushChanges` collects into a `tag_remap: [{client_id, canonical_id}]` array. `SyncClient` never reads that key.

**Root cause**  
Migration `0005_tag_identity.sql` made the tag natural key authoritative precisely because two offline devices mint different UUIDs for the same tag name. The remap array is the mechanism by which a client learns its local id lost. Implementing the server half without the client half leaves the reconciliation permanently half-finished.

**Impact**  
Device B's local `#ideas` keeps its own UUID forever while the server has folded it into device A's. Every push re-sends the losing id, the server re-remaps it, and the response is thrown away again — an unbounded loop that never converges. Locally the user sees two `#ideas` tags with different note sets; note↔tag joins pulled from the server reference ids that do not exist in the local tag table.

**Fix**  
Apply the remap in one local transaction before the pull: repoint `note_tags`, delete the orphaned local tag, and keep the canonical row.

**Before:**
```dart
final pushJson = jsonDecode(pushRes.body) as Map<String, dynamic>;
// tag_remap never read
```
**After:**
```dart
final remap = (pushJson['tag_remap'] as List? ?? const [])
    .cast<Map<String, dynamic>>();

if (remap.isNotEmpty) {
  repo.applyTagRemap([
    for (final entry in remap)
      (
        clientId: entry['client_id'] as String,
        canonicalId: entry['canonical_id'] as String,
      ),
  ]);
}

// packages/data — SqliteNoteRepository
void applyTagRemap(List<({String clientId, String canonicalId})> pairs) {
  db.execute('BEGIN');
  try {
    for (final p in pairs) {
      if (p.clientId == p.canonicalId) continue;
      db.execute(
        'INSERT OR IGNORE INTO note_tags (note_id, tag_id) '
        'SELECT note_id, ? FROM note_tags WHERE tag_id = ?',
        [p.canonicalId, p.clientId],
      );
      db.execute('DELETE FROM note_tags WHERE tag_id = ?', [p.clientId]);
      db.execute('DELETE FROM tags WHERE id = ?', [p.clientId]);
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
```

---

### NEX-05 — `has_more` is ignored — a sync cycle stops after one page

- **Priority:** P1
- **Category:** Protocol Drift
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`
- **Effort:** S — 4 h

**Summary**  
The server paginates at `SYNC_PAGE_SIZE` (default 500) and reports `has_more`. `SyncClient.sync()` issues exactly one GET and returns.

**Root cause**  
Pagination was added server-side (correctly) without a corresponding drain loop on the client. The flag is present in the payload and simply not consulted.

**Impact**  
Any change set above 500 notes — first sync on an existing library, a restore, a bulk tag operation, a long offline period — leaves the device with a partial view until some later manual sync happens to catch up. Combined with NEX-02 the device restarts from zero each time, so with more than 500 changed notes it can never converge at all: it fetches the same first page forever.

**Fix**  
Drain pages until `has_more` is false, with a bounded page count as a circuit breaker.

**After:**
```dart
var guard = 0;
var pulled = 0;
while (true) {
  final uri = Uri.parse('$baseUrl/sync/pull').replace(queryParameters: {
    if (_lastPullWatermark != null) 'since': _lastPullWatermark!,
  });
  final res = await _http.get(uri, headers: _headers);
  if (res.statusCode >= 300) {
    throw StateError('sync pull failed: ${res.statusCode}');
  }

  final page = jsonDecode(res.body) as Map<String, dynamic>;
  _applyPage(page);
  pulled += (page['notes'] as List).length;

  final cursor = page['cursor'] as String;
  _lastPullWatermark = cursor;
  repo.setSyncCursor(cursor);

  if (page['has_more'] != true) break;
  if (++guard > 200) {
    // 200 pages x 500 = 100k rows. Past this something is wrong with the
    // cursor and looping forever is worse than stopping.
    throw StateError('sync pull: cursor failed to advance');
  }
}
```

---

### NEX-06 — Pull acknowledgement is written before delivery is confirmed — purge can resurrect deleted notes

- **Priority:** P1
- **Category:** Data Integrity
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/sync-service.ts`, `apps/backend/src/services/purge.ts`
- **Effort:** M — 1 day

**Summary**  
`pullChanges` advances `device_acks.last_pull_seq` on the server the moment the page is assembled — outside the read transaction and before the client has received, let alone persisted, the bytes. `purgeTombstones` then treats that as proof the device saw the deletes.

**Root cause**  
The ack is a server-side inference (`we sent it`) used as if it were a client-side fact (`they applied it`). The purge predicate `n.seq <= MIN(last_pull_seq)` is a distributed-systems safety gate, and it is being fed an at-most-once signal from a single unacknowledged HTTP response.

**Impact**  
Sequence: device B pulls, the ack advances, the response is lost to a dropped connection. B still holds the note locally with no tombstone. After `TOMBSTONE_RETENTION_DAYS` the purge deletes the row because every ack is past it. B's next push re-creates the note as new — a deletion the user performed silently undoes itself. This is the single worst-feeling bug class in a notes app.

**Fix**  
Make the ack client-driven: return the cursor, and let the client confirm the previous cursor on its next request. The server advances `last_pull_seq` only to a value the client has echoed back.

**Before:**
```ts
// pullChanges — fires as soon as the page is built, outside the txn
await getPool().query(
  `INSERT INTO device_acks (device_id, user_id, last_pull_at, last_pull_seq)
   VALUES ($1, $2, NOW(), $3)
   ON CONFLICT (device_id) DO UPDATE
      SET last_pull_at  = NOW(),
          last_pull_seq = GREATEST(device_acks.last_pull_seq,
                                   EXCLUDED.last_pull_seq)`,
  [input.device_id, input.user_id, page.cursor],
);
```
**After:**
```ts
// The cursor the client sends back is proof it persisted the previous page.
// Anything we merely transmitted is not acknowledged.
await getPool().query(
  `INSERT INTO device_acks (device_id, user_id, last_pull_at, last_pull_seq)
   VALUES ($1, $2, NOW(), $3)
   ON CONFLICT (device_id) DO UPDATE
      SET last_pull_at  = NOW(),
          last_pull_seq = GREATEST(device_acks.last_pull_seq,
                                   EXCLUDED.last_pull_seq)`,
  [input.device_id, input.user_id, sinceSeq],   // <-- the CONFIRMED cursor
);

// purge.ts — belt and braces: never reclaim a tombstone a device that has
// not been seen recently might still be missing.
`AND NOT EXISTS (
   SELECT 1 FROM device_acks d
    WHERE d.user_id = n.user_id
      AND (d.last_pull_seq < n.seq
           OR d.last_pull_at < NOW() - INTERVAL '90 days')
 )`
```

---

### NEX-07 — `NEX_TEST_MODE=1` is accepted in production and exposes a corpus-wipe endpoint

- **Priority:** P1
- **Category:** Security
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/env.ts`, `apps/backend/src/routes/sync.ts`
- **Effort:** XS — 45 min

**Summary**  
`POST /sync/test/reset` deletes every note, tag and media row for the authenticated user. Its only guard is `if (!env.isTestMode) throw new NotFound()`. Nothing prevents `NEX_TEST_MODE=1` from being set alongside `NODE_ENV=production`.

**Root cause**  
The env schema validates each variable in isolation. There is no cross-field refinement asserting that a destructive test affordance and a production deployment are mutually exclusive — and the flag is a plain string in a `.env` file, exactly the kind of value that gets copied between environments.

**Impact**  
One stray environment variable turns an authenticated endpoint into a total data-loss button for whoever calls it. There is no confirmation, no soft delete, no audit trail, and the deletes are not even transactional. Given the product positioning — 'the inbox for your mind' — this is the highest-consequence single line of configuration in the repository.

**Fix**  
Refuse the combination at boot, and make the route physically absent rather than 404-guarded in production builds.

**After:**
```ts
// env.ts
const schema = z.object({ /* ... existing fields ... */ })
  .refine(
    (v) => !(v.NODE_ENV === "production" && v.NEX_TEST_MODE === "1"),
    {
      path: ["NEX_TEST_MODE"],
      message:
        "NEX_TEST_MODE=1 exposes POST /sync/test/reset, which permanently " +
        "deletes the caller's entire library. It must never be set in " +
        "production.",
    },
  );

// index.ts — do not mount the router at all outside test mode
if (env.isTestMode) {
  const { testRouter } = await import("./routes/test.ts");
  app.use("/sync/test", express.json({ limit: "4kb" }),
          requireDevice, testRouter);
}
```

---

### NEX-08 — Downloaded update artifacts are executed with no integrity verification

- **Priority:** P1
- **Category:** Security
- **Area:** Flutter Client
- **Files:** `apps/client/lib/platform/app_update.dart`, `apps/client/lib/screens/update_sheet.dart`, `.github/workflows/release.yml`
- **Effort:** M — 1-2 days including the signing key and workflow change

**Summary**  
`UpdateDownloader` streams a release asset to the cache directory and `UpdateSheet` hands it to `OpenFilex.open`. The only check is `received == total` — a length comparison, not an integrity check. No checksum, no signature, no pinning.

**Root cause**  
The updater trusts TLS to `api.github.com` and `objects.githubusercontent.com` as its entire trust chain. That is a transport guarantee, not a provenance guarantee: it says the bytes arrived unmodified from whoever answered, not that they are the bytes the maintainer built. The release workflow publishes no checksum manifest for the updater to verify against.

**Impact**  
On Android the blast radius is bounded — the package manager refuses an update signed with a different key, so a substituted APK fails to install rather than executing. On **Windows there is no such check**: `Nex-x.y.z.exe` is opened directly, so a compromised release asset, a hijacked GitHub account, or a device with an attacker-controlled trust store yields arbitrary code execution as the user. A note-taking app that reads the user's entire private corpus is a high-value target for exactly this.

**Fix**  
Publish a signed `SHA256SUMS` in the release, verify the digest before opening, and on Windows additionally verify the Authenticode signature.

**After:**
```dart
# release.yml — publish a manifest alongside the artifacts
- name: Checksum manifest
  run: |
    cd dist && sha256sum Nex-* > SHA256SUMS
    # Sign it so a swapped manifest is as detectable as a swapped binary.
    gpg --batch --yes --armor --detach-sign \
        --local-user "$GPG_KEY_ID" SHA256SUMS

// app_update.dart
import 'package:crypto/crypto.dart';

Future<File> download({
  required String url,
  required Directory into,
  required String filename,
  required String expectedSha256,        // now required
  void Function(double?)? onProgress,
}) async {
  // ... stream to `partial` as today ...

  final digest = await partial
      .openRead()
      .transform(sha256)
      .first;

  if (digest.toString() != expectedSha256.toLowerCase()) {
    await partial.delete();
    throw const UpdateIntegrityError(
      'The downloaded installer does not match the published checksum. '
      'It was not opened.',
    );
  }
  await partial.rename(target.path);
  return target;
}
```

---

### NEX-09 — Push response field renamed server-side; client reads the old key

- **Priority:** P1
- **Category:** Protocol Drift
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`, `apps/backend/src/services/sync-service.ts`
- **Effort:** S — 3 h (fold into NEX-03)

**Summary**  
`pushChanges` returns `merged: [{ id, rev }]`. `SyncClient` reads `pushJson['merged_ids']` and defaults to an empty list, so `SyncResult.mergedIds` is always empty.

**Root cause**  
Same class of drift as NEX-02: the server response shape changed when `rev` became server-authoritative, and every read on the Dart side is written defensively (`as List?` with a `?? const []` fallback), which converts a contract break into a silently empty value.

**Impact**  
Any UI or diagnostic that reports 'n notes merged by the server' shows zero. More importantly it is the same missing signal that NEX-03 depends on — fixing NEX-03 requires reading this field correctly, so the two must land together.

**Fix**  
Read `merged`, and make the whole response a typed model so a rename is a compile error rather than an empty list.

**Before:**
```dart
mergedIds: ((pushJson['merged_ids'] as List?) ?? const []).cast<String>(),
```
**After:**
```dart
// A typed decode surfaces drift at the boundary instead of absorbing it.
final push = PushResponse.fromJson(pushJson);
// ...
mergedIds: push.merged.map((m) => m.id).toList(),

class PushResponse {
  const PushResponse({
    required this.merged,
    required this.mediaDeduped,
    required this.tagRemap,
    required this.cursor,
  });

  factory PushResponse.fromJson(Map<String, dynamic> json) {
    final merged = json['merged'];
    if (merged is! List) {
      throw StateError('sync push: missing "merged" in response');
    }
    return PushResponse(
      merged: [
        for (final m in merged.cast<Map<String, dynamic>>())
          (id: m['id'] as String, rev: m['rev'] as int),
      ],
      mediaDeduped: (json['media_deduped'] as List).cast<String>(),
      tagRemap: (json['tag_remap'] as List).cast<Map<String, dynamic>>(),
      cursor: json['cursor'] as String,
    );
  }

  final List<({String id, int rev})> merged;
  final List<String> mediaDeduped;
  final List<Map<String, dynamic>> tagRemap;
  final String cursor;
}
```

---

### NEX-10 — The sync matrix passes because incremental sync is broken, not despite it

- **Priority:** P1
- **Category:** Test Coverage
- **Area:** CI / Tooling
- **Files:** `packages/data/test/sync_matrix_test.dart`, `.github/workflows/ci.yml`
- **Effort:** M — 1-2 days

**Summary**  
The six-row matrix is the repository's flagship correctness gate. It cannot fail on NEX-02, NEX-03, NEX-04, NEX-05 or NEX-09 — every one of those defects is invisible to it by construction.

**Root cause**  
Each `_Device` builds a fresh `NexDatabase.openInMemory()` and a fresh `SyncClient` per test, and every assertion is a convergence check (`aIds == bIds`). A full re-download from seq 0 satisfies convergence trivially, so the broken watermark makes the tests *more* likely to pass. Test 6 uses 12 notes against a 500-row page size, so pagination never triggers. Tags are created with `upsertTag` on device A and pulled into B, so the two sides never mint competing UUIDs for the same name and the remap path never fires. `mergedIds` is never asserted.

**Impact**  
Nine CI jobs and a `ci-green` required check give a strong impression of coverage, and the one job that exercises the actual product feature validates the state the feature is in rather than the state it should be in. Four of this audit's P0/P1 findings sit inside its declared scope.

**Fix**  
Add cases that can only pass when the incremental path works: assert the request actually carries `since`, force pagination, and mint the same tag name independently on both devices.

**After:**
```dart
test('pull is incremental: the second cycle sends a cursor', () async {
  final a = _Device(id: 'device-a', ...);
  a.captureText('one');
  await a.sync();

  // Capture the wire, not just the outcome: convergence is satisfied by a
  // full re-download, so only the request proves incrementality.
  final requests = <Uri>[];
  a.client = SyncClient(/* ... */, httpClient: _Recording(requests));

  a.captureText('two');
  await a.sync();

  final pull = requests.lastWhere((u) => u.path.endsWith('/sync/pull'));
  expect(pull.queryParameters['since'], isNotNull);
  expect(int.parse(pull.queryParameters['since']!), greaterThan(0));
});

test('a change set larger than one page drains completely', () async {
  // SYNC_PAGE_SIZE is 500; 1200 forces three pages.
  for (var i = 0; i < 1200; i++) b.captureText('bulk-$i');
  await b.sync();
  await a.sync();
  expect(a.repo.listTimeline().length, 1200 + /* pre-existing */ 0);
});

test('the same tag name minted on both devices converges to one id', () async {
  final note = a.captureText('shared');
  await a.sync(); await b.sync();

  a.repo.attachTag(noteId: note.id, tagId: a.repo.upsertTag(name: 'ideas').id);
  b.repo.attachTag(noteId: note.id, tagId: b.repo.upsertTag(name: 'ideas').id);
  await a.sync(); await b.sync(); await a.sync();

  expect(a.repo.listTags().where((t) => t.name == 'ideas'), hasLength(1));
  expect(b.repo.listTags().where((t) => t.name == 'ideas'), hasLength(1));
  expect(
    a.repo.listTags().firstWhere((t) => t.name == 'ideas').id,
    b.repo.listTags().firstWhere((t) => t.name == 'ideas').id,
    reason: 'tag_remap must converge both devices on the canonical id',
  );
});
```

---

### NEX-11 — No `trust proxy` — auth rate limiting collapses into a single global bucket

- **Priority:** P1
- **Category:** Security
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/index.ts`
- **Effort:** S — 2 h

**Summary**  
`authLimiter` has no `keyGenerator`, so express-rate-limit keys on `req.ip`. `app.set('trust proxy', ...)` is never called, so behind any reverse proxy or load balancer `req.ip` is the proxy's address for every request.

**Root cause**  
The Dockerfile and the readiness/liveness split both assume a deployment behind an ingress. Express defaults `trust proxy` to false, which is the safe default for a directly-exposed server and the wrong one here. express-rate-limit v7 detects the mismatch and emits `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`, but only as a warning.

**Impact**  
All pairing traffic from every user shares one 10-requests-per-minute bucket, so a single client retrying a failed pair locks out everyone else's device pairing — a trivial, unauthenticated denial of service. The same fallback (`req.ip ?? 'unknown'`) is the pre-auth key for the sync and read limiters. It also means every access log and error log records the proxy IP, so abuse cannot be attributed.

**Fix**  
Declare the proxy topology explicitly, key the auth limiter on the submitted code prefix as well as the IP, and let the limiter validate the configuration.

**After:**
```ts
// index.ts — one hop: the ingress in front of the container.
// Never `true`: that trusts a client-supplied X-Forwarded-For outright.
app.set("trust proxy", env.TRUST_PROXY_HOPS);

const authLimiter = rateLimit({
  windowMs: 60_000,
  limit: 10,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  validate: { trustProxy: true, xForwardedForHeader: true },
  keyGenerator: (req) => ipKeyGenerator(req.ip ?? "unknown"),
});

// env.ts
TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(0),
```

---

### NEX-12 — Every authenticated request issues an unbatched `UPDATE devices SET last_seen_at`

- **Priority:** P2
- **Category:** Performance
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/middleware/auth.ts`
- **Effort:** XS — 30 min

**Summary**  
`requireDevice` fires a fire-and-forget row update on the `devices` table for every request that passes authentication.

**Root cause**  
Liveness bookkeeping was implemented as a synchronous side effect of authentication rather than as sampled or deferred telemetry. It is correctly non-blocking, but it is still a write.

**Impact**  
Doubles the query count on every endpoint and turns a read-only pull into a write transaction against a hot, narrow table — WAL growth, index churn and autovacuum pressure proportional to total request volume rather than to anything a user did. At the configured 60 sync + 120 read requests per minute per device this is up to 180 row updates per minute per device, all writing a value nothing reads in real time.

**Fix**  
Throttle to at most one write per device per interval, using the value already in the row.

**After:**
```ts
// Only write when the stored value is actually stale. One statement, no
// read-modify-write, and the vast majority of requests match zero rows.
void getPool()
  .query(
    `UPDATE devices
        SET last_seen_at = NOW()
      WHERE device_id = $1
        AND (last_seen_at IS NULL
             OR last_seen_at < NOW() - INTERVAL '5 minutes')`,
    [row.device_id],
  )
  .catch(() => undefined);
```

---

### NEX-13 — Connection pool of 10 with long REPEATABLE READ transactions and no statement timeouts

- **Priority:** P2
- **Category:** Scalability
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/db/index.ts`, `apps/backend/src/services/sync-service.ts`
- **Effort:** S — 3 h; batching the push loop is a further 1 day

**Summary**  
`getPool()` caps at 10 connections. `pullChanges` holds one inside a REPEATABLE READ transaction for the duration of a 500-row join plus an unbounded tags query; `pushChanges` holds one across up to 500 sequential round trips with row locks. No `statement_timeout` or `idle_in_transaction_session_timeout` is set.

**Root cause**  
The pool was sized for the original stateless request pattern. The transactional rewrite (correct in itself) turned short checkouts into long ones without revisiting the ceiling or adding the server-side guards that bound them.

**Impact**  
Eleven concurrent syncing devices exhaust the pool; the twelfth waits and fails at `connectionTimeoutMillis: 5000` with a 500. A push of 500 notes issues roughly 1,500 sequential statements while holding `FOR UPDATE` locks — one slow client blocks writes to those rows for every other device on the account. Without `idle_in_transaction_session_timeout`, a client that disconnects mid-transaction pins a connection and its locks until TCP keepalive notices, which can be minutes.

**Fix**  
Raise and configure the pool from env, set both timeouts at connection level, and batch the push loop.

**After:**
```ts
pool ??= new pg.Pool({
  connectionString: env.DATABASE_URL,
  max: env.PG_POOL_MAX,                 // default 20, tuned per replica
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  // Bound every statement and every transaction server-side, so a hung
  // client cannot hold a connection or a row lock indefinitely.
  options: [
    "-c statement_timeout=15000",
    "-c idle_in_transaction_session_timeout=30000",
    "-c lock_timeout=5000",
  ].join(" "),
});
```

---

### NEX-14 — Purge is a single unbounded global DELETE with a correlated subquery

- **Priority:** P2
- **Category:** Scalability
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/purge.ts`
- **Effort:** M — 1 day

**Summary**  
`purgeTombstones` runs two unbatched DELETEs across every user on an interval. The media DELETE has no user or time filter at all and re-evaluates a `NOT EXISTS` correlated subquery over the whole `notes` table.

**Root cause**  
The purge was written as a correctness mechanism (reclaim tombstones) without an operational envelope. There is no `LIMIT`, no per-user chunking, no jitter, and no leader election — every replica runs the same full-table sweep on the same schedule.

**Impact**  
At scale the hourly sweep is a long-running write transaction competing with live sync traffic for locks on the two hottest tables. With multiple replicas they collide. A revoked device's `device_acks` row is never removed, so its frozen `last_pull_seq` permanently pins `MIN(last_pull_seq)` and the notes purge silently stops reclaiming anything — the privacy guarantee quietly lapses with no signal.

**Fix**  
Chunk with `LIMIT`, exclude revoked devices from the ack floor, take an advisory lock so one replica runs, and emit a metric.

**After:**
```sql
-- Only devices that can still pull should hold the floor.
DELETE FROM device_acks a
 WHERE EXISTS (SELECT 1 FROM devices d
                WHERE d.device_id = a.device_id
                  AND d.revoked_at IS NOT NULL);

-- Chunked, so no single statement holds locks for long.
DELETE FROM notes
 WHERE id IN (
   SELECT n.id FROM notes n
    WHERE n.deleted_at IS NOT NULL
      AND n.deleted_at < NOW() - ($1 || ' days')::interval
      AND n.seq <= COALESCE(
            (SELECT MIN(last_pull_seq) FROM device_acks
              WHERE user_id = n.user_id), 0)
    LIMIT 1000
 );

// purge.ts — one replica at a time, with jitter
const LOCK = 5_512_004_991_233n;
const { rows } = await pool.query(
  "SELECT pg_try_advisory_lock($1) AS acquired", [LOCK.toString()]);
if (!rows[0]?.acquired) return { notes: 0, media: 0, skipped: true };
try { /* chunked loop until a pass deletes < 1000 */ }
finally { await pool.query("SELECT pg_advisory_unlock($1)", [LOCK.toString()]); }
```

---

### NEX-15 — Device tokens never expire, never rotate, and carry no scope

- **Priority:** P2
- **Category:** Security
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/routes/auth.ts`, `apps/backend/src/middleware/auth.ts`, `apps/backend/src/db/migrations/0003_tenancy.sql`
- **Effort:** M — 1-2 days including the client-side settings UI

**Summary**  
`POST /auth/pair` mints a 256-bit bearer token with no expiry column, no refresh mechanism, and no scope. The only revocation path is `POST /auth/revoke`, which the compromised device itself must call.

**Root cause**  
The pairing flow was designed for the boundary problem (is this caller anyone at all?) and stopped there. `devices` has `revoked_at` but no `expires_at` and no `rotated_at`; there is no endpoint to list or revoke *another* device.

**Impact**  
A token exfiltrated from a lost, sold or backed-up phone grants permanent full read/write access to the entire account with no way for the user to cut it off — they cannot even see that the device exists. There is also no `pairing_codes` cleanup, so consumed and expired codes accumulate forever. `safeEqualHex` is exported and unused: the actual comparison is a plain SQL equality on an indexed column, so the constant-time helper is dead code that implies a protection that is not in place.

**Fix**  
Add expiry and rotation, a device list, and remote revocation. Delete the unused helper.

**After:**
```sql
-- 0006_token_lifecycle.sql
ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rotated_at TIMESTAMPTZ;

UPDATE devices SET expires_at = NOW() + INTERVAL '180 days'
 WHERE expires_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pairing_codes_sweep
  ON pairing_codes (expires_at) WHERE consumed_at IS NULL;

-- middleware/auth.ts
`SELECT device_id, user_id FROM devices
  WHERE token_hash = $1
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > NOW())`

// routes/auth.ts
authRouter.get("/devices", requireDevice, ...);        // list, with last_seen
authRouter.post("/devices/:id/revoke", requireDevice, ...); // revoke another
authRouter.post("/rotate", requireDevice, ...);        // new token, old dies
```

---

### NEX-16 — Rate limiting is per-process memory — ineffective on more than one replica

- **Priority:** P2
- **Category:** Scalability
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/index.ts`, `apps/backend/Dockerfile`
- **Effort:** S — 4 h (plus provisioning Redis)

**Summary**  
All three limiters use express-rate-limit's default in-memory store while the Dockerfile and health-probe split are built for horizontal scaling.

**Root cause**  
The limiters were added to close a specific gap (unbounded unauthenticated writes) in a single-process context, and the store was never revisited when containerisation landed.

**Impact**  
The effective limit is `configured × replica count`, and it resets on every deploy, restart and autoscale event. The `/auth` limit — the one guarding pairing-code redemption — is the weakest as a result. It also means limits behave differently in staging (one replica) than in production, so the configuration is never actually validated.

**Fix**  
Move to a shared store, or enforce at the ingress if one is available.

**After:**
```ts
import { RedisStore } from "rate-limit-redis";
import { createClient } from "redis";

const redis = createClient({ url: env.REDIS_URL });
await redis.connect();

const shared = (prefix: string) =>
  new RedisStore({
    prefix,
    sendCommand: (...args: string[]) => redis.sendCommand(args),
  });

const authLimiter = rateLimit({
  windowMs: 60_000,
  limit: 10,
  store: shared("rl:auth:"),
  // ...
});
```

---

### NEX-17 — Health endpoints are unauthenticated, unthrottled, and hit the database

- **Priority:** P2
- **Category:** Security
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/index.ts`
- **Effort:** S — 2 h

**Summary**  
`/health` and `/health/ready` both call `pingDatabase()`, which issues `SELECT 1`. Both are mounted before every limiter and before any auth.

**Root cause**  
Readiness correctly reflects database reachability (that was a deliberate fix), but the endpoint that does so is public and free to call. `/health` also exists purely as a back-compat alias for the CI job and duplicates the readiness body verbatim.

**Impact**  
Any unauthenticated caller can drive one database round trip per request with no ceiling, checking out a pooled connection each time — a cheap way to exhaust the 10-connection pool (NEX-13) from outside. The response also discloses service name, phase and live database state to anonymous callers.

**Fix**  
Cache the probe result briefly, restrict the detailed body, and rate-limit the public surface.

**After:**
```ts
let probe: { at: number; state: "up" | "down" } | null = null;

async function cachedPing(): Promise<"up" | "down"> {
  // A readiness probe every 10s does not need a query every request.
  if (probe && Date.now() - probe.at < 2_000) return probe.state;
  const state = await pingDatabase();
  probe = { at: Date.now(), state };
  return state;
}

const probeLimiter = rateLimit({ windowMs: 60_000, limit: 120 });

app.get("/health/live", (_req, res) =>
  res.json({ status: "ok" }));

app.get("/health/ready", probeLimiter, async (_req, res) => {
  const database = await cachedPing();
  res.status(database === "up" ? 200 : 503)
     .json({ status: database === "up" ? "ok" : "degraded" });
});
```

---

### NEX-18 — Two devices creating the same note id concurrently lose one write

- **Priority:** P2
- **Category:** Data Integrity
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/sync-service.ts`
- **Effort:** S — 3 h

**Summary**  
`loadNote` takes `FOR UPDATE`, which locks nothing when the row does not exist. Two concurrent pushes for the same new id both see `existing === null`, both skip the merge, and the second overwrites the first.

**Root cause**  
`FOR UPDATE` is a row lock; there is no row to lock on first insert. The transaction runs at READ COMMITTED, so neither side sees the other's uncommitted insert, and `ON CONFLICT (id) DO UPDATE` resolves the collision by overwriting rather than merging.

**Impact**  
Narrow but real: the same note id arriving from two devices happens on restore-from-backup, on a re-paired device replaying its outbox, and whenever a push is retried against a slow first attempt. The losing side's content is discarded with no conflict recorded — the merge algorithm that exists specifically to prevent this is bypassed.

**Fix**  
Serialise per note id with a transaction-scoped advisory lock so the second writer waits and then observes the committed row.

**After:**
```ts
// hashtextextended gives a stable 64-bit key for a text id; the lock is
// released automatically at COMMIT or ROLLBACK.
await client.query(
  "SELECT pg_advisory_xact_lock(hashtextextended($1 || ':' || $2, 0))",
  [input.user_id, incoming.id],
);

// Now the read is guaranteed to see any concurrent committed insert.
const existing = await loadNote(client, input.user_id, incoming.id);
const resolved = existing ? mergeNotes(existing, local) : local;
```

---

### NEX-19 — Re-pushing an unchanged note bumps `rev` and `seq`, causing cross-device churn

- **Priority:** P2
- **Category:** Performance
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/sync-service.ts`
- **Effort:** M — 1 day (tag-set changes must still trigger a bump)

**Summary**  
`writeNote`'s conflict branch sets `rev = notes.rev + 1` and `seq = nextval(...)` unconditionally. A push carrying a row byte-identical to the stored one still advances both.

**Root cause**  
Server-authoritative revision was implemented as 'increment on every accepted write' rather than 'increment on every *change*'. There is no content comparison in the upsert, so the operation is not idempotent.

**Impact**  
A retried push — after a timeout, a 502 from an ingress, or an app restart mid-sync — inflates the revision and mints a new sequence value. That new seq places the row above every other device's cursor, so all of them re-download a note that did not change. With NEX-02 unfixed this compounds: the client re-pushes its whole outbox view repeatedly, and each cycle churns every peer.

**Fix**  
Make the write a no-op when nothing material differs.

**After:**
```sql
ON CONFLICT (id) DO UPDATE
   SET type = EXCLUDED.type,
       /* ... */
       rev  = notes.rev + 1,
       seq  = nextval('notes_seq_seq'),
       server_updated_at = NOW()
 WHERE notes.user_id = EXCLUDED.user_id
   AND notes.rev <= EXCLUDED.rev
   -- Idempotency: a retry that carries no change must not mint a new seq,
   -- because a new seq re-broadcasts the row to every other device.
   AND (notes.type,        notes.content,     notes.media_uri,
        notes.media_hash,  notes.duration_ms, notes.updated_at,
        notes.deleted_at)
       IS DISTINCT FROM
       (EXCLUDED.type,       EXCLUDED.content,     EXCLUDED.media_uri,
        EXCLUDED.media_hash, EXCLUDED.duration_ms, EXCLUDED.updated_at,
        EXCLUDED.deleted_at)
RETURNING rev, seq;

-- An unchanged row returns no tuple, so writeNote must distinguish
-- "rejected as stale" from "accepted, nothing to do" with a follow-up read.
```

---

### NEX-20 — `merged_by_server` is decided by `JSON.stringify` deep equality

- **Priority:** P2
- **Category:** Code Smell
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/services/sync-service.ts`, `apps/backend/src/services/merge.ts`
- **Effort:** XS — 45 min

**Summary**  
`const mergedByServer = existing !== null && JSON.stringify(resolved) !== JSON.stringify(local);` — structural comparison by serialisation, which depends on property insertion order.

**Root cause**  
It works today only because `mergeNotes` and the `local` literal in `pushChanges` happen to declare their twelve fields in the same order. Nothing enforces that. `JSON.stringify` also cannot see the difference between `undefined` and a missing key, and `exactOptionalPropertyTypes` is on precisely because those two states are distinguishable elsewhere in this codebase.

**Impact**  
Reordering a field in `merge.ts` — a formatting-level change no reviewer would flag — silently flips `merged_by_server` to true for every merge. That is the flag the pull query uses to decide whether to echo a row back to its author, so the failure mode is every device re-downloading its own writes indefinitely. A latent trap in the least obvious place.

**Fix**  
Compare the fields explicitly, or hash a canonicalised projection.

**After:**
```ts
const MERGE_FIELDS = [
  "type", "content", "media_uri", "media_hash", "duration_ms",
  "created_at", "updated_at", "deleted_at", "device_id",
] as const satisfies readonly (keyof NoteRow)[];

function differs(a: NoteRow, b: NoteRow): boolean {
  for (const field of MERGE_FIELDS) {
    if (a[field] !== b[field]) return true;
  }
  // tag_ids is the one array field; both sides are sorted by construction.
  if (a.tag_ids.length !== b.tag_ids.length) return true;
  return a.tag_ids.some((id, i) => id !== b.tag_ids[i]);
}

const mergedByServer = existing !== null && differs(resolved, local);
```

---

### NEX-21 — An out-of-range `since` cursor returns 500 instead of 400

- **Priority:** P2
- **Category:** Code Smell
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/routes/sync.ts`, `apps/backend/src/services/sync-service.ts`
- **Effort:** XS — 20 min

**Summary**  
`pullSchema` validates `since` with `/^\d+$/` and no length bound. A value above 2^63−1 passes validation, reaches PostgreSQL as a `bigint` comparison, and raises `22003 numeric field overflow`.

**Root cause**  
The regex checks the character class but not the magnitude, and the boundary between 'syntactically a non-negative integer' and 'representable as a bigint' was never drawn. The generic error middleware maps the unrecognised pg error to 500.

**Impact**  
A malformed or corrupted client cursor is reported as a server fault. That misroutes on-call attention, pollutes the error rate that any SLO would be measured against, and gives the client no actionable signal — a 400 would tell it to reset its cursor, a 500 tells it to retry forever.

**Fix**  
Bound the value in the schema so it is rejected at the edge.

**After:**
```ts
const MAX_CURSOR = 9223372036854775807n;   // bigint upper bound

const pullSchema = z.object({
  since: z
    .string()
    .regex(/^\d{1,19}$/, "since must be a non-negative integer cursor")
    .refine((v) => BigInt(v) <= MAX_CURSOR, {
      message: "since exceeds the maximum cursor value",
    })
    .optional(),
});
```

---

### NEX-22 — Downloaded installers accumulate in the cache directory forever

- **Priority:** P2
- **Category:** Code Smell
- **Area:** Flutter Client
- **Files:** `apps/client/lib/screens/update_sheet.dart`, `apps/client/lib/platform/app_update.dart`
- **Effort:** XS — 45 min

**Summary**  
`_download` writes `Nex-<version>.apk` into `getTemporaryDirectory()` and nothing ever removes it. Only the current download's `.part` and exact target name are cleared.

**Root cause**  
Cleanup was scoped to the single in-flight download. Previous versions use different filenames, so they never match the delete and simply stay.

**Impact**  
A universal APK for a Flutter app with native SQLite, audio and image plugins is on the order of 40–70 MB. A user who updates monthly silently accrues hundreds of megabytes of dead installers in app storage. Android may reclaim the cache directory under pressure, but only after the user has seen an inflated storage figure for the app — an avoidable trust problem for a product whose Settings screen reports storage usage.

**Fix**  
Sweep stale installers before each download.

**After:**
```dart
Future<void> _sweepOldInstallers(Directory dir) async {
  final pattern = RegExp(r'^Nex-.*\.(apk|exe)(\.part)?$');
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    if (!pattern.hasMatch(p.basename(entity.path))) continue;
    try {
      await entity.delete();
    } catch (_) {
      // A file the installer still holds open is not worth failing over.
    }
  }
}

// call before starting the new download
final dir = await getTemporaryDirectory();
await _sweepOldInstallers(dir);
```

---

### NEX-23 — Raw exception strings are rendered to the user in the update sheet

- **Priority:** P2
- **Category:** Code Smell
- **Area:** Flutter Client
- **Files:** `apps/client/lib/screens/update_sheet.dart`
- **Effort:** S — 2 h including the l10n strings in both locales

**Summary**  
The download catch block does `setState(() { _phase = _Phase.failed; _error = '$error'; })`, and `_error` is displayed directly.

**Root cause**  
Error presentation reuses the exception's `toString()`. Everywhere else in this codebase user-facing copy goes through `AppLocalizations`; this path bypasses it.

**Impact**  
The user sees `HttpException: Download failed (403), uri = https://objects.githubusercontent.com/...` — untranslated in a fully localised app (English and Farsi are both maintained), unreadable, and leaking internal URLs. It is also an RTL layout hazard: an unlocalised Latin-script URL inside a Farsi sheet renders with bidirectional artefacts.

**Fix**  
Map failures to localised, actionable messages and log the detail instead of showing it.

**After:**
```dart
} on UpdateIntegrityError {
  _fail(l10n.updateIntegrityFailed);
} on SocketException {
  _fail(l10n.updateCheckFailed);
} on HttpException {
  _fail(l10n.updateDownloadFailed);
} catch (error, stack) {
  // The detail belongs in a log, not in a bottom sheet.
  debugPrint('update download failed: $error\n$stack');
  _fail(l10n.updateDownloadFailed);
}

void _fail(String message) {
  if (!mounted) return;
  setState(() {
    _phase = _Phase.failed;
    _error = message;
  });
}
```

---

### NEX-24 — Five packages still resolve independently — no pub workspace

- **Priority:** P2
- **Category:** Dependency
- **Area:** CI / Tooling
- **Files:** `apps/client/pubspec.yaml`, `packages/core/pubspec.yaml`, `packages/data/pubspec.yaml`, `packages/ui/pubspec.yaml`, `packages/ai/pubspec.yaml`, `Makefile`
- **Effort:** S — 4 h, mostly verifying the resolution does not move

**Summary**  
There is no root `pubspec.yaml` declaring a workspace, and no member sets `resolution: workspace`. The Makefile runs each package's commands in sequence, which unifies the *task* surface but not the *resolution* graph.

**Root cause**  
The task-runner half of the monorepo problem was solved and the dependency half was not. Dart 3.6+ pub workspaces are available under the pinned 3.9 SDK, so the capability is present and unused.

**Impact**  
Each package resolves `crypto`, `uuid`, `path`, `meta`, `http` and `lints` independently, so the app and the packages it consumes can compile against different minor versions of the same transitive dependency with nothing to detect the skew. Only `apps/client/pubspec.lock` is committed, so the packages' resolutions are not reproducible at all — a CI run weeks apart can resolve differently with no commit in between.

**Fix**  
Adopt the workspace and commit the single root lockfile.

**After:**
```yaml
# /pubspec.yaml  (new)
name: nex_workspace
publish_to: "none"
environment:
  sdk: ^3.9.0
workspace:
  - apps/client
  - packages/ai
  - packages/core
  - packages/data
  - packages/ui

# each member pubspec.yaml adds:
resolution: workspace

# Makefile
bootstrap:
	dart pub get          # one resolution for the whole repo
	cd apps/backend && npm ci

# commit /pubspec.lock; delete apps/client/pubspec.lock
```

---

### NEX-25 — The backend CI smoke test declares a database that is not running

- **Priority:** P2
- **Category:** Test Coverage
- **Area:** CI / Tooling
- **Files:** `.github/workflows/ci.yml`
- **Effort:** S — 2 h

**Summary**  
The `backend` job's smoke step sets `DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nex`, but that job declares no `services: postgres`. It then polls `/health/live`, which deliberately does not touch the database.

**Root cause**  
The step was written to prove the built artifact starts, and `/health/live` was chosen precisely because it has no dependencies. The `DATABASE_URL` is present only to satisfy env validation, which makes the configuration look like an integration test when it is a process-start check.

**Impact**  
The step proves less than it appears to: it cannot catch a broken pool configuration, a missing migration, or a readiness regression. Meanwhile `startPurgeSchedule()` begins firing against an unreachable database and logging warnings into the smoke log, so a genuine failure is buried in expected noise. A reader trusts this job more than it deserves.

**Fix**  
Either add the service and assert readiness, or make the intent explicit.

**After:**
```yaml
  backend:
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: nex
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s --health-timeout 5s --health-retries 5
    steps:
      # ...
      - run: npm run build
      - run: npm run migrate
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/nex
      - name: Smoke test the built artifact
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/nex
          PORT: "4100"
        run: |
          node dist/index.js > "$RUNNER_TEMP/smoke.log" 2>&1 &
          echo $! > "$RUNNER_TEMP/smoke.pid"
          npx wait-on -t 30000 http-get://127.0.0.1:4100/health/ready
          # Readiness, not liveness: this asserts the pool actually connects.
          curl -sf http://127.0.0.1:4100/health/ready | grep -q '"database":"up"'
          kill "$(cat "$RUNNER_TEMP/smoke.pid")" || true
```

---

### NEX-26 — `/sync/test/reset` performs five destructive statements outside a transaction

- **Priority:** P2
- **Category:** Data Integrity
- **Area:** Backend (Node/TS)
- **Files:** `apps/backend/src/routes/sync.ts`
- **Effort:** XS — 30 min

**Summary**  
The reset handler issues five sequential `getPool().query(...)` calls, each on an arbitrary pooled connection, each autocommitting.

**Root cause**  
The handler predates `withTransaction` being available and was never migrated, even though every other multi-statement write in the codebase now uses it.

**Impact**  
A failure partway through leaves the tenant half-wiped: notes deleted but tags retained, or `device_acks` left pointing at sequence values for rows that no longer exist. Because this runs between matrix test cases, a partial failure produces a corrupt fixture and a confusing cascade of unrelated assertion failures rather than one clear error.

**Fix**  
Wrap it, and let the FK cascade do the join-table cleanup.

**After:**
```ts
syncRouter.post("/test/reset", async (req: Request, res: Response) => {
  if (!env.isTestMode) throw new NotFound();
  const { userId } = auth(req);

  await withTransaction(async (client) => {
    // note_tags cascades from notes (0001_init.sql), so it needs no
    // statement of its own.
    await client.query("DELETE FROM notes WHERE user_id = $1", [userId]);
    await client.query("DELETE FROM tags WHERE user_id = $1", [userId]);
    await client.query("DELETE FROM media_objects WHERE user_id = $1",
                       [userId]);
    await client.query(
      "UPDATE device_acks SET last_pull_seq = 0 WHERE user_id = $1",
      [userId]);
  });

  res.json({ status: "ok" });
});
```

---

### NEX-27 — Every sync pushes the complete tag table regardless of what changed

- **Priority:** P2
- **Category:** Performance
- **Area:** Sync Client (Dart)
- **Files:** `packages/data/lib/sync_client/sync_client.dart`
- **Effort:** M — 1 day

**Summary**  
`sync()` builds its push body with `repo.listTags()` — all tags, every time — while notes correctly come from `repo.listPending()`.

**Root cause**  
Tags have no outbox. Notes carry a `sync_state` column that drives `listPending`; the tag table has no equivalent, so the client cannot tell which tags are dirty and sends everything.

**Impact**  
Every sync runs one `upsertTag` per tag on the server, and each of those calls `nextval('tags_seq_seq')` in its `DO UPDATE` branch — so **every tag's seq advances on every sync from any device**, which pushes all of them above every other device's cursor and forces all peers to re-download the entire tag table on their next pull. A 200-tag library turns each sync into 200 server writes plus a full tag broadcast to every device. This is the tag-side equivalent of NEX-19 and it fires unconditionally.

**Fix**  
Give tags an outbox and only bump `seq` when something actually changed.

**After:**
```dart
-- packages/data local schema
ALTER TABLE tags ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'pending';
-- set to 'pending' on insert, rename, colour change or merge

// sync_client.dart
final tags = repo.listPendingTags();

// apps/backend — sync-service.ts: an unchanged upsert must not mint a seq
`ON CONFLICT (user_id, lower(name)) DO UPDATE
    SET color      = COALESCE(EXCLUDED.color, tags.color),
        created_at = LEAST(tags.created_at, EXCLUDED.created_at),
        seq        = CASE
                       WHEN tags.color IS DISTINCT FROM
                            COALESCE(EXCLUDED.color, tags.color)
                         OR tags.created_at IS DISTINCT FROM
                            LEAST(tags.created_at, EXCLUDED.created_at)
                       THEN nextval('tags_seq_seq')
                       ELSE tags.seq
                     END
  RETURNING id`
```

---

## Recurring Themes

### The client and server halves of sync drifted apart
Five of the eleven P0/P1 findings are the same shape: the backend was rewritten correctly and `SyncClient` was not updated to match. It reads `server_time` where the server sends `cursor`, `merged_ids` where it sends `merged`, and ignores `tag_remap` and `has_more` entirely. Every read is written defensively with `as T?` and `?? const []`, so each break degrades into a plausible-looking empty value instead of an exception. The result is that v2 sync is, functionally, a full-corpus re-download with a silently truncating outbox.
**Related findings:** NEX-02, NEX-03, NEX-04, NEX-05, NEX-09

### The one test that covers sync cannot fail on any of it
The six-row matrix asserts convergence between two devices with fresh in-memory databases. A full re-download converges trivially, 12 notes never reach a 500-row page, and both devices get their tags from the same origin so competing UUIDs never arise. The suite is well-written for the conflict semantics it was designed to pin down, and structurally blind to the transport defects sitting underneath it.
**Related findings:** NEX-10, NEX-25

### Correct transactional logic, missing operational envelope
The transactional rewrite, row locks, advisory-locked migrations and two-phase delete are all sound. What is missing is the boundary around them: a 10-connection pool holding long REPEATABLE READ transactions, no statement or idle-in-transaction timeouts, an unbatched global purge running on every replica at once, and in-memory rate limiting behind an untrusted proxy. Nothing here is wrong at one user; all of it fails together at a thousand.
**Related findings:** NEX-13, NEX-14, NEX-16, NEX-11, NEX-12, NEX-17

### Idempotency was never established end to end
Retrying a push bumps `rev` and mints a new `seq` even when nothing changed; pushing the tag table re-sequences every tag; a first-insert race has no lock to take. Each of these turns an ordinary retry — a timeout, a 502, an app restart mid-sync — into fan-out work for every other device on the account.
**Related findings:** NEX-18, NEX-19, NEX-27

---

## Tab 2 — World-Class Vision (No Constraints)

### Positioning
**Thesis:** Nex is one of the very few capture tools whose primary platforms are Android and Windows. Every serious competitor in this category — Drafts, Bear, Apple Notes Quick Note, Craft — is Apple-first, and the cross-platform ones (Keep, Notion, Obsidian) are not built around capture latency. That gap is the entire opportunity, and it is defensible because the incumbents cannot chase it without abandoning their own platform advantage.

**Wedge:** Own the two seconds between having a thought and it being safe. Not the note-taking market — the capture moment. Everything else in the product is downstream of winning that moment on hardware nobody else optimises for.

**Target metrics:**

| Metric | Target | Note |
|---|---|---|
| Cold launch → cursor blinking | < 200 ms | p95, mid-tier Android |
| Widget tap → text committed | < 400 ms | no app launch at all |
| Search keystroke → results | < 50 ms | 100k notes, on-device |
| Crash-free sessions | > 99.9 % | capture path: 100 % |

### Competitive Landscape

| Product | Capture latency | Local-first | Android + Windows | E2EE sync | Where Nex wins |
|---|---|---|---|---|---|
| Drafts | Excellent | Partial | iOS/macOS only | No | Nex covers the platforms Drafts refuses to. |
| Google Keep | Good | No | Yes | No | Nex is private by construction; Keep is an ads-company product. |
| Apple Notes | Good (Quick Note) | Partial | No | Optional | Nex is the Quick Note that exists off Apple hardware. |
| Obsidian | Poor | Yes | Yes | Paid add-on | Nex is the front door; Obsidian is the library. Integrate, don't compete. |
| Notion | Poor | No | Yes | No | Nex has no setup, no schema, no blank-page tax. |
| Bear | Good | Partial | No | No | Same craft bar, platforms Bear will never ship. |
| Twos / Amplenote | Good | No | Yes | No | Nex works fully offline and holds nothing hostage. |

### Vision Sections

#### Foundations: The architecture I would build instead

Three of the four P0s in this audit come from the same structural cause: two hand-written implementations of one protocol, in two languages, kept in agreement by discipline. The fix is not better discipline. It is to make the second implementation impossible.

> **Move the domain into a Rust core and compile it everywhere**
> 
> Notes, merge semantics, the outbox state machine, the wire codec, crypto and the local schema all live in one `nex-core` Rust crate. Flutter binds it through flutter_rust_bridge; the server runs the same crate natively. The conformance corpus that currently exists to prove two implementations agree becomes unnecessary, because there is one implementation. NEX-02, NEX-03, NEX-04, NEX-09 and NEX-20 are all instances of a class of bug that cannot occur once the codec is shared code rather than shared documentation.

**`Sync` Replace field-aware LWW with a real CRDT**  
The current merge is a careful, well-tested, hand-rolled LWW with tag union — and it still needs a 12-case corpus, a commutativity proof and a server referee to be trusted. Loro or Automerge gives convergence as a property of the data type: no referee, no tie-break rules, no `merged_by_server` flag, offline-forever with no divergence, and character-level merge inside a note body so two devices editing the same paragraph both keep their words. The server stops being an arbiter and becomes a dumb, encrypted, append-only relay.

**`Privacy` End-to-end encryption, non-negotiable**  
A product marketed as 'the inbox for your mind' cannot store plaintext thoughts on a server. Per-account XChaCha20-Poly1305 content key, derived from a passphrase via Argon2id, wrapped per device at pairing. The server sees ciphertext blobs, an opaque note id and a sequence number — nothing else. This also deletes an entire category of liability: no plaintext to leak, subpoena, or accidentally log. It makes the tombstone-purge privacy story (NEX-06, NEX-14) largely moot.

**`Storage` SQLite + FTS5 + sqlite-vec in one file**  
Keep SQLite — it is the right call and already works. Add `sqlite-vec` so lexical and vector search live in the same file, the same transaction and the same backup. One file to back up, restore, export and encrypt at rest via SQLCipher. No second datastore, no sync between indexes, no partial-restore states.

**`Backend` Rust + Axum on the same crate, or nothing at all**  
Once the server is a relay for opaque blobs it barely needs a server. An Axum service over Postgres is ~600 lines. It should also be genuinely optional: ship a self-host Docker image on day one, and support iCloud/Drive/WebDAV/S3 as a bring-your-own-backend transport so users who distrust hosted sync still get multi-device. Trust is the product.

**`Client` Stay on Flutter — it is the right choice**  
One codebase for Android, Windows, iOS, macOS and Linux with native-feeling motion is exactly what this product needs, and the existing worker-isolate architecture is sound. Invest in Impeller, precise frame budgets and platform-channel work for the OS surfaces that actually differentiate: widgets, quick settings tiles, global hotkeys, App Intents.

**`Contract` Generate the wire format, never hand-write it**  
Protobuf or a typed IDL with generated Dart and Rust. Contract tests run against the generated types, so a field rename is a compile error in both languages on the same commit. Every protocol-drift finding in Tab 1 becomes structurally unreachable.

*Target dependency graph*
```text
                      ┌──────────────────────────┐
                      │   nex-core  (Rust)       │
                      │  · Note / Tag domain     │
                      │  · Loro CRDT documents   │
                      │  · outbox state machine  │
                      │  · wire codec (protobuf) │
                      │  · XChaCha20 + Argon2id  │
                      │  · SQLite + FTS5 + vec   │
                      └───────────┬──────────────┘
                                  │  one implementation
              ┌───────────────────┼───────────────────┐
              │                   │                   │
   flutter_rust_bridge      native link          wasm32
              │                   │                   │
      ┌───────▼───────┐   ┌───────▼───────┐   ┌───────▼───────┐
      │ Flutter app   │   │ Axum relay    │   │ Web / ext.    │
      │ Android · Win │   │ (ciphertext   │   │ read-only     │
      │ iOS · macOS   │   │  only)        │   │ capture       │
      └───────────────┘   └───────────────┘   └───────────────┘

The server cannot read a note. The client cannot disagree with itself.
```


#### The wedge: Make capture physically faster than anything else on the device

The tagline promises seconds. That should be an engineering budget with a test that fails the build, not a marketing line. If Nex is not measurably the fastest way to record a thought on Android and Windows, it has no reason to exist.

> **The real competitor is the Android notification shade, not another notes app**
> 
> People capture thoughts by sending themselves a message, using the keyboard's clipboard, or typing into whatever is already open. Nex wins by being available in those exact places — not by being a better destination once you have already decided to open a notes app.

**`Android` Inline widget capture with no app launch**  
A RemoteViews widget with a real inline input, committing straight to SQLite through a foreground service. Tap → type → done, with the app process never starting. Plus a Quick Settings tile, a persistent low-priority notification with a reply action, and a Direct Share target.

**`Android` A keyboard-adjacent capture surface**  
An accessibility-service or bubble-based floating capture that overlays any app. The thought usually arrives while reading something else; forcing a context switch is where capture tools lose.

**`Windows` Global hotkey → floating composer**  
Win+Alt+N summons a frameless, always-on-top composer in under 100 ms from a pre-warmed hidden window. Escape dismisses, Enter commits. Plus a tray icon, jump-list actions, and clipboard-history capture.

**`iOS` Action Button, Control Center, Lock Screen**  
App Intents so Nex is a first-class Shortcuts citizen, an Action Button binding, a Control Center control (iOS 18+), Lock Screen widgets and a Live Activity while recording voice.

**`Wearable` Wear OS and watchOS voice capture**  
Raise wrist, speak, done — synced when the phone is next reachable. The highest-value capture moments are the ones where a phone is not in your hand.

**`Everywhere` CLI, email-in, and browser extension**  
`nex "thought"` from a terminal. A private per-account email address that becomes a note. A browser extension that captures selection plus source URL. Meet people where the thought already is.

*Enforce the budget in CI, not in a design doc*
```dart
// integration_test/capture_latency_test.dart
//
// This test exists so that "Capture in Seconds" is a build gate. A regression
// that adds 80 ms to cold start fails the PR that introduced it, not a
// bug report six releases later.

testWidgets('cold launch to focused composer stays inside budget', (t) async {
  final trace = await startTimeline();
  await t.pumpWidget(const NexApp());
  await t.pumpAndSettle();

  expect(find.byType(CaptureField), findsOneWidget);
  expect(
    tester.binding.focusManager.primaryFocus?.context?.widget,
    isA<EditableText>(),
    reason: 'the cursor must already be live — no tap required',
  );

  final summary = await trace.stop();
  expect(summary.timeToFirstFrameMs, lessThan(200));
  expect(summary.jankFrameCount, 0,
      reason: 'not one dropped frame on the capture path');
});
```

**Capture-path rules I would enforce as lint**
- No await between the keystroke and the durable write. The write is fire-and-forget into a WAL-backed queue.
- No network call, no analytics call and no AI call may be reachable from the capture code path — enforced by an import-boundary check in CI.
- The composer widget tree may not depend on any provider that can be in a loading state.
- Cold start does no migration, no backup, no index rebuild. All of it is deferred past first frame.


#### Product: The features that turn a capture inbox into something people pay for

Capture is the wedge, not the business. Every capture tool that stalled did so because it was write-only: users trusted it with thoughts and then never got them back. Retrieval and resurfacing are what make the product sticky.

> **The single highest-leverage feature: resurfacing**
> 
> A capture app that only captures becomes a landfill, and users eventually notice. A gentle daily resurfacing loop — three old notes, chosen by a mix of recency, semantic clustering and spaced repetition — converts a write-only inbox into something with a reason to open it. This is the difference between a utility people forget and a habit they pay for. It must respect the product's own silence rule: pull, never push; no badge, no notification unless explicitly enabled.

**`AI · on-device` Whisper-class transcription, fully local**  
whisper.cpp or Parakeet via ONNX Runtime, streaming, with the partial transcript visible while recording. Voice becomes the fastest capture mode. Nothing leaves the device, so it works on a plane and costs nothing per user — which also means it can be free, unlike every cloud-transcription competitor.

**`AI · on-device` OCR on every photo, indexed into FTS5**  
ML Kit on Android, Vision on Apple, Windows.Media.Ocr on Windows. A photographed whiteboard, receipt or book page becomes full-text searchable within seconds of capture, in the background, off the capture path.

**`AI · on-device` Semantic search with local embeddings**  
EmbeddingGemma or gte-small quantised to int8, vectors in sqlite-vec. 'That thing about pricing' finds the note that never used the word pricing. Hybrid BM25 + cosine with reciprocal-rank fusion. Still instant, still offline, still private.

**`AI · optional` Ask-my-brain, with a local model by default**  
A retrieval-augmented chat over your own corpus — Gemma or Qwen via llama.cpp locally, with an opt-in bring-your-own-key cloud path for people who want a frontier model. The default must be local, or the privacy promise is theatre.

**`Retrieval` Search that behaves like a command palette**  
One field. Type to filter, `#` for tags, `>` for actions, `@` for dates, natural language for time ranges. Sub-50 ms at 100k notes. Results ranked by a blend of lexical, semantic and recency signals, with the matched span highlighted.

**`Retrieval` Automatic clustering, never mandatory folders**  
Nightly on-device clustering proposes themes — 'you have written about this eleven times' — as a suggestion the user can accept, rename or dismiss. Organisation emerges from the corpus instead of being demanded up front. This is the promise 'organize later, if you ever need to' actually cashed in.

**`Trust` Export that is boring, complete and continuous**  
A live Markdown + attachments folder mirror, not a one-shot zip. Obsidian-compatible frontmatter, a documented JSON schema, and a `nex export` CLI. The strongest retention mechanism for a privacy product is credibly making it easy to leave.

**`Integrations` Be the front door to whatever people already use**  
One-way flush to Obsidian, Readwise, Notion, Todoist, Things, Apple/Google Reminders. Plus an MCP server so Claude or any agent can query a user's Nex locally. The README already positions Nex as a front door — integrations are that positioning made real rather than stated.

| Capability | Where it runs | Cost per user | Free or paid |
|---|---|---|---|
| Transcription | On device (whisper.cpp) | $0 | Free |
| OCR | On device (platform APIs) | $0 | Free |
| Embeddings / semantic search | On device (ONNX int8) | $0 | Free |
| Clustering & resurfacing | On device, overnight | $0 | Free |
| E2EE multi-device sync | Relay (ciphertext only) | ~$0.05/mo | Paid |
| Encrypted cloud backup | Object storage | ~$0.10/mo | Paid |
| Frontier-model chat | User's own API key | $0 to us | Free with BYOK |


#### Craft: Design system and the feel of the thing

In this category craft is the moat. Drafts and Bear win on feel, not features. The bar is not 'looks clean' — it is that every interaction has a considered motion curve, a haptic, and a defined behaviour at 200% text scale in Farsi.

**`Tokens` A real token pipeline, not a Dart constants file**  
Design tokens in JSON as the source of truth, compiled by Style Dictionary into Dart, Kotlin, Swift and CSS. Figma variables bound to the same file. Colour in OKLCH so dark mode is generated with guaranteed contrast ratios rather than hand-picked and hoped for.

**`Motion` A documented motion spec with named curves**  
Every transition classified — emphasised, standard, decelerate — with durations tied to distance travelled. Shared-element transitions from timeline row to detail. Everything reduced to a cross-fade under `reduceMotion`, which is already a preference and should be honoured everywhere, not selectively.

**`Haptics` A haptic vocabulary**  
Capture committed, swipe threshold crossed, undo available, delete confirmed — each with a distinct, consistent pattern. On a capture tool the haptic *is* the confirmation, because there is no Save button to press and no dialog to acknowledge.

**`Accessibility` WCAG 2.2 AA as a build gate**  
Automated axe-style checks in widget tests, minimum 44×44 targets, full TalkBack and Narrator passes per release, and correct semantic announcements for capture-committed. Farsi is already shipped, so RTL and bidirectional text must be tested continuously, not spot-checked.

**`Identity` Visual identity worth trusting**  
A real wordmark and monochrome silhouette, an animated launch that resolves into the composer rather than a static splash, themed icons that work under every Material You palette, and a distinctive capture sound that can be disabled.

**`Density` Timeline that scales from 10 notes to 100,000**  
Sticky date headers, virtualised list with stable keys, a scrub bar for jumping years, and rich inline previews — waveform for voice, thumbnail for photo, favicon for links. Comfort mode already exists as a preference; it should drive a genuinely different information density, not just padding.

> **One opinionated rule: the app must never show a spinner on the capture path**
> 
> Not a skeleton, not a shimmer, not a progress bar. If something is slow it happens after the note is already durable and the cursor is already blinking. A spinner in front of a thought is the product failing at the one thing it promises.


#### Production: Infrastructure, security and the operational envelope

Tab 1 lists a pool of ten connections, in-memory rate limiting and an unbatched global purge. Those are the symptoms of a service that has never been operated. This is what operating it properly looks like.

**`Runtime` Fly.io or Hetzner + Kamal, not Kubernetes**  
A ciphertext relay does not justify a control plane. Multi-region Fly machines close to users, Postgres on Neon or a managed provider with PITR, S3-compatible object storage for encrypted media blobs. Kubernetes is a cost centre until there is a team to staff it.

**`Data` Backups you have actually restored**  
Point-in-time recovery, plus a scheduled restore drill in CI that provisions a throwaway database from the latest snapshot, runs migrations and asserts row counts. An untested backup is a belief, not a control.

**`Observability` OpenTelemetry end to end**  
Traces spanning client sync → relay → Postgres, correlated by the request id that already exists. Structured logs shipped to Loki or Axiom. RED metrics per route. Sentry with source maps on the backend and symbolicated Dart stack traces on the client. Alert on sync error rate and p99 pull latency, not CPU.

**`Security` Treat it like a target, because it is**  
Annual third-party pen test and a published report. A funded bug bounty. SLSA level 3 provenance and Sigstore signing for every release artifact — which also closes NEX-08 properly rather than patching it. Reproducible builds so a user can verify the APK matches the tag. SBOM per release.

**`Security` Client-side hardening**  
SQLCipher at rest keyed from the platform keystore, biometric app lock, screenshot blocking in the app switcher, certificate pinning for the relay, and a panic-wipe. A stolen unlocked phone should not equal a stolen corpus.

**`Release` Staged rollout with automatic halt**  
Play Console staged rollout at 1% → 10% → 50% → 100%, gated on crash-free rate. Feature flags for anything touching sync so a bad protocol change is switched off rather than rolled back. Beta and canary tracks with real users on them before every release.

*The invariants I would encode as continuous property tests*
```rust
// nex-core/tests/sync_properties.rs
//
// The current suite asserts six hand-written scenarios. Convergence is a
// property, and properties want a generator, not examples. This is how a
// bug like "the cursor outruns the page" gets found by a machine at 3am
// instead of by an auditor reading the code.

proptest! {
    /// Any interleaving of writes across any number of devices, with any
    /// pattern of dropped connections, converges to identical state.
    #[test]
    fn all_devices_converge(ops in operation_sequence(1..=5, 0..=500)) {
        let mut world = SimulatedWorld::new();
        world.apply(ops);
        world.run_until_quiescent();
        prop_assert!(world.all_replicas_identical());
    }

    /// A note that was committed on any device is present on all of them.
    /// This is the invariant NEX-01 violates.
    #[test]
    fn no_write_is_ever_lost(ops in operation_sequence(2..=4, 1..=2000)) {
        let mut world = SimulatedWorld::new();
        let committed = world.apply(ops);
        world.run_until_quiescent();
        for replica in world.replicas() {
            prop_assert_eq!(replica.note_ids(), committed);
        }
    }

    /// Replaying any prefix of a device's requests changes nothing.
    /// This is the invariant NEX-19 violates.
    #[test]
    fn sync_is_idempotent_under_retry(ops in operation_sequence(1..=3, 0..=200),
                                      retries in retry_schedule()) {
        let a = SimulatedWorld::new().apply_then_settle(ops.clone());
        let b = SimulatedWorld::new()
                    .apply_with_retries(ops, retries)
                    .settle();
        prop_assert_eq!(a.canonical_state(), b.canonical_state());
    }
}
```


#### Market: Monetisation and distribution

The privacy positioning constrains the business model in a way that is actually clarifying: no ads, no data, no engagement farming. That leaves subscription and one-time purchase — and it makes the on-device AI decision a margin decision as much as a principled one.

> **Free tier must be genuinely, permanently useful — including AI**
> 
> Because transcription, OCR and embeddings run on device, they cost nothing per user and can all be free forever. That is a positioning weapon no cloud-AI competitor can match: they must charge for what Nex gives away. The paid tier sells the one thing that genuinely has marginal cost — moving encrypted bytes between your devices and keeping a backup of them.

| Tier | Price | Includes | Rationale |
|---|---|---|---|
| Nex (free) | $0 forever | Unlimited local capture, all on-device AI, full export, one device | The product must be complete without paying. Anything less undermines the trust pitch. |
| Nex Sync | $4/mo or $36/yr | E2EE multi-device sync, encrypted backup, version history, web access | Prices against Bear ($3) and Drafts Pro ($2.5) while covering real infra cost. |
| Nex Sync Family | $60/yr | Up to 5 accounts, separate encrypted vaults | High-margin, near-zero support overhead, strong retention. |
| Lifetime | $149 one-time | Sync forever, capped device count | Funds early runway and appeals to exactly the anti-subscription crowd this product attracts. |
| Self-hosted | Free (AGPL relay) | Run your own relay, full feature parity | Converts the most sceptical users into advocates. Costs nothing and buys enormous credibility. |

**Distribution**
- Play Store, Microsoft Store, App Store, Mac App Store — plus F-Droid for a fully FOSS build, which the privacy audience treats as a signal of seriousness.
- winget, Homebrew cask, Scoop, Flathub, AUR. Direct signed APK and .exe stay supported — the in-app updater already built for this is a genuine asset for the F-Droid-averse Android sideloading audience.
- Launch narrative: not 'another notes app' but 'the capture app for people who aren't on a Mac'. Ship on Android and Windows first and say so loudly — it is the only story in this category nobody else can tell.
- Content strategy around the engineering: the CRDT work, the on-device AI, the E2EE design, and a published threat model. This audience reads that material and it is the cheapest credible acquisition channel available.
- Open-source the client under AGPL, keep the relay open too, sell the hosted service. Obsidian and Bear both prove people pay for convenience even when the format is open.


#### Passion project: The unconventional bets I would actually make

If this were mine and nobody could tell me no, these are the things I would build that no competitor would sanction — the ones that make a product memorable rather than merely good.

**`Hardware` A physical capture button**  
A £25 BLE fob on a keyring or desk. Press, speak, release. It appears in Nex transcribed. Every serious capture user has described wanting exactly this. Hardware is also a moat no software competitor will cross, and it turns the product into something with a physical presence in someone's life.

**`Ritual` Inbox Zero for thoughts**  
An explicit, optional daily review: swipe each new capture to keep, act, file or discard. Two minutes, gamified only enough to be satisfying. Turns a passive landfill into a practice — and gives the product a daily-open reason that does not require a notification.

**`Time` A time-travel scrubber**  
Drag a slider and watch the corpus rewind. See what you were thinking about in March. With CRDT history this is nearly free, and it is the kind of thing people screenshot and post.

**`Ambient` Opt-in ambient voice buffer**  
A rolling 60-second on-device audio buffer, never written to disk, discarded continuously. Press capture and the previous 60 seconds is transcribed too — because you always realise a thought was worth keeping just after you finish saying it. Enormously useful, and only ethically shippable because it is fully local, off by default and visibly indicated.

**`Extensibility` A sandboxed plugin runtime**  
Small WASM plugins with a capability-scoped API: capture transforms, custom resurfacing rules, export targets. Obsidian's plugin ecosystem is the single largest reason it is hard to leave. Start narrow, sandbox hard, never grant network without an explicit prompt.

**`Agents` Ship an MCP server in the app**  
Let Claude or any local agent query a user's corpus, with per-tool consent and a visible audit log of what was read. Nex becomes the memory layer for whatever assistant someone already uses — a position that gets more valuable every year, and one that no closed notes app can occupy.

**`Format` Git as an optional backing store**  
For the developer audience: back the vault with a real git repo, one commit per capture batch, push wherever. Sync, history and portability solved with a format that will still be readable in thirty years. Niche, cheap to build on top of a Markdown mirror, and enormously loved by exactly the people who evangelise tools.

**`Craft` A public latency leaderboard**  
Publish p95 cold-start-to-cursor per device model, measured continuously, on the website. Invite competitors to beat it. Turning the core promise into a public, falsifiable number is both a forcing function internally and the most credible marketing a capture tool could run.


### Roadmap

**Phase 0 — Make sync actually work** (Weeks 1–4)

Nothing in this vision matters while v2 sync silently loses writes. Close every P0 and P1 from Tab 1, and rebuild the matrix so it can fail.

Outcomes:
- Cursor, outbox and tag remap correct end to end; incremental pull verified on the wire
- Sync matrix extended: pagination, rejected writes, competing tag names, cursor assertions
- Test-mode wipe impossible in production; update artifacts checksum-verified
- Operational envelope: pool sizing, statement timeouts, chunked purge, trust proxy

*Signal:* A 20k-note library syncs incrementally across three devices with zero divergence over a week.

**Phase 1 — Own the capture moment** (Months 2–4)

Ship the latency budget as a build gate, then build the OS surfaces that make Nex reachable without opening it.

Outcomes:
- Sub-200 ms cold-to-cursor enforced in CI on a real device farm
- Android inline widget, QS tile, notification reply; Windows global hotkey composer
- On-device transcription — voice becomes the fastest capture mode
- Command-palette search at sub-50 ms on 100k notes

*Signal:* Median time from intent to durable note under two seconds, measured on real users.

**Phase 2 — Earn trust at the protocol level** (Months 4–8)

Move the domain into Rust, adopt a CRDT, and make the server incapable of reading a note. This is the big architectural bet and it should happen before the user base is large enough to make migration painful.

Outcomes:
- nex-core Rust crate via flutter_rust_bridge; one implementation of the protocol
- Loro CRDT replaces field-aware LWW; the referee disappears
- E2EE with per-device key wrapping; published threat model and third-party audit
- Self-host image and BYO-backend transports shipped alongside hosted sync

*Signal:* A published, audited threat model — and a relay operator who provably cannot read a note.

**Phase 3 — Retrieval and resurfacing** (Months 8–12)

Convert the capture inbox into something with a daily reason to open it, entirely on device.

Outcomes:
- Local embeddings + sqlite-vec hybrid search; OCR on every image
- Resurfacing loop and the optional Inbox Zero review ritual
- Automatic clustering proposing themes rather than demanding folders
- Live Markdown mirror, Obsidian/Readwise integrations, MCP server

*Signal:* Weekly retention above 60% among users past their first month.

**Phase 4 — Commercial launch** (Months 12–18)

Store presence everywhere, paid sync, and the craft polish that makes it reviewable.

Outcomes:
- Play, Microsoft, App Store, Mac App Store, F-Droid, winget, Homebrew
- Nex Sync subscription with staged rollout and crash-rate gating
- Full design-token pipeline, motion spec, WCAG 2.2 AA verified, RTL continuously tested
- Public latency leaderboard and the engineering content programme

*Signal:* Sustainable revenue from sync, and a review cycle that leads with the platform story.

**Phase 5 — The bets** (Month 18+)

The things that make it memorable rather than merely excellent.

Outcomes:
- BLE capture fob
- WASM plugin runtime with capability-scoped permissions
- Ambient voice buffer, opt-in and fully local
- Time-travel scrubber over CRDT history; git-backed vault option

*Signal:* People describe Nex to their friends using a feature no competitor has.
