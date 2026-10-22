import '../documents/text_import.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:isolate';
import 'dart:io';

// foundation exports its own Summary (a diagnostics type); the one this file
// returns is nex_core's AI summary.
import 'package:flutter/foundation.dart' hide Summary;
import 'package:http/http.dart' as http show Client;
import 'package:meta/meta.dart' show useResult;
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'backup_policy.dart';
import 'brief_refresh.dart';
import 'install_source.dart';
import 'full_backup.dart';
import 'vault_store.dart';
import 'vault_files.dart';
import 'editor_drafts.dart';
import 'capture_journal.dart';
import 'voice_spool.dart';
import 'chat_history.dart';
import 'export_cache.dart';
import 'db_worker.dart';
import 'package:nex_ai/cloud.dart';
import 'backup_folder.dart';
import 'nex_db.dart';
import 'photo_encoding.dart';
import 'media_picker_impl.dart';
import 'crash_reporter.dart';
import 'nex_preferences.dart';
import 'profile_photo.dart';
import 'local_ai_support.dart';
import 'model_store.dart';
import 'reminders.dart';
import '../modules/module_registry.dart';

part 'folder_backup.dart';
part 'module_services.dart';
part 'services/attachment_services.dart';
part 'services/backup_services.dart';
part 'services/library_services.dart';
part 'services/scheduled_services.dart';
part 'services/cycle_services.dart';
part 'services/note_services.dart';

/// Thrown when sync is invoked before the device has been paired with a server.
class SyncNotConfigured implements Exception {
  const SyncNotConfigured();

  @override
  String toString() =>
      'Sync is not configured. Pair this device with a Nex server first.';
}

/// No files have been replaced when authorization is declined or unavailable.
class VaultAuthenticationRequired implements Exception {}

/// Returned by [NexServices.restoreBackup] so a restore cannot silently leave a
/// dead service graph in place. The caller must feed it to NexRestartScope.
@immutable
class RestartRequired {
  const RestartRequired({this.error});
  final String? error;
}

/// App-wide services. Capture path never awaits AI (09-ai.md).
///
/// Depends on nex_core contracts plus the nex_data composition — never on
/// packages/ai — so deleting the AI package leaves this client compiling
/// (Phase 3 deletability guarantee).
///
/// All database work is delegated to [NexDbWorker], a dedicated isolate. The UI
/// isolate never calls sqlite3 directly.
class NexServices {
  NexServices._({
    required this.worker,
    required this.mediaPicker,
    required this.deviceId,
    required this.dbPath,
    required this.mediaDir,
    required this.backupDir,
    required BackupPolicy backupPolicy,
    required NexPreferences preferences,
  }) : _backupPolicy = backupPolicy,
       _preferences = preferences;

  final NexDb worker;
  final MediaPicker mediaPicker;
  final String deviceId;
  final String dbPath;
  final String mediaDir;
  final String backupDir;

  /// The alarms behind the due dates. Owned here rather than passed in
  /// because every path that can change a due date goes through this class,
  /// and a reminder that is only scheduled by whichever screen happened to
  /// set it is a reminder that is missed by the ones that did not.
  final reminders = NexReminders();

  final BackupPolicy _backupPolicy;
  final NexPreferences _preferences;
  late final briefRefresh = NexBriefRefresh(_preferences);
  EditorDrafts? get editorDrafts => _preferences.editorDrafts;
  bool get solarCalendar => _preferences.solarCalendar;

  /// Whether the intelligence layer is on and actually has a provider behind
  /// it. The UI asks so it does not offer a control that cannot do anything.
  bool get aiIsUsable =>
      _preferences.aiEnabled && aiTextAvailableWith(_preferences.aiProvider);

  bool get imageReadingAvailable =>
      _preferences.effectiveAiCapabilities.ocr &&
      _preferences.aiProvider.isUsable &&
      _preferences.aiProvider.supportsImages;

  bool get audioTranscriptionAvailable =>
      _preferences.effectiveAiCapabilities.transcription &&
      _preferences.aiProvider.isUsable &&
      _preferences.aiProvider.supportsTranscription;

  final _timelineController = StreamController<List<Note>>.broadcast();
  Stream<List<Note>> get timelineStream => _timelineController.stream;

  /// Fires after anything in «Cycle» is written — what the Cycle widgets
  /// redraw on. Its own stream: a period is not a note, and the timeline's
  /// listeners have no business waking for one.
  final _cycleController = StreamController<void>.broadcast();
  Stream<void> get cycleChanges => _cycleController.stream;

  Future<T> _cycleWrite<T>(Future<T> write) async {
    final result = await write;
    if (!_cycleController.isClosed) _cycleController.add(null);
    return result;
  }

  /// Fires with a module's id after it writes — what its screen and its
  /// Tools tile redraw on.
  final _moduleController = StreamController<String>.broadcast();
  Stream<String> get moduleChanges => _moduleController.stream;

  final _moduleDraftController = StreamController<String>.broadcast();
  Stream<String> get moduleDraftChanges => _moduleDraftController.stream;

  Future<T> _moduleWrite<T>(
    String module,
    Future<T> write, {
    String? kind,
  }) async {
    final result = await write;
    if (kind == 'draft') {
      if (!_moduleDraftController.isClosed) _moduleDraftController.add(module);
    } else if (kind != 'operation' && kind != '__recovery') {
      if (!_moduleController.isClosed) _moduleController.add(module);
      if (moduleRemindersEnabled(module) && kind != '__reminder') {
        try {
          await restoreModuleReminders();
        } catch (_) {
          reminders.onDiagnostic?.call('module reminder reconciliation failed');
        }
      }
    }
    return result;
  }

  bool _closed = false;

  /// [aiAdapter] is injected from Core types only. Defaults to
  /// [AIAdapterBinding.instance] (NullAIAdapter until a composition root binds
  /// an on-device or cloud adapter).
  static Future<NexServices> bootstrap({
    String? deviceId,
    required NexPreferences preferences,
    AIAdapter? aiAdapter,
    MediaPicker? mediaPicker,
    bool recoverDrafts = true,
  }) async {
    if (!kIsWeb &&
        (Platform.isAndroid || Platform.isIOS || Platform.isWindows)) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final support = await getApplicationSupportDirectory();
    final dbPath = p.join(support.path, 'nex.sqlite');
    ChatHistory.storageDirectory = support.path;
    // The record of what leaves the device, beside the library it describes.
    // The database worker configures the same file for its own requests.
    NexDisclosureLog.configure(support.path);
    NexAiFailureLog.sink = (message) => unawaited(noteDiagnostic(message));
    await NexInstallSource.load();
    final mediaDir = p.join(support.path, 'media');
    final backupDir = p.join(support.path, 'backups');
    modelsRoot = p.join(support.path, 'models');

    // Async filesystem APIs — createSync blocked the UI isolate.
    await Directory(mediaDir).create(recursive: true);
    await Directory(backupDir).create(recursive: true);
    final interrupted = await preferences.pendingRestoreRecovery();
    if (interrupted != null) {
      final library = interrupted['library'] as String;
      if (!p.isWithin(backupDir, library)) {
        throw StateError('Invalid recovery path');
      }
      await Isolate.run(
        () => NexBackupArchive.restore(
          liveDbPath: dbPath,
          mediaDir: mediaDir,
          backupFile: library,
        ),
      );
      await preferences.restoreSettings(
        Map<String, dynamic>.from(interrupted['settings'] as Map),
      );
      await preferences.finishRestoreRecovery();
    }
    await preferences.attachProfileMirror(mediaDir);
    // Old exports and the file picker's copies of chosen files (SEC-01):
    // cleared on every launch, not only when the next export happens.
    unawaited(
      getTemporaryDirectory().then(cleanExportCache).catchError((Object _) {}),
    );

    final profilePhoto = resolveProfilePhoto(
      mediaDir,
      preferences.profilePhotoPath,
    );
    if (profilePhoto != null &&
        profilePhoto.path != preferences.profilePhotoPath) {
      await preferences.setProfilePhotoPath(profilePhoto.path);
    }

    // Stable, persisted UUID. Never Platform.localHostname, which is
    // "localhost" on Android and renameable on Windows.
    final id = deviceId ?? await preferences.stableDeviceId();

    // EnrichmentService takes the synchronous NoteRepository port, so it is
    // constructed inside the isolate, not here. The adapter has to survive the
    // hop: core's adapters are const and pure Dart, a plugin-backed one is not.
    final worker = await NexDbWorker.spawn(
      dbPath: dbPath,
      deviceId: id,
      mediaDir: mediaDir,
      adapter: aiAdapter ?? AIAdapterBinding.instance,
      // `effective`, not the raw switches. The raw ones are what the
      // intelligence screen shows; they say nothing about whether the master
      // switch is on, and reading them here handed the worker all six
      // capabilities even with the layer turned off. The correction did
      // arrive — `setAiCapabilities` a few lines into bootstrap — but it
      // arrives across at least one await boundary, and a background
      // `enrichNote` scheduled inside that window ran with everything
      // enabled. A window is not a defence.
      capabilities: preferences.effectiveAiCapabilities,
    );

    final services = NexServices._(
      worker: worker,
      mediaPicker: mediaPicker ?? PlatformMediaPicker(),
      deviceId: id,
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      preferences: preferences,
    );

    // The system "Alarms & reminders" screen leaves the app, so it is shown
    // once per install — at the first reminder — and never re-shown for
    // someone who declined. The gate latches here, where the preference
    // store lives; the engine stays free of platform storage.
    services.reminders
      ..shouldRequestExactAlarms = () async {
        return !preferences.remindersExactAlarmsAsked;
      }
      ..onExactAlarmsRequested = () {
        unawaited(preferences.markRemindersExactAlarmsAsked());
      }
      // Into the file "Share diagnostics" sends. A reminder that arrives at
      // the wrong hour leaves no other trace: the note keeps the time it was
      // given, the alarm queue confirms an alarm exists but not when, and the
      // one moment that knows what the OS was actually told is the call that
      // told it.
      //
      // A block body rather than an arrow, and not a style choice:
      // `..x = (a) => f(a)` swallows the cascade after it, because the arrow's
      // body runs to the end of the expression and the next `..` then attaches
      // to `f(a)`'s result instead of to the object being cascaded.
      ..onDiagnostic = (message) {
        unawaited(noteDiagnostic(message));
      }
      // Read at schedule time rather than captured once: the lock can be
      // turned on long after a reminder was set, and every reminder is
      // rebuilt from the library on launch.
      ..hideOnLockScreen = () => preferences.appLockEnabled;

    if (recoverDrafts) {
      await services.recoverCaptureDrafts();
      await services.recoverVoiceRecordings();
      unawaited(
        getTemporaryDirectory()
            .then(cleanExportCache)
            .catchError((Object _) {}),
      );
      // Plain copies of private attachments left by a vault that never got
      // to lock (the app was killed while one was open).
      unawaited(VaultFiles.clearOpenCopies());
    }
    unawaited(services.refreshTimeline());
    unawaited(services._maybeBackupInBackground());

    return services;
  }

  /// Appends one line to the diagnostics file, and never throws.
  ///
  /// Opening the log touches the filesystem, so this is async and fired
  /// without awaiting: a reminder must not wait on a log entry, and a log
  /// that cannot be written must not become the failure it was recording.
  /// Writes one line where "Share diagnostics" will find it.
  ///
  /// Public because the bootstrap host needs it too: a share that fails while
  /// the app is starting has nowhere on screen to report itself, and the
  /// alternative — letting it propagate — turned a failed share into a
  /// "could not open your local library" screen offering Restore backup.
  static Future<void> noteDiagnostic(String message) async {
    try {
      (await NexCrashLog.open()).note(message);
    } catch (_) {
      // Best-effort, like everything else that writes to this file.
    }
  }

  @visibleForTesting
  static NexServices forTest({
    required NexDb worker,
    required String deviceId,
    required NexPreferences preferences,
    required BackupPolicy backupPolicy,
    MediaPicker? mediaPicker,
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) {
    return NexServices._(
      worker: worker,
      mediaPicker: mediaPicker ?? PlatformMediaPicker(),
      deviceId: deviceId,
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
      backupPolicy: backupPolicy,
      preferences: preferences,
    );
  }

  void applyAiPreferences(NexPreferences preferences) {
    // The master switch wins: with AI off, every capability is off regardless
    // of what the individual switches were last left at.
    unawaited(worker.setAiCapabilities(preferences.effectiveAiCapabilities));
    final ai = preferences.aiEnabled
        ? preferences.aiProvider
        : const AiProviderConfig();
    unawaited(
      worker.setAiProvider({
        ...ai.toMap(),
        // Not part of AiProviderConfig — see `aiOutputLanguage` — but it has
        // to reach the isolate that builds the adapter, and this is the one
        // message that already carries everything else the adapter needs.
        'outputLanguage': preferences.aiOutputLanguage.wireName,
      }),
    );
    // After the provider, so that the search model, when there is one, has
    // the last word on which vector space the library is in.
    final searchModel = activeSearchModel(preferences);
    unawaited(worker.setLocalEmbedder(searchModel));
    // Search can index existing text, but enabling a provider must not upload
    // photos or recordings. Their reading actions are explicit from 2.0.4.
    if (ai.isUsable) unawaited(backfillEnrichment());
    if (searchModel != null) unawaited(embedLibrary());
  }

  /// The on-device search model's file, when it is installed in a build that
  /// can run it; null otherwise. Checked against the disk, not only the
  /// preference: a model deleted by hand, or lost with a cleared app, must
  /// hand search back to the provider rather than fail every query.
  static String? activeSearchModel(NexPreferences preferences) {
    if (!LocalAi.flavorSupportsLocalModels) return null;
    final path = preferences.searchModelPath;
    if (path == null || !isSearchModelFile(path)) return null;
    if (!File(path).existsSync()) return null;
    return path;
  }

  /// The app's own models folder, once known (set at bootstrap).
  static String? modelsRoot;

  /// Whether [path] is where the model store keeps one of the search models
  /// (SEC-03). The path travels in backups: a crafted one could otherwise
  /// point the native embedder at any file, never digest-checked.
  @visibleForTesting
  static bool isSearchModelFile(String path, {String? root}) {
    final models = root ?? modelsRoot;
    if (models == null) return false;
    return NexModels.search.any(
      (model) => p.equals(path, p.join(models, model.id, model.filename)),
    );
  }

  Future<void>? _embeddingLibrary;

  /// Gives every note a vector, in rounds, until none is left without one.
  ///
  /// A new vector space starts empty — the search model taking over throws
  /// the provider's vectors away — and the ordinary backfill takes 25 notes
  /// per call, which left a library mostly unsearchable until enough
  /// launches had happened. On the phone each note costs milliseconds, so
  /// this simply keeps going. One run at a time, however often it is asked.
  Future<void> embedLibrary() => _embeddingLibrary ??= () async {
    try {
      // A bound, not an expectation: 400 rounds is 10,000 notes.
      for (var round = 0; round < 400 && !_closed; round++) {
        final done = await worker.backfillEmbeddings(limit: 25);
        if (done == 0) break;
      }
    } catch (_) {
      // The notes are untouched; they are found by their words until the
      // next launch tries again.
    } finally {
      _embeddingLibrary = null;
    }
  }();

  /// Fire-and-forget post-capture enrichment — never awaited by capture UI.
  void scheduleEnrichment(String noteId) {
    if (_closed) return;
    // Nobody awaits it, so nobody may be handed its failure either. Media
    // reading is never scheduled here; only text enrichment and indexing.
    unawaited(worker.enrichNote(noteId).catchError((Object _) {}));
  }

  /// Indexes text already available in the library, without reading media.
  /// The legacy entrypoint is kept for callers and saved preference flows.
  Future<int> backfillEnrichment({int limit = 25}) async {
    if (_closed) return 0;
    try {
      final done = await worker.backfillEnrichment(limit: limit);
      if (done > 0) await refreshTimeline();
      return done;
    } catch (_) {
      // Nothing here is worth interrupting anyone over: the notes are intact,
      // they simply have no transcript yet.
      return 0;
    }
  }

  /* --------------------------------------------------------------- notes */

  Future<Note?> getById(String id) => worker.getById(id);

  late final captureJournal = CaptureJournal(p.dirname(dbPath));

  /* ------------------------------------------------------------ cycle */

  Future<List<CyclePeriod>> cyclePeriods() => worker.cyclePeriods();

  /* -------------------------------------------------- scheduled notes */

  Timer? _scheduledTimer;

  /// Persists a manual order for exactly the notes in [orderedIds] — the
  /// currently-displayed set a Rearrange drag was performed against.

  /* ---------------------------------------------------------------- tags */

  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) => worker.addTag(noteId: noteId, name: name, color: color);

  /* ---------------------------------------------------------- threads */

  /// Named views over notes about the same thing (W5.3). None of these
  /// change a note; the timeline is refreshed only so a card can show it.
  Future<List<NoteThread>> threads() => worker.listThreads();

  /* ------------------------------------------- recurring obligations */

  /// The standing obligations — the insurance, the rent, the tablet every
  /// eight hours. Not notes and not on the timeline; see [NexCommitment].
  Future<List<NexCommitment>> commitments() => worker.listCommitments();

  /* -------------------------------------------------------------- search */

  Future<List<Note>> timeline({
    int limit = 50,
    int offset = 0,
    String? tagId,
  }) => worker.timeline(limit: limit, offset: offset, tagId: tagId);

  /* ------------------------------------------------- library maintenance */

  Future<List<Note>> deletedNotes({int limit = 200}) =>
      worker.deletedNotes(limit: limit);

  /* ---------------------------------------------------------- enrichment */

  bool get _manualLocalAi =>
      _preferences.aiEnabled &&
      !_preferences.aiProvider.isUsable &&
      ChatAdapterBinding.instance.available;

  Future<List<TagSuggestion>> suggestTags(String noteId) async {
    if (!_preferences.effectiveAiCapabilities.tagSuggestions) return const [];
    if (!_manualLocalAi) return worker.suggestTags(noteId);
    final note = await worker.getById(noteId);
    if (note == null) return const [];
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(),
      outputLanguage: _preferences.aiOutputLanguage,
    );
    try {
      final result = await adapter.suggestTags(note);
      final current = await worker.getById(noteId);
      return _manualLocalAi &&
              _preferences.effectiveAiCapabilities.tagSuggestions &&
              current?.aiSourceText == note.aiSourceText
          ? result ?? const []
          : const [];
    } catch (_) {
      return const [];
    } finally {
      adapter.close();
    }
  }

  /// How many notes [refreshTimeline] keeps in the stream.
  ///
  /// Every mutation elsewhere — capture, tag edit, delete, sync — calls
  /// [refreshTimeline] with no idea how far the timeline has been scrolled,
  /// so the window has to live here rather than as an argument threaded
  /// through every one of those call sites. Only [loadMoreTimeline] grows it,
  /// and only [trimTimelineWindow] — called once the reader is back near the
  /// top — shrinks it, so a capture or a sync elsewhere never truncates a
  /// scrolled-down timeline, and a library scrolled deep once does not make
  /// every later change re-read all of that depth.
  int _timelineWindow = timelineBaseWindow;

  /// The window the timeline starts at and returns to.
  static const timelineBaseWindow = 200;

  /// What the stream last carried, and how many full reads have started —
  /// so [loadMoreTimeline] can tell whether a page may simply be appended.
  List<Note>? _lastTimeline;

  int _timelineReads = 0;
  Future<bool>? _timelinePage;

  Future<void>? _backingUp;

  static const localBackupsKept = NexDatabase.backupRetention;

  /// How often the chosen folder gets a fresh copy (W1.6).
  static const backupFolderInterval = Duration(hours: 24);

  /// The Android side of the chosen folder. Replaced by tests.
  NexBackupFolderChannel backupFolder = const NexBackupFolderChannel();

  /// What went wrong, short enough to show: the kind of error and, for the
  /// ones Nex throws itself, its own fixed wording ("Unsafe media blob") —
  /// never a path or anything read from a note.
  static String _why(Object error) {
    final message = switch (error) {
      FormatException(:final message) => message,
      StateError(:final message) => message,
      _ => '',
    };
    final short = message.length > 60 ? message.substring(0, 60) : message;
    return short.isEmpty
        ? '${error.runtimeType}'
        : '${error.runtimeType}: $short';
  }

  // Static: a closure over `this` here would be carried into the isolate
  // below, and the preferences it reaches cannot be sent.
  static List<File> _newestBackups(String dir) =>
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.nexbak'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

  /// The last thing sync said when it failed, short enough to put in a banner.
  ///
  /// The full text goes to the diagnostics file; this is the part worth
  /// showing someone standing in front of the screen.
  static String describeFailure(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 120 ? text : '${text.substring(0, 119)}…';
  }

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    await worker.close();
  }

  Future<void> dispose() async {
    _scheduledTimer?.cancel();
    await _timelineController.close();
    await _cycleController.close();
    await _moduleController.close();
    await _moduleDraftController.close();
    await _closeOnce();
  }
}
