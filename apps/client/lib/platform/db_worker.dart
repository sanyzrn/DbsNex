import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';

/// Commands the worker isolate understands.
///
/// package:sqlite3 is a synchronous FFI binding: every call blocks the calling
/// isolate for the whole query. Running it on the UI isolate — which is what
/// the composition root used to do, including a full database file copy on
/// every launch — directly violates the product's one non-negotiable principle.
///
/// The domain services live in here too, not on the UI isolate. They take the
/// synchronous [NoteRepository] port, so this is the only isolate that can hold
/// them. That includes [EnrichmentService]: AI work is exactly what must not
/// run on the UI thread (09-ai.md).
enum _DbCommand {
  timeline,
  loadMore,
  search,
  getById,
  captureText,
  captureVoice,
  capturePhoto,
  captureFile,
  updateNote,
  deleteNote,
  undelete,
  setCaption,
  addTag,
  removeTag,
  listTags,
  setTagColor,
  backup,
  exportArchive,
  // Library maintenance (trash, tag manager, storage breakdown).
  deletedNotes,
  purgeDeletedBefore,
  tagUsage,
  renameTag,
  mergeTag,
  deleteTag,
  anniversary,
  nearestMiss,
  storage,
  // Enrichment.
  enrichNote,
  suggestTags,
  summarize,
  relatedNotes,
  setAiCapabilities,
  sync,
  close,
}

class _DbRequest {
  const _DbRequest(this.id, this.command, this.args);

  final int id;
  final _DbCommand command;
  final Map<String, Object?> args;
}

class _DbResponse {
  const _DbResponse(this.id, this.value, this.error, this.stack);

  final int id;
  final Object? value;
  final Object? error;
  final String? stack;
}

class _WorkerBoot {
  const _WorkerBoot(
    this.sendPort,
    this.dbPath,
    this.deviceId,
    this.adapter,
    this.capabilities,
  );

  final SendPort sendPort;
  final String dbPath;
  final String deviceId;

  /// Must be isolate-sendable: pure Dart, no platform channels. The adapters in
  /// packages/core (`NullAIAdapter`, `OnDeviceAIAdapter`) are const and satisfy
  /// this; a plugin-backed adapter would not.
  final AIAdapter adapter;
  final AiCapabilities capabilities;
}

/// Async facade over a dedicated database isolate.
///
/// The UI isolate never touches sqlite3 directly; it sends a command and awaits
/// a reply, so no query can block a frame.
class NexDbWorker {
  NexDbWorker._(
    this._isolate,
    this._toWorker,
    this._responses,
    Stream<dynamic> incoming,
  ) {
    _subscription = incoming.listen(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _responses;

  late final StreamSubscription<dynamic> _subscription;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  static Future<NexDbWorker> spawn({
    required String dbPath,
    required String deviceId,
    AIAdapter adapter = const NullAIAdapter(),
    AiCapabilities capabilities = const AiCapabilities(),
  }) async {
    final responses = ReceivePort();
    final incoming = responses.asBroadcastStream();
    final ready = Completer<SendPort>();

    late final StreamSubscription<dynamic> bootstrap;
    bootstrap = incoming.listen((message) {
      if (message is SendPort && !ready.isCompleted) {
        ready.complete(message);
        bootstrap.cancel();
      }
    });

    final isolate = await Isolate.spawn(
      _entryPoint,
      _WorkerBoot(
        responses.sendPort,
        dbPath,
        deviceId,
        adapter,
        capabilities,
      ),
      debugName: 'nex-db',
    );

    final toWorker = await ready.future;
    return NexDbWorker._(isolate, toWorker, responses, incoming);
  }

  void _onMessage(dynamic message) {
    if (message is! _DbResponse) return;

    final completer = _pending.remove(message.id);
    if (completer == null) return;

    if (message.error != null) {
      completer.completeError(
        StateError('nex-db worker failed: ${message.error}'),
        StackTrace.fromString(message.stack ?? ''),
      );
    } else {
      completer.complete(message.value);
    }
  }

  Future<T> _send<T>(
    _DbCommand command, [
    Map<String, Object?> args = const {},
  ]) {
    if (_closed) throw StateError('NexDbWorker has been closed');

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _toWorker.send(_DbRequest(id, command, args));
    return completer.future.then((value) => value as T);
  }

  /* ------------------------------------------------------------- reading */

  Future<List<Note>> timeline({int limit = 200, int offset = 0, String? tagId}) =>
      _send<List<Note>>(_DbCommand.timeline, {
        'limit': limit,
        'offset': offset,
        'tagId': tagId,
      });

  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      _send<List<Note>>(_DbCommand.loadMore, {'limit': limit, 'offset': offset});

  Future<List<Note>> search(SearchFilters filters) =>
      _send<List<Note>>(_DbCommand.search, {'filters': filters});

  Future<Note?> getById(String id) =>
      _send<Note?>(_DbCommand.getById, {'id': id});

  /* ------------------------------------------------------------ capturing */

  Future<Note?> captureText(String content) =>
      _send<Note?>(_DbCommand.captureText, {'content': content});

  Future<Note> captureVoice({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  }) =>
      _send<Note>(_DbCommand.captureVoice, {
        'mediaUri': mediaUri,
        'mediaBytes': mediaBytes,
        'durationMs': durationMs,
      });

  Future<Note> capturePhoto({
    required String mediaUri,
    required Uint8List mediaBytes,
  }) =>
      _send<Note>(_DbCommand.capturePhoto, {
        'mediaUri': mediaUri,
        'mediaBytes': mediaBytes,
      });

  Future<Note> captureFile({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  }) =>
      _send<Note>(_DbCommand.captureFile, {
        'mediaUri': mediaUri,
        'mediaBytes': mediaBytes,
        'originalFilename': originalFilename,
        'mimeType': mimeType,
      });

  /* ------------------------------------------------------------- mutating */

  Future<void> updateNote(String id, String content) =>
      _send<void>(_DbCommand.updateNote, {'id': id, 'content': content});

  Future<void> deleteNote(String id) =>
      _send<void>(_DbCommand.deleteNote, {'id': id});

  Future<void> undelete(String id) =>
      _send<void>(_DbCommand.undelete, {'id': id});

  Future<void> setCaption(String id, String caption) =>
      _send<void>(_DbCommand.setCaption, {'id': id, 'caption': caption});

  /* ----------------------------------------------------------------- tags */

  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) =>
      _send<Tag>(_DbCommand.addTag, {
        'noteId': noteId,
        'name': name,
        'color': color,
      });

  Future<void> removeTag({required String noteId, required String tagId}) =>
      _send<void>(_DbCommand.removeTag, {'noteId': noteId, 'tagId': tagId});

  Future<List<Tag>> listTags() => _send<List<Tag>>(_DbCommand.listTags);

  Future<void> setTagColor({required String tagId, String? color}) =>
      _send<void>(_DbCommand.setTagColor, {'tagId': tagId, 'color': color});

  /* ------------------------------------------------------ backup / export */

  Future<void> backup(String backupDir) =>
      _send<void>(_DbCommand.backup, {'dir': backupDir});

  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) =>
      _send<String>(_DbCommand.exportArchive, {
        'outputPath': outputPath,
        'mediaRoot': mediaRoot,
      });

  /* --------------------------------------------------- library maintenance */

  Future<List<Note>> deletedNotes({int limit = 200}) =>
      _send<List<Note>>(_DbCommand.deletedNotes, {'limit': limit});

  Future<void> purgeDeletedBefore(DateTime cutoff) =>
      _send<void>(_DbCommand.purgeDeletedBefore, {'cutoff': cutoff});

  Future<List<TagUsage>> tagUsage() =>
      _send<List<TagUsage>>(_DbCommand.tagUsage);

  Future<void> renameTag(String id, String name) =>
      _send<void>(_DbCommand.renameTag, {'id': id, 'name': name});

  Future<void> mergeTag({
    required String sourceId,
    required String targetId,
  }) =>
      _send<void>(_DbCommand.mergeTag, {
        'sourceId': sourceId,
        'targetId': targetId,
      });

  Future<void> deleteTag(String id) =>
      _send<void>(_DbCommand.deleteTag, {'id': id});

  Future<List<Note>> anniversary(DateTime now) =>
      _send<List<Note>>(_DbCommand.anniversary, {'now': now});

  Future<Note?> nearestMiss(String query) =>
      _send<Note?>(_DbCommand.nearestMiss, {'query': query});

  Future<StorageSnapshot> storage({
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) =>
      _send<StorageSnapshot>(_DbCommand.storage, {
        'dbPath': dbPath,
        'mediaDir': mediaDir,
        'backupDir': backupDir,
      });

  /* ----------------------------------------------------------- enrichment */

  Future<void> enrichNote(String noteId) =>
      _send<void>(_DbCommand.enrichNote, {'noteId': noteId});

  Future<List<TagSuggestion>> suggestTags(String noteId) =>
      _send<List<TagSuggestion>>(_DbCommand.suggestTags, {'noteId': noteId});

  Future<Summary?> summarizeOnDemand(String noteId) =>
      _send<Summary?>(_DbCommand.summarize, {'noteId': noteId});

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      _send<List<SemanticHit>>(_DbCommand.relatedNotes, {
        'noteId': noteId,
        'limit': limit,
      });

  Future<void> setAiCapabilities(AiCapabilities capabilities) =>
      _send<void>(_DbCommand.setAiCapabilities, {'capabilities': capabilities});

  /// One sync cycle.
  ///
  /// SyncClient needs the concrete repository — the outbox surface the port
  /// deliberately withholds — so it is built here, inside the isolate that owns
  /// it, rather than on the UI isolate where it has nothing to talk to.
  Future<SyncResult> sync({
    required String baseUrl,
    String? bearerToken,
  }) =>
      _send<SyncResult>(_DbCommand.sync, {
        'baseUrl': baseUrl,
        'bearerToken': bearerToken,
      });

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      await _send<void>(_DbCommand.close);
    } catch (_) {
      // The isolate may already be gone; teardown must never throw.
    }

    await _subscription.cancel();
    _responses.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  /* -------------------------------------------------------- worker side */

  /// Runs a `void` operation and yields a value the switch expression can use.
  static Object? _voided(void Function() operation) {
    operation();
    return null;
  }

  static void _entryPoint(_WorkerBoot boot) {
    final requests = ReceivePort();
    boot.sendPort.send(requests.sendPort);

    final db = NexDatabase.open(boot.dbPath);
    final repo = SqliteNoteRepository(db, localDeviceId: boot.deviceId);
    final capture = CaptureService(repo, deviceId: boot.deviceId);
    final tags = TagService(repo);
    final search = SearchService(repo);
    final maintenance = LibraryMaintenance(repo);
    final enrichment = EnrichmentService(
      repo: repo,
      adapter: boot.adapter,
      capabilities: boot.capabilities,
    );

    // The handler is asynchronous because several operations are: exportArchive
    // and storage return Futures, and a Future cannot cross a SendPort — the
    // previous synchronous handler sent the Future itself and the awaiting side
    // hung or cast-failed.
    requests.listen((message) async {
      if (message is! _DbRequest) return;

      Object? arg(String key) => message.args[key];

      try {
        final Object? result = switch (message.command) {
          _DbCommand.timeline || _DbCommand.loadMore => search.timeline(
              limit: arg('limit')! as int,
              offset: arg('offset')! as int,
              tagId: arg('tagId') as String?,
            ),
          _DbCommand.search => search.search(arg('filters')! as SearchFilters),
          _DbCommand.getById => repo.getById(arg('id')! as String),
          _DbCommand.captureText =>
            capture.submitTextCapture(arg('content')! as String),
          _DbCommand.captureVoice => capture.submitVoiceCapture(
              mediaUri: arg('mediaUri')! as String,
              mediaBytes: arg('mediaBytes')! as Uint8List,
              durationMs: arg('durationMs')! as int,
            ),
          _DbCommand.capturePhoto => capture.submitPhotoCapture(
              mediaUri: arg('mediaUri')! as String,
              mediaBytes: arg('mediaBytes')! as Uint8List,
            ),
          _DbCommand.captureFile => capture.submitFileCapture(
              mediaUri: arg('mediaUri')! as String,
              mediaBytes: arg('mediaBytes')! as Uint8List,
              originalFilename: arg('originalFilename') as String?,
              mimeType: arg('mimeType') as String?,
            ),
          _DbCommand.updateNote => _voided(() => repo.updateContent(
                arg('id')! as String,
                arg('content')! as String,
              )),
          _DbCommand.deleteNote =>
            _voided(() => repo.softDelete(arg('id')! as String)),
          _DbCommand.undelete =>
            _voided(() => repo.undelete(arg('id')! as String)),
          _DbCommand.setCaption => _voided(() => repo.setCaption(
                arg('id')! as String,
                arg('caption')! as String,
              )),
          _DbCommand.addTag => tags.addTag(
              noteId: arg('noteId')! as String,
              name: arg('name')! as String,
              color: arg('color') as String?,
            ),
          _DbCommand.removeTag => _voided(() => tags.removeTag(
                noteId: arg('noteId')! as String,
                tagId: arg('tagId')! as String,
              )),
          _DbCommand.listTags => tags.listTags(),
          _DbCommand.setTagColor => _voided(() => tags.setColor(
                tagId: arg('tagId')! as String,
                color: arg('color') as String?,
              )),
          _DbCommand.backup => repo.backup(arg('dir')! as String),
          _DbCommand.exportArchive =>
            (await repo.exportArchive(
              outputPath: arg('outputPath')! as String,
              mediaRoot: arg('mediaRoot')! as String,
            ))
                .path,
          _DbCommand.deletedNotes =>
            maintenance.deletedNotes(limit: arg('limit')! as int),
          _DbCommand.purgeDeletedBefore => _voided(
              () => maintenance.purgeDeletedBefore(arg('cutoff')! as DateTime)),
          _DbCommand.tagUsage => maintenance.tagUsage(),
          _DbCommand.renameTag => _voided(() => maintenance.renameTag(
                arg('id')! as String,
                arg('name')! as String,
              )),
          _DbCommand.mergeTag => _voided(() => maintenance.mergeTag(
                sourceId: arg('sourceId')! as String,
                targetId: arg('targetId')! as String,
              )),
          _DbCommand.deleteTag =>
            _voided(() => maintenance.deleteTag(arg('id')! as String)),
          _DbCommand.anniversary =>
            maintenance.anniversary(arg('now')! as DateTime),
          _DbCommand.nearestMiss =>
            maintenance.nearestMiss(arg('query')! as String),
          _DbCommand.storage => await maintenance.storage(
              arg('dbPath')! as String,
              arg('mediaDir')! as String,
              arg('backupDir')! as String,
            ),
          _DbCommand.enrichNote => await enrichment
              .enrichNote(arg('noteId')! as String)
              .then<Object?>((_) => null),
          _DbCommand.suggestTags =>
            await enrichment.suggestTags(arg('noteId')! as String),
          _DbCommand.summarize =>
            await enrichment.summarizeOnDemand(arg('noteId')! as String),
          _DbCommand.relatedNotes => await enrichment.relatedNotes(
              arg('noteId')! as String,
              limit: arg('limit')! as int,
            ),
          _DbCommand.setAiCapabilities => _voided(() => enrichment
              .updateCapabilities(arg('capabilities')! as AiCapabilities)),
          _DbCommand.sync => await () async {
              final client = SyncClient(
                baseUrl: arg('baseUrl')! as String,
                deviceId: boot.deviceId,
                repo: repo,
                bearerToken: arg('bearerToken') as String?,
              );
              try {
                return await client.sync();
              } finally {
                client.close();
              }
            }(),
          _DbCommand.close => null,
        };

        boot.sendPort.send(_DbResponse(message.id, result, null, null));

        if (message.command == _DbCommand.close) {
          db.close();
          requests.close();
        }
      } catch (e, stack) {
        boot.sendPort.send(
          _DbResponse(message.id, null, e.toString(), stack.toString()),
        );
      }
    });
  }
}
