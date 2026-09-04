import 'dart:convert';

import 'package:http/http.dart' as http;
// nex_core also exports a MergedNote (the field-aware merger's server-side
// result type) — unrelated to sync_wire's wire-level typedef of the same
// name, and unused here, so it's hidden rather than left to collide.
import 'package:nex_core/nex_core.dart' hide MergedNote;

import '../repositories/note_repository.dart';
import 'sync_wire.dart';

/// HTTP sync client — push outbox, pull deltas (04-architecture.md).
///
/// Conflict resolution is performed on the server (field-aware). The client
/// applies the pull set as the remote truth for synced rows.
///
/// Typed against the concrete [SqliteNoteRepository] rather than the
/// [NoteRepository] port: syncing needs the outbox surface (listPending,
/// markSynced, applyRemoteNote, upsertTagFromSync) that the port deliberately
/// does not expose to the domain layer.
class SyncClient implements SyncPort {
  SyncClient({
    required this.baseUrl,
    required this.deviceId,
    required this.repo,
    this.bearerToken,
    this.requestTimeout = _defaultRequestTimeout,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String deviceId;
  final SqliteNoteRepository repo;

  /// Device token issued by `POST /auth/pair`.
  ///
  /// The sync API stopped being open when tenancy landed, but this client was
  /// never taught to authenticate — it sent no Authorization header at all, so
  /// every push and pull came back 401 against a real server.
  final String? bearerToken;

  final http.Client _http;

  /// How many pages one cycle will drain before deciding the cursor is stuck.
  ///
  /// 200 × the server's 500-row page is 100k rows. Past that, something is
  /// wrong with the watermark, and looping forever is worse than stopping.
  static const _maxPages = 200;

  /// The server's push endpoint rejects a `notes` or `tags` array above 500
  /// items (routes/sync.ts's `pushSchema`) with a flat 400 — and the whole
  /// outbox used to go up in one request, so a device with a backlog above
  /// that — a long offline period, or a first sync of an existing corpus —
  /// never synced at all: push threw before the pull this same cycle would
  /// otherwise have run even got a chance to recover anything.
  static const _pushBatchSize = 500;

  /// How long one request is allowed to take before the cycle gives up.
  ///
  /// `package:http` has no default timeout, and these two calls were the only
  /// network in the app without one — `FeedbackService` uses 15s, `LinkReader`
  /// 8s, the cloud AI adapter 90s and 3min. The absence mattered more here
  /// than anywhere else: sync is dispatched through the db worker, and that
  /// worker runs one command at a time. A connection that is accepted and then
  /// answers nothing — a suspended server, a dropped NAT binding, a VPN that
  /// went away without a FIN — parks the request for as long as the OS keeps
  /// the socket open, and every timeline read, search and capture queued
  /// behind it waits there too. The app's whole data layer stops, with nothing
  /// on screen to say why.
  ///
  /// 30 seconds is chosen against the payload rather than against patience: a
  /// push carries up to 500 notes and a pull returns up to a 500-row page, so
  /// this has to cover a large transfer on a bad mobile connection while still
  /// being far below the several minutes an abandoned socket can take.
  ///
  /// A `.timeout` frees the caller, not the socket — the connection is left to
  /// the OS to reap. That is the right trade here: what was hurting was the
  /// waiting, not the file descriptor.
  static const _defaultRequestTimeout = Duration(seconds: 30);

  /// The value in use, so that a test can reach this at all.
  ///
  /// A constant would have been simpler and would have shipped a timeout no
  /// suite could exercise without waiting half a minute for it — the same
  /// shape of gap that let the reminder scheduling path go untested until it
  /// was extracted. Production never passes this.
  final Duration requestTimeout;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (bearerToken != null) 'authorization': 'Bearer $bearerToken',
  };

  /// Flush pending local notes/tags, then pull remote deltas.
  @override
  Future<SyncResult> sync() async {
    final pendingNotes = repo.listPending(includeDeleted: true);
    // The outbox, not the whole table. Pushing every tag on every sync meant
    // one server upsert per tag per sync, each minting a new sequence, which
    // put all of them above every peer's cursor and made each sync broadcast
    // the entire tag table to every other device on the account.
    final pendingTags = repo.listPendingTags();

    // One request per batch, capped to what the server accepts. Notes and
    // tags are chunked independently and paired off by index: most outboxes
    // are almost entirely notes, so this keeps the common case at one
    // request without leaving a large tag backlog uncovered on its own.
    final noteBatches = _chunked(pendingNotes, _pushBatchSize);
    final tagBatches = _chunked(pendingTags, _pushBatchSize);
    final batchCount = noteBatches.length > tagBatches.length
        ? noteBatches.length
        : tagBatches.length;

    final merged = <MergedNote>[];
    final tagRemap = <TagRemapEntry>[];
    final mediaDeduped = <String>[];
    for (var i = 0; i < (batchCount == 0 ? 1 : batchCount); i++) {
      final push = await _push(
        notes: i < noteBatches.length ? noteBatches[i] : const [],
        tags: i < tagBatches.length ? tagBatches[i] : const [],
      );
      merged.addAll(push.merged);
      tagRemap.addAll(push.tagRemap);
      mediaDeduped.addAll(push.mediaDeduped);
    }

    // Only what the server acknowledged leaves the outbox. It reports a write
    // it refused as stale by omitting the id, and that signal used to be
    // ignored: every pending note was marked synced regardless, so the exact
    // case the outbox exists for — an offline edit that lost a race — was the
    // one that silently discarded the edit.
    final accepted = {for (final m in merged) m.id: m.rev};
    for (final note in pendingNotes) {
      final rev = accepted[note.id];
      if (rev == null) continue; // rejected — stays pending, retried next cycle
      repo.markSynced(note.id, serverRev: rev);
    }

    // Fold this device's tag ids into the server's canonical ones before the
    // pull, so the note↔tag joins arriving below resolve against rows that
    // exist locally.
    if (tagRemap.isNotEmpty) repo.applyTagRemap(tagRemap);
    final remapped = {for (final entry in tagRemap) entry.clientId};
    repo.markTagsSynced([
      for (final tag in pendingTags)
        if (!remapped.contains(tag.id)) tag.id,
    ]);

    var pulled = 0;
    var pages = 0;
    // Drain, rather than fetch one page and stop. The server paginates at
    // SYNC_PAGE_SIZE and says so in `has_more`; the client used to issue
    // exactly one GET, so any change set above a page — a first sync, a
    // restore, a long offline period — left the device with a partial view.
    while (true) {
      final page = await _pull();
      _applyPage(page);
      pulled += page.notes.length;
      // Persisted, not just held in a field: an in-memory watermark restarts
      // from zero on every cold launch even when the field name is right.
      repo.syncCursor = page.cursor;
      if (!page.hasMore) break;
      if (++pages > _maxPages) {
        throw StateError(
          'sync pull: cursor failed to advance after $pages pages',
        );
      }
    }

    return SyncResult(
      pushed: accepted.length,
      pulled: pulled,
      mergedIds: merged.map((m) => m.id).toList(),
      mediaDeduped: mediaDeduped,
    );
  }

  Future<PushResponse> _push({
    required List<Note> notes,
    required List<Tag> tags,
  }) async {
    final pushBody = {
      'device_id': deviceId,
      'tags': tags.map((t) => t.toJson()).toList(),
      'notes': notes.map(_notePayload).toList(),
    };
    final pushRes = await _http
        .post(
          Uri.parse('$baseUrl/sync/push'),
          headers: _headers,
          body: jsonEncode(pushBody),
        )
        .timeout(requestTimeout);
    if (pushRes.statusCode >= 300) {
      throw StateError(
        'sync push failed: ${pushRes.statusCode} ${pushRes.body}',
      );
    }
    return PushResponse.fromJson(
      jsonDecode(pushRes.body) as Map<String, dynamic>,
    );
  }

  static List<List<T>> _chunked<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    return [
      for (var i = 0; i < items.length; i += size)
        items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
  }

  Future<PullPage> _pull() async {
    final since = repo.syncCursor;
    final uri = Uri.parse('$baseUrl/sync/pull').replace(
      queryParameters: {
        'device_id': deviceId,
        if (since != null) 'since': since,
      },
    );
    final res = await _http.get(uri, headers: _headers).timeout(requestTimeout);
    if (res.statusCode >= 300) {
      throw StateError('sync pull failed: ${res.statusCode} ${res.body}');
    }
    return PullPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  void _applyPage(PullPage page) {
    // Atomic: the cursor that records this page is written right after this
    // returns, so a page that half-applied and then threw used to wedge sync
    // forever — every retry re-failed on the same page, at the same note,
    // with the cursor never moving past it. Now the whole page lands or the
    // error propagates with nothing on disk half-done.
    final db = repo.db;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final t in page.tags) {
        repo.upsertTagFromSync(
          id: t['id'] as String,
          name: t['name'] as String,
          color: t['color'] as String?,
          createdAt: DateTime.parse(t['created_at'] as String).toUtc(),
        );
      }

      for (final n in page.notes) {
        final tagIds = (n['tag_ids'] as List?)?.cast<String>() ?? const [];
        repo.applyRemoteNote(
          id: n['id'] as String,
          type: NoteType.fromWire(n['type'] as String),
          content: n['content'] as String?,
          mediaUri: n['media_uri'] as String?,
          mediaHash: n['media_hash'] as String?,
          durationMs: n['duration_ms'] as int?,
          createdAt: DateTime.parse(n['created_at'] as String).toUtc(),
          updatedAt: DateTime.parse(n['updated_at'] as String).toUtc(),
          deletedAt: n['deleted_at'] != null
              ? DateTime.parse(n['deleted_at'] as String).toUtc()
              : null,
          deviceId: n['device_id'] as String,
          rev: n['rev'] as int,
          tagIds: tagIds,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, Object?> _notePayload(Note note) => {
    'id': note.id,
    'type': note.type.wireName,
    'content': note.content,
    'media_uri': note.mediaUri,
    'media_hash': note.mediaHash,
    'duration_ms': note.durationMs,
    'created_at': note.createdAt.toUtc().toIso8601String(),
    'updated_at': note.updatedAt.toUtc().toIso8601String(),
    'deleted_at': note.deletedAt?.toUtc().toIso8601String(),
    'device_id': note.deviceId,
    'rev': note.rev,
    'tags': note.tags.map((t) => t.toJson()).toList(),
  };

  @override
  void close() => _http.close();
}
