import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nex_core/nex_core.dart';

import '../repositories/note_repository.dart';

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

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (bearerToken != null) 'authorization': 'Bearer $bearerToken',
      };

  String? _lastPullWatermark;

  /// Flush pending local notes/tags, then pull remote deltas.
  @override
  Future<SyncResult> sync() async {
    final pendingNotes = repo.listPending(includeDeleted: true);
    final tags = repo.listTags();

    final pushBody = {
      'device_id': deviceId,
      'tags': tags.map((t) => t.toJson()).toList(),
      'notes': pendingNotes.map(_notePayload).toList(),
    };

    final pushRes = await _http.post(
      Uri.parse('$baseUrl/sync/push'),
      headers: _headers,
      body: jsonEncode(pushBody),
    );
    if (pushRes.statusCode >= 300) {
      throw StateError('sync push failed: ${pushRes.statusCode} ${pushRes.body}');
    }
    final pushJson = jsonDecode(pushRes.body) as Map<String, dynamic>;

    for (final note in pendingNotes) {
      // Tombstones must leave the outbox too once the server has them.
      repo.markSynced(note.id);
    }

    final pullUri = Uri.parse('$baseUrl/sync/pull').replace(
      queryParameters: {
        'device_id': deviceId,
        if (_lastPullWatermark != null) 'since': _lastPullWatermark!,
      },
    );
    final pullRes = await _http.get(pullUri, headers: _headers);
    if (pullRes.statusCode >= 300) {
      throw StateError('sync pull failed: ${pullRes.statusCode} ${pullRes.body}');
    }
    final pullJson = jsonDecode(pullRes.body) as Map<String, dynamic>;
    _lastPullWatermark = pullJson['server_time'] as String?;

    final remoteNotes = (pullJson['notes'] as List).cast<Map<String, dynamic>>();
    final remoteTags = (pullJson['tags'] as List).cast<Map<String, dynamic>>();

    for (final t in remoteTags) {
      repo.upsertTagFromSync(
        id: t['id'] as String,
        name: t['name'] as String,
        color: t['color'] as String?,
        createdAt: DateTime.parse(t['created_at'] as String).toUtc(),
      );
    }

    for (final n in remoteNotes) {
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

    return SyncResult(
      pushed: pendingNotes.length,
      pulled: remoteNotes.length,
      mergedIds: ((pushJson['merged_ids'] as List?) ?? const [])
          .cast<String>(),
      mediaDeduped: ((pushJson['media_deduped'] as List?) ?? const [])
          .cast<String>(),
    );
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
