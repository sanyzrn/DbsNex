import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';

import 'ai_provider.dart';
import 'nex_db.dart';

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
  captureChecklist,
  importNotes,
  captureLink,
  captureVoice,
  capturePhoto,
  captureFile,
  updateNote,
  deleteNote,
  undelete,
  setCaption,
  setTitle,
  setSummaryText,
  setLinkMetadata,
  toggleChecklistItem,
  pinNote,
  unpinNote,
  pinnedNoteCount,
  addTag,
  removeTag,
  createTag,
  listTags,
  setTagColor,
  backup,
  setDueAt,
  upcomingReminders,
  exportArchive,
  importArchive,
  // Library maintenance (trash, tag manager, storage breakdown).
  deletedNotes,
  purgeDeletedBefore,
  sweepOrphanMedia,
  purgeNote,
  purgeAllDeleted,
  tagUsage,
  renameTag,
  mergeTag,
  deleteTag,
  nearestMiss,
  storage,
  // Enrichment.
  enrichNote,
  backfillEnrichment,
  suggestTags,
  summarize,
  relatedNotes,
  semanticSearch,
  setAiCapabilities,
  setAiProvider,
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
    this.mediaDir,
  );

  final SendPort sendPort;
  final String dbPath;
  final String deviceId;

  /// Must be isolate-sendable: pure Dart, no platform channels. The adapters in
  /// packages/core (`NullAIAdapter`, `OnDeviceAIAdapter`) are const and satisfy
  /// this; a plugin-backed adapter would not.
  final AIAdapter adapter;
  final AiCapabilities capabilities;

  /// Where attachment files live. The purge paths need it to delete the file
  /// a purged note pointed at — the row alone was never the whole note.
  final String mediaDir;
}

/// Sent through the boot port when the database itself cannot be opened.
///
/// The worker used to send its request port first and open the database
/// second, so a file that would not open — corruption, a full disk, a locked
/// path — killed the isolate silently and left the awaiting side parked on a
/// Completer that nothing would ever complete: the app hung on the splash
/// screen for as long as the user was willing to stare at it. Failure is now
/// a first-class reply, and it becomes a bootstrap error the user can see
/// and retry.
class _WorkerOpenFailure {
  const _WorkerOpenFailure(this.message, this.stack);

  final String message;
  final String stack;
}

/// Async facade over a dedicated database isolate.
///
/// The UI isolate never touches sqlite3 directly; it sends a command and awaits
/// a reply, so no query can block a frame.
class NexDbWorker implements NexDb {
  /// The error and exit subscriptions are handed in already listening.
  ///
  /// A `ReceivePort` is a single-subscription stream, and [spawn] has to watch
  /// both ports before the isolate is up — that is the whole point of them, to
  /// catch a database that never opens. Listening again here threw
  /// `Bad state: Stream has already been listened to` on every launch, from
  /// inside the constructor, so the app could not start at all. Cancelling
  /// the first subscription instead of reusing it is not the fix either:
  /// cancelling a `ReceivePort` subscription closes the port.
  ///
  /// One listener per port for the whole life of the worker; [spawn] routes
  /// to these handlers once the instance exists.
  NexDbWorker._(
    this._isolate,
    this._toWorker,
    this._responses,
    Stream<dynamic> incoming,
    this._errors,
    this._exits,
    this._errorSub,
    this._exitSub,
  ) {
    _subscription = incoming.listen(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _responses;
  final ReceivePort _errors;
  final ReceivePort _exits;

  late final StreamSubscription<dynamic> _subscription;

  /// An uncaught worker error is fatal to the isolate (errorsAreFatal).
  /// Whatever requests were in flight must hear about it instead of waiting
  /// forever; the ones queued behind them are covered by the exit port, which
  /// fires when the isolate actually goes away.
  final StreamSubscription<dynamic> _errorSub;
  final StreamSubscription<dynamic> _exitSub;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  /// Fails everything in flight. Called when the isolate reports a fatal
  /// error or exits: a caller parked on a request that will never be
  /// answered is a caller hanging the capture sheet, the timeline, or the
  /// whole app.
  void _failAllPending(String reason) {
    if (_closed || _pending.isEmpty) return;
    final outstanding = Map<int, Completer<Object?>>.of(_pending);
    _pending.clear();
    for (final completer in outstanding.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(reason));
      }
    }
  }

  /// An error port message is a two-element list: [error, stackTrace], both
  /// strings by the time they cross the port.
  void _onIsolateError(dynamic message) {
    _failAllPending('nex-db worker crashed: $message');
  }

  void _onIsolateExit(dynamic message) {
    _failAllPending('nex-db worker has exited unexpectedly');
  }

  static Future<NexDbWorker> spawn({
    required String dbPath,
    required String deviceId,
    required String mediaDir,
    AIAdapter adapter = const NullAIAdapter(),
    AiCapabilities capabilities = const AiCapabilities(),
  }) async {
    final responses = ReceivePort();
    final incoming = responses.asBroadcastStream();
    final ready = Completer<SendPort>();
    final errors = ReceivePort();
    final exits = ReceivePort();

    // Everything below is about refusing to hang. Three ways this used to
    // deadlock or go silent: the database failing to open (the isolate died
    // before its request port was ever sent — nothing completed `ready`), an
    // unexpected error killing the isolate mid-session (pending requests sat
    // unanswered forever), and the isolate exiting outright. Each now
    // completes or fails whatever is waiting on it.
    late final StreamSubscription<dynamic> bootstrap;
    bootstrap = incoming.listen((message) {
      if (ready.isCompleted) return;
      if (message is SendPort) {
        ready.complete(message);
        bootstrap.cancel();
      } else if (message is _WorkerOpenFailure) {
        ready.completeError(
          StateError('nex-db failed to open: ${message.message}'),
          StackTrace.fromString(message.stack),
        );
        bootstrap.cancel();
      }
    });

    // Listened once, here, and never again — see the constructor. Before the
    // worker exists these fail whatever is waiting on it; afterwards they are
    // the instance's own error and exit handlers.
    NexDbWorker? worker;
    final spawnErrorSub = errors.listen((message) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('nex-db crashed while starting: $message'),
        );
        bootstrap.cancel();
        return;
      }
      worker?._onIsolateError(message);
    });
    final spawnExitSub = exits.listen((message) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('nex-db exited before it was ready'));
        bootstrap.cancel();
        return;
      }
      worker?._onIsolateExit(message);
    });

    final isolate = await Isolate.spawn(
      _entryPoint,
      _WorkerBoot(
        responses.sendPort,
        dbPath,
        deviceId,
        adapter,
        capabilities,
        mediaDir,
      ),
      debugName: 'nex-db',
      errorsAreFatal: true,
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );

    try {
      final toWorker = await ready.future;
      return worker = NexDbWorker._(
        isolate,
        toWorker,
        responses,
        incoming,
        errors,
        exits,
        spawnErrorSub,
        spawnExitSub,
      );
    } on Object {
      // The worker never came up. The ports are this frame's problem now —
      // the instance that would own them will never exist.
      await spawnErrorSub.cancel();
      await spawnExitSub.cancel();
      errors.close();
      exits.close();
      isolate.kill(priority: Isolate.beforeNextEvent);
      rethrow;
    }
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

  @override
  Future<List<Note>> timeline({
    int limit = 200,
    int offset = 0,
    String? tagId,
  }) => _send<List<Note>>(_DbCommand.timeline, {
    'limit': limit,
    'offset': offset,
    'tagId': tagId,
  });

  @override
  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      _send<List<Note>>(_DbCommand.loadMore, {
        'limit': limit,
        'offset': offset,
      });

  @override
  Future<List<Note>> search(SearchFilters filters) =>
      _send<List<Note>>(_DbCommand.search, {'filters': filters});

  @override
  Future<Note?> getById(String id) =>
      _send<Note?>(_DbCommand.getById, {'id': id});

  /* ------------------------------------------------------------ capturing */

  @override
  Future<Note?> captureText(String content) =>
      _send<Note?>(_DbCommand.captureText, {'content': content});

  @override
  Future<Note?> captureChecklist(List<ChecklistItem> items) =>
      _send<Note?>(_DbCommand.captureChecklist, {
        // Sent as the on-disk text rather than as objects: the isolate port
        // takes primitives, and formatChecklist is already the one place that
        // knows the format.
        'body': formatChecklist(items),
      });

  @override
  Future<int> importNotes(String path, {required String mediaDir}) =>
      _send<int>(_DbCommand.importNotes, {'path': path, 'mediaDir': mediaDir});

  @override
  Future<Note?> captureLink(String url) =>
      _send<Note?>(_DbCommand.captureLink, {'url': url});

  @override
  Future<Note> captureVoice({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  }) => _send<Note>(_DbCommand.captureVoice, {
    'mediaUri': mediaUri,
    'mediaBytes': mediaBytes,
    'durationMs': durationMs,
  });

  @override
  Future<Note> capturePhoto({
    required String mediaUri,
    required Uint8List mediaBytes,
  }) => _send<Note>(_DbCommand.capturePhoto, {
    'mediaUri': mediaUri,
    'mediaBytes': mediaBytes,
  });

  @override
  Future<Note> captureFile({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  }) => _send<Note>(_DbCommand.captureFile, {
    'mediaUri': mediaUri,
    'mediaBytes': mediaBytes,
    'originalFilename': originalFilename,
    'mimeType': mimeType,
  });

  /* ------------------------------------------------------------- mutating */

  @override
  Future<void> updateNote(String id, String content) =>
      _send<void>(_DbCommand.updateNote, {'id': id, 'content': content});

  @override
  Future<void> deleteNote(String id) =>
      _send<void>(_DbCommand.deleteNote, {'id': id});

  @override
  Future<void> undelete(String id) =>
      _send<void>(_DbCommand.undelete, {'id': id});

  @override
  Future<void> setCaption(String id, String caption) =>
      _send<void>(_DbCommand.setCaption, {'id': id, 'caption': caption});

  @override
  Future<void> setTitle(String id, String? title) =>
      _send<void>(_DbCommand.setTitle, {'id': id, 'title': title});

  @override
  Future<void> setSummaryText(String id, String text) =>
      _send<void>(_DbCommand.setSummaryText, {'id': id, 'text': text});

  @override
  Future<void> setLinkMetadata(String id, {String? title, String? excerpt}) =>
      _send<void>(_DbCommand.setLinkMetadata, {
        'id': id,
        'title': title,
        'excerpt': excerpt,
      });

  @override
  Future<void> toggleChecklistItem(String id, int index) =>
      _send<void>(_DbCommand.toggleChecklistItem, {'id': id, 'index': index});

  @override
  Future<bool> pinNote(String id) =>
      _send<bool>(_DbCommand.pinNote, {'id': id});

  @override
  Future<void> unpinNote(String id) =>
      _send<void>(_DbCommand.unpinNote, {'id': id});

  @override
  Future<int> pinnedNoteCount() => _send<int>(_DbCommand.pinnedNoteCount);

  /* ----------------------------------------------------------------- tags */

  @override
  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) => _send<Tag>(_DbCommand.addTag, {
    'noteId': noteId,
    'name': name,
    'color': color,
  });

  @override
  Future<void> removeTag({required String noteId, required String tagId}) =>
      _send<void>(_DbCommand.removeTag, {'noteId': noteId, 'tagId': tagId});

  @override
  Future<Tag> createTag(String name, {String? color}) =>
      _send<Tag>(_DbCommand.createTag, {'name': name, 'color': color});

  @override
  Future<List<Tag>> listTags() => _send<List<Tag>>(_DbCommand.listTags);

  @override
  Future<void> setTagColor({required String tagId, String? color}) =>
      _send<void>(_DbCommand.setTagColor, {'tagId': tagId, 'color': color});

  /* ------------------------------------------------------ backup / export */

  @override
  @override
  Future<void> setDueAt(
    String noteId,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) => _send<void>(_DbCommand.setDueAt, {
    'noteId': noteId,
    'when': when?.toUtc().toIso8601String(),
    'repeat': repeat.wireName,
  });

  @override
  Future<List<Note>> upcomingReminders({int limit = 200}) =>
      _send<List<Note>>(_DbCommand.upcomingReminders, {'limit': limit});

  @override
  Future<void> backup(String backupDir, {required String mediaDir}) =>
      _send<void>(_DbCommand.backup, {'dir': backupDir, 'mediaDir': mediaDir});

  @override
  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) => _send<String>(_DbCommand.exportArchive, {
    'outputPath': outputPath,
    'mediaRoot': mediaRoot,
  });

  @override
  Future<ImportResult> importArchive({
    required String archivePath,
    required String mediaRoot,
  }) => _send<ImportResult>(_DbCommand.importArchive, {
    'archivePath': archivePath,
    'mediaRoot': mediaRoot,
  });

  /* --------------------------------------------------- library maintenance */

  @override
  Future<List<Note>> deletedNotes({int limit = 200}) =>
      _send<List<Note>>(_DbCommand.deletedNotes, {'limit': limit});

  @override
  Future<void> purgeDeletedBefore(DateTime cutoff) =>
      _send<void>(_DbCommand.purgeDeletedBefore, {'cutoff': cutoff});

  @override
  Future<int> sweepOrphanMedia() => _send<int>(_DbCommand.sweepOrphanMedia);

  @override
  Future<void> purgeNote(String id) =>
      _send<void>(_DbCommand.purgeNote, {'id': id});

  @override
  Future<void> purgeAllDeleted() => _send<void>(_DbCommand.purgeAllDeleted);

  @override
  Future<List<TagUsage>> tagUsage() =>
      _send<List<TagUsage>>(_DbCommand.tagUsage);

  @override
  Future<void> renameTag(String id, String name) =>
      _send<void>(_DbCommand.renameTag, {'id': id, 'name': name});

  @override
  Future<void> mergeTag({required String sourceId, required String targetId}) =>
      _send<void>(_DbCommand.mergeTag, {
        'sourceId': sourceId,
        'targetId': targetId,
      });

  @override
  Future<void> deleteTag(String id) =>
      _send<void>(_DbCommand.deleteTag, {'id': id});

  @override
  Future<Note?> nearestMiss(String query) =>
      _send<Note?>(_DbCommand.nearestMiss, {'query': query});

  @override
  Future<StorageSnapshot> storage({
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) => _send<StorageSnapshot>(_DbCommand.storage, {
    'dbPath': dbPath,
    'mediaDir': mediaDir,
    'backupDir': backupDir,
  });

  /* ----------------------------------------------------------- enrichment */

  @override
  Future<void> enrichNote(String noteId) =>
      _send<void>(_DbCommand.enrichNote, {'noteId': noteId});

  @override
  Future<int> backfillEnrichment({int limit = 25}) =>
      _send<int>(_DbCommand.backfillEnrichment, {'limit': limit});

  @override
  Future<List<TagSuggestion>> suggestTags(String noteId) =>
      _send<List<TagSuggestion>>(_DbCommand.suggestTags, {'noteId': noteId});

  @override
  Future<Summary?> summarizeOnDemand(String noteId) =>
      _send<Summary?>(_DbCommand.summarize, {'noteId': noteId});

  @override
  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      _send<List<SemanticHit>>(_DbCommand.relatedNotes, {
        'noteId': noteId,
        'limit': limit,
      });

  @override
  Future<List<SemanticHit>> semanticSearch(String query, {int limit = 20}) =>
      _send<List<SemanticHit>>(_DbCommand.semanticSearch, {
        'query': query,
        'limit': limit,
      });

  @override
  Future<void> setAiProvider(Map<String, String> config) =>
      _send<void>(_DbCommand.setAiProvider, {'config': config});

  @override
  Future<void> setAiCapabilities(AiCapabilities capabilities) =>
      _send<void>(_DbCommand.setAiCapabilities, {'capabilities': capabilities});

  /// One sync cycle.
  ///
  /// SyncClient needs the concrete repository — the outbox surface the port
  /// deliberately withholds — so it is built here, inside the isolate that owns
  /// it, rather than on the UI isolate where it has nothing to talk to.
  @override
  Future<SyncResult> sync({required String baseUrl, String? bearerToken}) =>
      _send<SyncResult>(_DbCommand.sync, {
        'baseUrl': baseUrl,
        'bearerToken': bearerToken,
      });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      await _send<void>(_DbCommand.close);
    } catch (_) {
      // The isolate may already be gone; teardown must never throw.
    }

    await _subscription.cancel();
    await _errorSub.cancel();
    await _exitSub.cancel();
    _responses.close();
    _errors.close();
    _exits.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  /* -------------------------------------------------------- worker side */

  /// Runs a `void` operation and yields a value the switch expression can use.
  static Object? _voided(void Function() operation) {
    operation();
    return null;
  }

  /// Imports an export, writing its photos into [mediaDir] on the way.
  ///
  /// Split out of the command switch because it is three statements rather than
  /// one expression, and because the media path is the whole reason photos now
  /// come across at all — a reader with nowhere to put files still gets every
  /// note's words and counts the photos as skipped.
  static int _importNotes(
    CaptureService capture,
    File file,
    Directory mediaDir,
  ) {
    final read = NoteImportArchive.read(file, mediaInto: mediaDir);
    return capture
        .importNotes(read.notes, mediaFor: NoteImportArchive.mediaPathFor)
        .length;
  }

  static void _entryPoint(_WorkerBoot boot) {
    final requests = ReceivePort();

    final NexDatabase db;
    try {
      db = NexDatabase.open(boot.dbPath);
    } catch (e, stack) {
      // The boot port must be answered even when the database will not
      // open: the awaiting side is parked on a Completer that only a
      // message through this port can complete. This turns "splash screen
      // forever" into a bootstrap error the user can see and retry.
      boot.sendPort.send(_WorkerOpenFailure(e.toString(), stack.toString()));
      return;
    }
    boot.sendPort.send(requests.sendPort);

    final repo = SqliteNoteRepository(db, localDeviceId: boot.deviceId);
    final capture = CaptureService(repo, deviceId: boot.deviceId);
    final tags = TagService(repo);
    final search = SearchService(repo);
    final maintenance = LibraryMaintenance(repo, mediaRoot: boot.mediaDir);
    final enrichment = EnrichmentService(
      repo: repo,
      adapter: boot.adapter,
      capabilities: boot.capabilities,
    );

    // One repair pass per open. Cheap when the index is healthy (two set
    // lookups), and the difference between findable and silently missing
    // when it is not — a crash between paired FTS statements used to
    // strand a note out of search until it was next edited.
    repo.repairSearchIndex();

    Object? argOf(_DbRequest message, String key) => message.args[key];

    Future<Object?> dispatch(_DbRequest message) async {
      Object? arg(String key) => argOf(message, key);

      // The handler is asynchronous because several operations are: exportArchive
      // and storage return Futures, and a Future cannot cross a SendPort — the
      // previous synchronous handler sent the Future itself and the awaiting side
      // hung or cast-failed.
      return switch (message.command) {
        _DbCommand.timeline || _DbCommand.loadMore => search.timeline(
          limit: arg('limit')! as int,
          offset: arg('offset')! as int,
          tagId: arg('tagId') as String?,
        ),
        _DbCommand.search => search.search(arg('filters')! as SearchFilters),
        _DbCommand.getById => repo.getById(arg('id')! as String),
        _DbCommand.captureText => capture.submitTextCapture(
          arg('content')! as String,
        ),
        _DbCommand.captureChecklist => capture.submitChecklistCapture(
          parseChecklist(arg('body')! as String),
        ),
        // Read *and* written inside the isolate. Unzipping a Takeout
        // export, writing its photos out and inserting a few thousand rows
        // are all long enough to drop frames, and the point of this worker
        // is that none of it happens on the thread drawing the screen.
        _DbCommand.importNotes => _importNotes(
          capture,
          File(arg('path')! as String),
          Directory(arg('mediaDir')! as String),
        ),
        _DbCommand.captureLink => capture.submitLinkCapture(
          arg('url')! as String,
        ),
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
        _DbCommand.updateNote => _voided(
          () => repo.updateContent(
            arg('id')! as String,
            arg('content')! as String,
          ),
        ),
        _DbCommand.deleteNote => _voided(
          () => repo.softDelete(arg('id')! as String),
        ),
        _DbCommand.undelete => _voided(
          () => repo.undelete(arg('id')! as String),
        ),
        _DbCommand.setCaption => _voided(
          () =>
              repo.setCaption(arg('id')! as String, arg('caption')! as String),
        ),
        _DbCommand.setTitle => _voided(
          () => repo.setTitle(arg('id')! as String, arg('title') as String?),
        ),
        _DbCommand.setSummaryText => _voided(
          () =>
              repo.setSummaryText(arg('id')! as String, arg('text')! as String),
        ),
        _DbCommand.setLinkMetadata => _voided(
          () => repo.setLinkMetadata(
            arg('id')! as String,
            title: arg('title') as String?,
            excerpt: arg('excerpt') as String?,
          ),
        ),
        _DbCommand.toggleChecklistItem => _voided(
          () => repo.toggleChecklistItem(
            arg('id')! as String,
            arg('index')! as int,
          ),
        ),
        _DbCommand.pinNote => repo.pinNote(arg('id')! as String),
        _DbCommand.unpinNote => _voided(
          () => repo.unpinNote(arg('id')! as String),
        ),
        _DbCommand.pinnedNoteCount => repo.pinnedNoteCount(),
        _DbCommand.addTag => tags.addTag(
          noteId: arg('noteId')! as String,
          name: arg('name')! as String,
          color: arg('color') as String?,
        ),
        _DbCommand.removeTag => _voided(
          () => tags.removeTag(
            noteId: arg('noteId')! as String,
            tagId: arg('tagId')! as String,
          ),
        ),
        _DbCommand.createTag => repo.upsertTag(
          name: arg('name')! as String,
          color: arg('color') as String?,
        ),
        _DbCommand.listTags => tags.listTags(),
        _DbCommand.setTagColor => _voided(
          () => tags.setColor(
            tagId: arg('tagId')! as String,
            color: arg('color') as String?,
          ),
        ),
        // `when` is a pattern guard keyword, so the variable it would
        // otherwise be named cannot be spelled here.
        _DbCommand.setDueAt => _voided(() {
          final at = arg('when');
          repo.setDueAt(
            arg('noteId')! as String,
            at is String ? DateTime.parse(at) : null,
            repeat: NoteRepeat.fromWire(arg('repeat') as String?),
          );
        }),
        _DbCommand.upcomingReminders => repo.listUpcomingReminders(
          limit: arg('limit')! as int,
        ),
        _DbCommand.backup => repo.backup(
          arg('dir')! as String,
          mediaDir: arg('mediaDir')! as String,
        ),
        _DbCommand.exportArchive => (await repo.exportArchive(
          outputPath: arg('outputPath')! as String,
          mediaRoot: arg('mediaRoot')! as String,
        )).path,
        _DbCommand.importArchive => await repo.importArchive(
          archiveFile: File(arg('archivePath')! as String),
          mediaRoot: arg('mediaRoot')! as String,
        ),
        _DbCommand.deletedNotes => maintenance.deletedNotes(
          limit: arg('limit')! as int,
        ),
        _DbCommand.purgeDeletedBefore => _voided(
          () => maintenance.purgeDeletedBefore(arg('cutoff')! as DateTime),
        ),
        _DbCommand.sweepOrphanMedia => maintenance.sweepOrphanMedia(),
        _DbCommand.purgeNote => _voided(
          () => maintenance.purgeNote(arg('id')! as String),
        ),
        _DbCommand.purgeAllDeleted => _voided(maintenance.purgeAllDeleted),
        _DbCommand.tagUsage => maintenance.tagUsage(),
        _DbCommand.renameTag => _voided(
          () => maintenance.renameTag(
            arg('id')! as String,
            arg('name')! as String,
          ),
        ),
        _DbCommand.mergeTag => _voided(
          () => maintenance.mergeTag(
            sourceId: arg('sourceId')! as String,
            targetId: arg('targetId')! as String,
          ),
        ),
        _DbCommand.deleteTag => _voided(
          () => maintenance.deleteTag(arg('id')! as String),
        ),
        _DbCommand.nearestMiss => maintenance.nearestMiss(
          arg('query')! as String,
        ),
        _DbCommand.storage => await maintenance.storage(
          arg('dbPath')! as String,
          arg('mediaDir')! as String,
          arg('backupDir')! as String,
        ),
        _DbCommand.enrichNote =>
          await enrichment
              .enrichNote(arg('noteId')! as String)
              .then<Object?>((_) => null),
        _DbCommand.backfillEnrichment => await enrichment.backfill(
          limit: arg('limit')! as int,
        ),
        _DbCommand.suggestTags => await enrichment.suggestTags(
          arg('noteId')! as String,
        ),
        _DbCommand.summarize => await enrichment.summarizeOnDemand(
          arg('noteId')! as String,
        ),
        _DbCommand.relatedNotes => await enrichment.relatedNotes(
          arg('noteId')! as String,
          limit: arg('limit')! as int,
        ),
        _DbCommand.semanticSearch => await enrichment.semanticSearch(
          arg('query')! as String,
          limit: arg('limit')! as int,
        ),
        _DbCommand.setAiCapabilities => _voided(
          () => enrichment.updateCapabilities(
            arg('capabilities')! as AiCapabilities,
          ),
        ),
        _DbCommand.setAiProvider => _voided(() {
          final raw = (arg('config')! as Map).cast<String, String>();
          final config = AiProviderConfig(
            provider: AiProviderWire.fromWire(raw['provider']),
            apiKey: raw['apiKey'] ?? '',
            baseUrl: raw['baseUrl'] ?? '',
            model: raw['model'] ?? '',
          );
          // No provider, or an incomplete one, falls back to the local
          // heuristics rather than to nothing: tag hints keep working.
          enrichment.updateAdapter(
            config.isUsable
                ? CloudAIAdapter(
                    config: config,
                    outputLanguage: AiOutputLanguage.fromWire(
                      raw['outputLanguage'],
                    ),
                  )
                : const OnDeviceAIAdapter(),
          );
        }),
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
    }

    // One request handled at a time. The listener is not `async` — several
    // handlers await (import reads a file, sync talks over HTTP, enrichment
    // talks to a provider) — and a raw async listener interleaved them: a
    // capture could run against the database mid-import, and a close could
    // dispose the handle under a handler still mid-await. Chaining each
    // request onto the tail of the last keeps ordering honest. The chain is
    // fault-tolerant on purpose: a failed request must not poison the queue.
    var tail = Future<void>.value();
    requests.listen((message) {
      if (message is! _DbRequest) return;
      tail = tail.then((_) async {
        try {
          final result = await dispatch(message);
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
    });
  }
}
