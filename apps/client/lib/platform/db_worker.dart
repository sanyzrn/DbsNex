import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;

import 'package:nex_ai/cloud.dart';
import 'local_embedder.dart';
import 'nex_db.dart';

part 'db_worker_client.dart';
part 'db_worker_attachments.dart';
part 'db_worker_dispatch.dart';
part 'db_worker_modules.dart';

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
  captureShared,
  capturedFor,
  captureChecklist,
  importNotes,
  captureLink,
  captureVoice,
  capturePhoto,
  captureFile,
  updateNote,
  updateImageMedia,
  convertMarkdown,
  deleteNote,
  undelete,
  setCaption,
  appendCaption,
  replaceCaption,
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
  // Recurring obligations — see NexCommitment in packages/core.
  listCommitments,
  cyclePeriods,
  cycleStartPeriod,
  cycleEndPeriod,
  cycleUpdatePeriod,
  cycleDeletePeriod,
  cycleDays,
  cycleSaveDay,
  cycleDeleteAll,
  attachmentsFor,
  attachmentAdd,
  attachmentUpdateImage,
  attachmentRemove,
  attachmentRestore,
  attachmentReorder,
  attachmentSetCaption,
  attachmentSetOcr,
  attachmentReadText,
  attachmentRename,
  attachmentDetach,
  attachmentPromote,
  moduleRecords,
  moduleRecord,
  modulePut,
  moduleDelete,
  moduleDeleteAll,
  scheduleNote,
  scheduledNotes,
  releaseDueNotes,
  releaseScheduledNow,
  rescheduleNote,
  discardScheduled,
  listThreads,
  threadsForNote,
  threadNotes,
  createThread,
  renameThread,
  deleteThread,
  addToThread,
  removeFromThread,
  suggestThread,
  saveCommitment,
  markCommitmentMet,
  deleteCommitment,
  mergeTag,
  deleteTag,
  nearestMiss,
  storage,
  // Enrichment.
  enrichNote,
  readMediaOnDemand,
  backfillEnrichment,
  backfillEmbeddings,
  suggestTags,
  summarize,
  relatedNotes,
  semanticSearch,
  fusedSearch,
  setAiCapabilities,
  setAiProvider,
  setLocalEmbedder,
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
    this.rootToken,
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

  /// What lets this isolate reach a platform channel: the on-device search
  /// model is native code, and it is asked for vectors from in here, where
  /// enrichment runs. Null where there is no engine to reach — tests, and
  /// anything not started by Flutter.
  final RootIsolateToken? rootToken;
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
class NexDbWorker
    with _DbClient, _DbAttachments, _DbModuleRecords
    implements NexDb {
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
  bool _closing = false;
  Future<void>? _closeFuture;

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
    AiCapabilities capabilities = AiCapabilities.allOff,
    RootIsolateToken? rootToken,
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
        rootToken ?? RootIsolateToken.instance,
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

  @override
  Future<T> _send<T>(
    _DbCommand command, [
    Map<String, Object?> args = const {},
  ]) {
    if (_closed || (_closing && command != _DbCommand.close)) {
      throw StateError('NexDbWorker has been closed');
    }

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _toWorker.send(_DbRequest(id, command, args));
    return completer.future.then((value) => value as T);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await _backupTask;
    } catch (_) {
      // Close even after a failed backup.
    }
    _closing = true;

    try {
      // The worker must serve this command before its isolate is killed.
      // Marking it closed first made `_send` reject the close request itself,
      // leaving SQLite open on Windows even though `close()` had returned.
      await _send<void>(_DbCommand.close);
    } catch (_) {
      // The isolate may already be gone; teardown must never throw.
    }

    _closed = true;
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

  /// Keyword matches and meaning matches, fused (W2.2). The meaning half
  /// waits on the provider, which is why this runs off the queue; the ranking
  /// itself is a few hundred rows and happens after the wait.
  static Future<List<Note>> _fusedSearch(
    SqliteNoteRepository repo,
    EnrichmentService enrichment,
    SearchFilters filters,
  ) async {
    final hits = await enrichment.semanticSearch(filters.query, limit: 100);
    return repo.rankedSearch(
      filters,
      semantic: [for (final hit in hits) hit.noteId],
    );
  }

  static void _entryPoint(_WorkerBoot boot) {
    final requests = ReceivePort();
    if (boot.rootToken case final token?) {
      try {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      } catch (_) {
        // No engine behind the token. The search model then fails each
        // call, and every note stays in the backlog rather than being
        // marked as having nothing to embed.
      }
    }

    final NexDatabase db;
    try {
      db = NexDatabase.open(boot.dbPath);
      // Tags, summaries, transcripts and the search index are requested from
      // this isolate; they go on the same record as the assistant's (W3.2).
      NexDisclosureLog.configure(p.dirname(boot.dbPath));
    } catch (e, stack) {
      // The boot port must be answered even when the database will not
      // open: the awaiting side is parked on a Completer that only a
      // message through this port can complete. This turns "splash screen
      // forever" into a bootstrap error the user can see and retry.
      boot.sendPort.send(_WorkerOpenFailure(e.toString(), stack.toString()));
      return;
    }
    boot.sendPort.send(requests.sendPort);

    final worker = _Worker(boot, db);

    // One repair pass per open. Cheap when the index is healthy (two set
    // lookups), and the difference between findable and silently missing
    // when it is not — a crash between paired FTS statements used to
    // strand a note out of search until it was next edited.
    worker.repo.repairSearchIndex();

    // One request handled at a time — with one exception, below. The listener
    // is not `async` because several handlers await (import reads a file,
    // sync talks over HTTP), and a raw async listener interleaved them: a
    // capture could run against the database mid-import, and a close could
    // dispose the handle under a handler still mid-await. Chaining each
    // request onto the tail of the last keeps ordering honest. The chain is
    // fault-tolerant on purpose: a failed request must not poison the queue.
    var tail = Future<void>.value();

    // Set once the close command has been served, so nothing new is started
    // in the background after it.
    var closed = false;

    // Background work still waiting on a provider.
    final inFlight = <Future<void>>{};

    Future<void> serve(_DbRequest message) async {
      try {
        final result = await worker.dispatch(message);
        boot.sendPort.send(_DbResponse(message.id, result, null, null));
      } catch (e, stack) {
        boot.sendPort.send(
          _DbResponse(message.id, null, e.toString(), stack.toString()),
        );
      }
    }

    requests.listen((message) {
      if (message is! _DbRequest) return;
      // The exception, and the reason it exists: these wait on a model, and
      // a model is allowed 90 seconds for text and three minutes for media.
      // On the chain, every one of those seconds is a second a capture would
      // spend queued behind it — and a capture is the one thing in this app
      // that is never allowed to wait. `scheduleEnrichment` already says
      // "never awaited by capture UI", and that was true of the caller and
      // false of the queue underneath it.
      if (_background.contains(message.command) && !closed) {
        late final Future<void> work;
        work = serve(message).whenComplete(() => inFlight.remove(work));
        inFlight.add(work);
        return;
      }
      tail = tail.then((_) async {
        if (message.command != _DbCommand.close) {
          await serve(message);
          return;
        }
        closed = true;
        // Give whatever is mid-request a moment to come back before the
        // handle goes. Bounded, because the thing it is waiting for may be
        // three minutes of provider timeout and shutdown cannot be: past
        // the grace, a resumed handler finds a disposed database and
        // throws, which `serve` catches. A stuck network call must not be
        // able to hold the app open.
        if (inFlight.isNotEmpty) {
          await Future.wait(
            inFlight,
          ).timeout(_closeGrace, onTimeout: () => const <void>[]);
        }
        // The handle is released *before* the reply, not after it. The
        // reply is what `close()` on the other side awaits, and it used to
        // be sent first — so `close()` returned while `nex.sqlite` was still
        // open. On Android that is invisible, because unlinking an open file
        // succeeds. On Windows it is a sharing violation: anything that
        // deleted or replaced the database right after closing it — a
        // restore, a test's teardown — failed with errno 32.
        //
        // `finally`, so the reply goes even if the close itself throws: the
        // other side is parked on it, and an unanswered close is an app that
        // cannot shut down.
        try {
          db.close();
        } finally {
          await serve(message);
          requests.close();
        }
      });
    });
  }

  /// The commands that wait on a provider rather than on the database.
  ///
  /// These run off the queue. Safe because this is one isolate and Dart is
  /// single-threaded: the only place another command can interleave is an
  /// `await`, and at every one of those these are parked on HTTP holding no
  /// transaction. Each writes at most one row of one note when it returns,
  /// and SQLite's own atomicity covers that.
  ///
  /// Deliberately not on this list: `sync`, `importNotes` and `importArchive`.
  /// All three write in bulk across many rows, which is exactly the
  /// multi-step sequence the chain exists to keep whole — and sync already
  /// caps itself at 30 seconds for this same reason.
  static const _background = {
    _DbCommand.enrichNote,
    _DbCommand.readMediaOnDemand,
    _DbCommand.backfillEnrichment,
    // A photo attached to a note is read, and a voice clip transcribed, by
    // the same model with the same three minutes. Left on the chain in
    // 1.99.90, every attachment held the database for as long as the model
    // took: a file attached, or a note deleted, appeared minutes later.
    _DbCommand.attachmentReadText,
    _DbCommand.backfillEmbeddings,
    _DbCommand.suggestTags,
    _DbCommand.summarize,
    _DbCommand.relatedNotes,
    _DbCommand.semanticSearch,
    _DbCommand.fusedSearch,
  };

  /// How long a close waits for background work before disposing the handle.
  static const _closeGrace = Duration(seconds: 2);
}
