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
    final pushRes = await _http.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers,
      body: jsonEncode(pushBody),
    );
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
    final res = await _http.get(uri, headers: _headers);
    if (res.statusCode >= 300) {
      throw StateError('sync pull failed: ${res.statusCode} ${res.body}');
    }
    return PullPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  void _applyPage(PullPage page) {
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
