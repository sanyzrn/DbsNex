import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
// nex_core also exports a MergedNote (the field-aware merger's server-side
// result type) — unrelated to sync_wire's wire-level typedef of the same
// name, and unused here, so it's hidden rather than left to collide.
import 'package:nex_core/nex_core.dart' hide MergedNote;
import 'package:path/path.dart' as p;

import '../repositories/note_repository.dart';
import '../schema/write_lock.dart';
import 'sync_wire.dart';

/// HTTP sync client — push outbox, pull deltas (04-architecture.md).
///
/// Conflict resolution is performed on the server (field-aware). The client
/// applies the pull set as the remote truth for synced rows.
///
/// One cycle, in order:
///
/// 1. Media upload — the bytes behind hashes the server may not have, so
///    they are on it before the notes referencing them arrive.
/// 2. Push — the outbox, batched to what the server accepts per request.
/// 3. Pull — drain every page past the persisted cursor, then fetch the
///    media of notes whose bytes this device does not hold.
///
/// Push still precedes pull: a behind-the-server revision must reach the
/// server's merger *before* this device sees the newer row, or the local
/// edit would be forked aside by [SqliteNoteRepository.applyRemoteNote]
/// instead of merged into one note. A push that fails without timing out
/// does not stop the pull — a device whose outbox carries one item the
/// server refuses must not stop *receiving* over it.
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
    this.mediaDir,
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

  /// Where this device keeps media files. When set, the cycle uploads the
  /// bytes behind hashes the server may not have and downloads the bytes
  /// behind hashes it pulled; when null (tests, and any host without a media
  /// tree) notes sync with their hashes and the media is simply never
  /// fetched.
  final String? mediaDir;

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

  /// A byte budget per push request, under the route's 2 MB body limit.
  ///
  /// The item cap alone did not bound the payload: a note's content has no
  /// length limit, so 500 ordinary notes fit in a few hundred kilobytes while
  /// 500 long ones overflowed the route and 400'd the whole batch — the same
  /// wedge the item cap exists to prevent, reached by size instead of count.
  static const _pushBatchBytes = 512 * 1024;

  /// Media objects one cycle will move in either direction.
  ///
  /// A first sync of a media-heavy library can reference thousands of
  /// hashes; moving them all in one cycle would park the database worker
  /// behind minutes of transfers. The remainder is picked up by the next
  /// cycle — both loops key on "hashes the other side may not have", not on
  /// which notes are pending.
  static const _maxMediaPerCycle = 10;

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

  /// The same authentication, for a body that is bytes rather than JSON.
  Map<String, String> get _octetHeaders => {
    'content-type': 'application/octet-stream',
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

    // Bytes before metadata: a peer that pulls a note whose hash it cannot
    // fetch has a card with nothing in it. A failure here holds nothing back
    // — the note still pushes, and the upload is retried next cycle against
    // the same "hashes the server may not have" query.
    await _uploadMissingMedia();

    final merged = <MergedNote>[];
    final tagRemap = <TagRemapEntry>[];
    final mediaDeduped = <String>[];
    final rejected = <String>[];
    final mediaWanted = <String>{};

    // Set when the push was refused without the network being the reason.
    // Thrown *after* the pull, so a poisoned outbox entry costs the device
    // its sending but never its receiving.
    (Object, StackTrace)? pushFailure;

    // An empty outbox skips the push entirely: the request it used to send
    // was harmless but pointless, and its response — "merged: []" — made the
    // idle cycle look indistinguishable from a refused one on the wire.
    if (pendingNotes.isNotEmpty || pendingTags.isNotEmpty) {
      final noteBatches = _chunkedByBytes(pendingNotes);
      final tagBatches = _chunked(pendingTags, _pushBatchSize);
      final batchCount = noteBatches.length > tagBatches.length
          ? noteBatches.length
          : tagBatches.length;

      // Notes and tags are chunked independently and paired off by index:
      // most outboxes are almost entirely notes, so this keeps the common
      // case at one request without leaving a large tag backlog uncovered on
      // its own.
      try {
        for (var i = 0; i < batchCount; i++) {
          final push = await _push(
            notes: i < noteBatches.length ? noteBatches[i] : const [],
            tags: i < tagBatches.length ? tagBatches[i] : const [],
          );
          merged.addAll(push.merged);
          tagRemap.addAll(push.tagRemap);
          mediaDeduped.addAll(push.mediaDeduped);
          rejected.addAll(push.rejected);
          mediaWanted.addAll(push.mediaWanted);
        }
      } on TimeoutException {
        // The network is not answering. A pull behind this would only double
        // how long the database worker — which runs one command at a time —
        // sits blocked behind this cycle, with the same nothing to show.
        rethrow;
      } on SocketException {
        rethrow;
      } catch (error, stack) {
        // The server spoke and said no (a status, a body it should not have,
        // a contract it broke). That says nothing about the pull, and a
        // device with a poisoned outbox entry must not stop receiving over
        // it: the pull below still runs, then the push failure is rethrown
        // so the caller reports the outbox, not a phantom success.
        pushFailure = (error, stack);
      }

      // Only what the server acknowledged leaves the outbox. It reports a
      // write it refused as stale by omitting the id, and that signal used to
      // be ignored: every pending note was marked synced regardless, so the
      // exact case the outbox exists for — an offline edit that lost a race —
      // was the one that silently discarded the edit.
      final accepted = {for (final m in merged) m.id: m.rev};
      for (final note in pendingNotes) {
        final rev = accepted[note.id];
        // Rejected: stays pending, retried next cycle.
        if (rev == null) continue;
        // Compare the pushed snapshot in SQL: a newer edit made during the
        // request stays pending, without an extra note/tag read per ack.
        repo.markSynced(note.id, serverRev: rev, expected: note);
      }

      // Fold this device's tag ids into the server's canonical ones before the
      // pull, so the note↔tag joins arriving below resolve against rows that
      // exist locally.
      final pushedTags = {for (final tag in pendingTags) tag.id: tag};
      final dirtyTags = {
        for (final tag in repo.listPendingTags())
          if (pushedTags[tag.id] case final old?)
            if (old.name != tag.name || old.color != tag.color) tag.id,
      };
      if (tagRemap.isNotEmpty) {
        repo.applyTagRemap([
          for (final pair in tagRemap)
            if (!dirtyTags.contains(pair.clientId)) pair,
        ]);
      }
      final remapped = {for (final entry in tagRemap) entry.clientId};
      repo.markTagsSynced([
        for (final tag in pendingTags)
          if (!remapped.contains(tag.id)) tag.id,
      ], expected: pushedTags);
    }

    // The server looked at its own disk and named the hashes it lacks the
    // bytes for. That outranks this device's "already sent" cache — the case
    // it exists for is exactly the one the cache cannot see (the object was
    // lost while the row lived on) — so these are uploaded even when the
    // cache says otherwise.
    await _uploadWantedMedia(mediaWanted);

    var pulled = 0;
    var pages = 0;
    var skippedUnknownTypes = 0;
    // Drain, rather than fetch one page and stop. The server paginates at
    // SYNC_PAGE_SIZE and says so in `has_more`; the client used to issue
    // exactly one GET, so any change set above a page — a first sync, a
    // restore, a long offline period — left the device with a partial view.
    while (true) {
      final page = await _pull();
      skippedUnknownTypes += _applyPage(page);
      pulled += page.notes.length;
      // Persisted, not just held in a field: an in-memory watermark restarts
      // from zero on every cold launch even when the field name is right.
      repo.syncCursor = page.cursor;
      await _fetchMissingMedia(page);
      if (!page.hasMore) break;
      if (++pages > _maxPages) {
        throw StateError(
          'sync pull: cursor failed to advance after $pages pages',
        );
      }
    }

    // The push failure surfaces only now, with the pull banked: the cycle's
    // job is to leave this device as current as the server can make it, and
    // a caller that swallows the error still got the receiving half done.
    if (pushFailure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }

    return SyncResult(
      pushed: merged.length,
      pulled: pulled,
      mergedIds: merged.map((m) => m.id).toList(),
      mediaDeduped: mediaDeduped,
      rejected: rejected,
      skippedUnknownTypes: skippedUnknownTypes,
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

  /// Batches notes by count *and* encoded size — see [_pushBatchBytes].
  ///
  /// Each payload is measured as the UTF-8 bytes it will actually occupy on
  /// the wire, not as Dart string length: a page of Persian notes is twice
  /// its `String.length` in bytes, and a budget checked in code units would
  /// let exactly the overflow it exists to prevent through.
  List<List<Note>> _chunkedByBytes(List<Note> notes) {
    final batches = <List<Note>>[];
    var current = <Note>[];
    var bytes = 0;
    for (final note in notes) {
      final size = utf8.encode(jsonEncode(_notePayload(note))).length;
      if (current.isNotEmpty &&
          (current.length >= _pushBatchSize ||
              bytes + size > _pushBatchBytes)) {
        batches.add(current);
        current = <Note>[];
        bytes = 0;
      }
      current.add(note);
      bytes += size;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
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
    final uri = Uri.parse('$baseUrl/sync/pull')
        .replace(queryParameters: {'device_id': deviceId, 'since': ?since});
    final res = await _http.get(uri, headers: _headers).timeout(requestTimeout);
    if (res.statusCode >= 300) {
      throw StateError('sync pull failed: ${res.statusCode} ${res.body}');
    }
    return PullPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Applies one page. Returns how many notes were skipped as carrying a
  /// type this build does not know.
  int _applyPage(PullPage page) {
    // Atomic: the cursor that records this page is written right after this
    // returns, so a page that half-applied and then threw used to wedge sync
    // forever — every retry re-failed on the same page, at the same note,
    // with the cursor never moving past it. Now the whole page lands or the
    // error propagates with nothing on disk half-done.
    var skippedUnknownTypes = 0;
    final db = repo.db;
    db.beginImmediate();
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
        // A type this build cannot name is skipped, not thrown: `fromWire`
        // used to abort the whole page transaction, which rolled the cursor
        // back with it, and one note from a newer peer wedged every later
        // sync behind it. The note stays on the server and on the devices
        // that do know the type; the count comes back in the SyncResult so
        // the services layer can say it happened.
        final NoteType type;
        try {
          type = NoteType.fromWire(n['type'] as String);
        } on ArgumentError {
          skippedUnknownTypes++;
          continue;
        }
        final tagIds = (n['tag_ids'] as List?)?.cast<String>() ?? const [];
        repo.applyRemoteNote(
          id: n['id'] as String,
          type: type,
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
    return skippedUnknownTypes;
  }

  /* --------------------------------------------------------------- media */

  /// Uploads the bytes behind hashes the server may not have.
  ///
  /// A media note's push carries its hash and a portable file name — never
  /// this device's filesystem layout — and the bytes go up separately, once
  /// per hash. A file whose contents no longer match the hash beside it is
  /// skipped: the address is the content, and uploading anything else under
  /// it would poison every note that references the hash, on every device.
  Future<void> _uploadMissingMedia() async {
    if (mediaDir == null) return;
    final moved = <String>{};
    for (final ref in repo.mediaReferencesNeedingUpload(
      limit: _maxMediaPerCycle * 3,
    )) {
      if (moved.length >= _maxMediaPerCycle) break;
      // The same hash can sit under several notes' paths; one good copy is
      // all the server ever needs.
      if (moved.contains(ref.hash)) continue;
      if (await _uploadHash(ref.hash, candidates: [ref.localPath])) {
        moved.add(ref.hash);
      }
    }
  }

  /// The server-named half of the upload: hashes it explicitly lacks.
  Future<void> _uploadWantedMedia(Set<String> hashes) async {
    if (mediaDir == null || hashes.isEmpty) return;
    for (final hash in hashes.take(_maxMediaPerCycle)) {
      await _uploadHash(hash, candidates: repo.mediaLocalPaths(hash));
    }
  }

  /// Puts one hash's bytes on the server, trying [candidates] in order until
  /// one is a file whose contents hash to [hash] itself.
  Future<bool> _uploadHash(
    String hash, {
    required List<String> candidates,
  }) async {
    try {
      for (final path in candidates) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        if (sha256OfBytes(bytes) != hash) continue;
        final res = await _http
            .put(
              Uri.parse('$baseUrl/sync/media/$hash'),
              headers: _octetHeaders,
              body: bytes,
            )
            .timeout(requestTimeout);
        // 404 is an older server without the media routes; anything else is a
        // real answer, and only success marks the hash as held.
        if (res.statusCode >= 200 && res.statusCode < 300) {
          repo.markMediaSynced(hash);
          return true;
        }
      }
    } catch (_) {
      // A failed upload is retried by the next cycle against the same
      // query. Nothing here may stop the notes themselves from syncing.
    }
    return false;
  }

  /// Fetches the bytes behind hashes a pulled page referenced but this device
  /// does not hold, then rewrites those notes to point at the local files.
  Future<void> _fetchMissingMedia(PullPage page) async {
    if (mediaDir == null) return;
    var moved = 0;
    for (final n in page.notes) {
      if (moved >= _maxMediaPerCycle) break;
      final hash = n['media_hash'] as String?;
      if (hash == null) continue;
      if (n['deleted_at'] != null) continue; // tombstones carry no media
      final id = n['id'] as String;
      if (!repo.noteNeedsMediaFetch(id)) continue;

      try {
        final res = await _http
            .get(Uri.parse('$baseUrl/sync/media/$hash'), headers: _headers)
            .timeout(requestTimeout);
        if (res.statusCode == 404) {
          // The server does not have these bytes either. Whatever this
          // device's cache says, it is stale now: dropping the mark lets the
          // next cycle's upload pass try again from any device that holds
          // the file — including this one.
          repo.forgetMediaSynced(hash);
          continue;
        }
        if (res.statusCode != 200) continue;
        final bytes = res.bodyBytes;
        // The hash is the address; anything that arrives under it but is not
        // it is discarded rather than written into the media tree.
        if (sha256OfBytes(bytes) != hash) continue;
        final extension = p.extension(n['media_uri'] as String? ?? '');
        final suffix = RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)
            ? extension
            : '';
        final target = File(p.join(mediaDir!, '${newUuidV7()}$suffix'));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
        repo.rewriteNoteMedia(id, target.path, markHeld: true);
        moved++;
      } catch (_) {
        // The note is already applied with its hash; its bytes are retried by
        // the next cycle's pass, which looks at what is missing locally.
        continue;
      }
    }
  }

  Map<String, Object?> _notePayload(Note note) => {
    'id': note.id,
    'type': note.type.wireName,
    'content': note.content,
    // A portable name, not this device's path: the wire used to carry the
    // author's absolute filesystem layout to the server and every peer —
    // a directory structure is nobody else's business, and a foreign path
    // is dead on arrival anyway. The hash is the identity; the name only
    // keeps the extension so a peer can file the bytes it fetches.
    'media_uri': note.mediaUri == null ? null : p.basename(note.mediaUri!),
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
