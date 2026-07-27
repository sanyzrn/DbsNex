import 'dart:async';
import 'dart:isolate';

import 'package:nex_data/nex_data.dart';

/// Commands the worker isolate understands.
///
/// package:sqlite3 is a synchronous FFI binding: every call blocks the calling
/// isolate for the whole query. Running it on the UI isolate — which is what
/// the composition root used to do, including a full database file copy on
/// every launch — directly violates the product's one non-negotiable principle.
enum _DbCommand {
  timeline,
  loadMore,
  captureText,
  captureMedia,
  updateNote,
  deleteNote,
  setTags,
  search,
  backup,
  exportArchive,
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
  const _WorkerBoot(this.sendPort, this.dbPath, this.deviceId);

  final SendPort sendPort;
  final String dbPath;
  final String deviceId;
}

/// Async facade over a dedicated database isolate.
///
/// The UI isolate never touches sqlite3 directly; it sends a command and awaits
/// a reply, so no query can block a frame.
class NexDbWorker {
  NexDbWorker._(this._isolate, this._toWorker, this._responses, Stream<dynamic> incoming) {
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
      _WorkerBoot(responses.sendPort, dbPath, deviceId),
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
        StateError('nex-db worker failed: ' + message.error.toString()),
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

  Future<List<Note>> timeline({int limit = 200, int offset = 0}) =>
      _send<List<Note>>(_DbCommand.timeline, {'limit': limit, 'offset': offset});

  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      _send<List<Note>>(_DbCommand.loadMore, {'limit': limit, 'offset': offset});

  Future<Note> captureText(String content) =>
      _send<Note>(_DbCommand.captureText, {'content': content});

  Future<Note> captureMedia({
    required String type,
    required String mediaUri,
    int? durationMs,
  }) =>
      _send<Note>(_DbCommand.captureMedia, {
        'type': type,
        'mediaUri': mediaUri,
        'durationMs': durationMs,
      });

  Future<void> updateNote(String id, String content) =>
      _send<void>(_DbCommand.updateNote, {'id': id, 'content': content});

  Future<void> deleteNote(String id) =>
      _send<void>(_DbCommand.deleteNote, {'id': id});

  Future<void> setTags(String noteId, List<String> tagNames) =>
      _send<void>(_DbCommand.setTags, {'noteId': noteId, 'tags': tagNames});

  Future<List<Note>> search(String query) =>
      _send<List<Note>>(_DbCommand.search, {'query': query});

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

  static void _entryPoint(_WorkerBoot boot) {
    final requests = ReceivePort();
    boot.sendPort.send(requests.sendPort);

    final db = NexDatabase.open(boot.dbPath);
    final repo = NoteRepository(db, localDeviceId: boot.deviceId);
    final capture = CaptureService(repo, deviceId: boot.deviceId);
    final tags = TagService(repo);
    final search = SearchService(repo);

    requests.listen((message) {
      if (message is! _DbRequest) return;

      try {
        final Object? result = switch (message.command) {
          _DbCommand.timeline => search.timeline(
              limit: message.args['limit']! as int,
              offset: message.args['offset']! as int,
            ),
          _DbCommand.loadMore => search.timeline(
              limit: message.args['limit']! as int,
              offset: message.args['offset']! as int,
            ),
          _DbCommand.captureText =>
            capture.captureText(message.args['content']! as String),
          _DbCommand.captureMedia => capture.captureMedia(
              type: message.args['type']! as String,
              mediaUri: message.args['mediaUri']! as String,
              durationMs: message.args['durationMs'] as int?,
            ),
          _DbCommand.updateNote => repo.updateContent(
              message.args['id']! as String,
              message.args['content']! as String,
            ),
          _DbCommand.deleteNote =>
            repo.softDelete(message.args['id']! as String),
          _DbCommand.setTags => tags.setTags(
              message.args['noteId']! as String,
              (message.args['tags']! as List).cast<String>(),
            ),
          _DbCommand.search => search.query(message.args['query']! as String),
          _DbCommand.backup => repo.backup(message.args['dir']! as String),
          _DbCommand.exportArchive => repo.exportArchive(
              outputPath: message.args['outputPath']! as String,
              mediaRoot: message.args['mediaRoot']! as String,
            ),
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
