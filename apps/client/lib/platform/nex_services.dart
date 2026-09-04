import 'dart:async';
import 'dart:isolate';
import 'dart:io';

// foundation exports its own Summary (a diagnostics type); the one this file
// returns is nex_core's AI summary.
import 'package:flutter/foundation.dart' hide Summary;
import 'package:meta/meta.dart' show useResult;
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'backup_policy.dart';
import 'db_worker.dart';
import 'ai_provider.dart';
import 'nex_db.dart';
import 'media_picker_impl.dart';
import 'crash_reporter.dart';
import 'nex_preferences.dart';
import 'model_store.dart';
import 'reminders.dart';

/// Thrown when sync is invoked before the device has been paired with a server.
class SyncNotConfigured implements Exception {
  const SyncNotConfigured();

  @override
  String toString() =>
      'Sync is not configured. Pair this device with a Nex server first.';
}

/// Returned by [NexServices.restoreBackup] so a restore cannot silently leave a
/// dead service graph in place. The caller must feed it to NexRestartScope.
@immutable
class RestartRequired {
  const RestartRequired();
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

  /// Whether the intelligence layer is on and actually has a provider behind
  /// it. The UI asks so it does not offer a control that cannot do anything.
  bool get aiIsUsable =>
      _preferences.aiEnabled && aiTextAvailableWith(_preferences.aiProvider);

  final _timelineController = StreamController<List<Note>>.broadcast();
  Stream<List<Note>> get timelineStream => _timelineController.stream;

  bool _closed = false;

  /// [aiAdapter] is injected from Core types only. Defaults to
  /// [AIAdapterBinding.instance] (NullAIAdapter until a composition root binds
  /// an on-device or cloud adapter).
  static Future<NexServices> bootstrap({
    String? deviceId,
    required NexPreferences preferences,
    AIAdapter? aiAdapter,
    MediaPicker? mediaPicker,
  }) async {
    if (!kIsWeb &&
        (Platform.isAndroid || Platform.isIOS || Platform.isWindows)) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final support = await getApplicationSupportDirectory();
    final dbPath = p.join(support.path, 'nex.sqlite');
    final mediaDir = p.join(support.path, 'media');
    final backupDir = p.join(support.path, 'backups');

    // Async filesystem APIs — createSync blocked the UI isolate.
    await Directory(mediaDir).create(recursive: true);
    await Directory(backupDir).create(recursive: true);

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
      capabilities: preferences.aiCapabilities,
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
        unawaited(_noteDiagnostic(message));
      }
      // Read at schedule time rather than captured once: the lock can be
      // turned on long after a reminder was set, and every reminder is
      // rebuilt from the library on launch.
      ..hideOnLockScreen = () => preferences.appLockEnabled;

    unawaited(services.refreshTimeline());
    unawaited(services._maybeBackupInBackground());

    return services;
  }

  /// Appends one line to the diagnostics file, and never throws.
  ///
  /// Opening the log touches the filesystem, so this is async and fired
  /// without awaiting: a reminder must not wait on a log entry, and a log
  /// that cannot be written must not become the failure it was recording.
  static Future<void> _noteDiagnostic(String message) async {
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
        'provider': ai.provider.wireName,
        'apiKey': ai.apiKey,
        'baseUrl': ai.baseUrl,
        'model': ai.model,
        // Not part of AiProviderConfig — see `aiOutputLanguage` — but it has
        // to reach the isolate that builds the adapter, and this is the one
        // message that already carries everything else the adapter needs.
        'outputLanguage': preferences.aiOutputLanguage.wireName,
      }),
    );
    // Turning it on has to mean something for the notes that are already here.
    // Enrichment is a capture-time step, so without this the layer would only
    // ever read notes captured after the moment it was configured — and every
    // recording made before that would stay untranscribed for good.
    if (ai.isUsable) unawaited(backfillEnrichment());
  }

  /// Fire-and-forget post-capture enrichment — never awaited by capture UI.
  void scheduleEnrichment(String noteId) {
    unawaited(worker.enrichNote(noteId));
  }

  /// Works through the notes the intelligence layer has never read.
  ///
  /// Bounded per call and safe to repeat: each pass takes the newest notes
  /// still missing their derived text, so calling it again picks up where the
  /// last one stopped.
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

  Future<Note?> captureText(String content) => worker.captureText(content);

  Future<Note?> captureChecklist(List<ChecklistItem> items) =>
      worker.captureChecklist(items);

  Future<Note?> captureLink(String url) => worker.captureLink(url);

  /// Imports another app's export, and answers how many notes landed.
  Future<int> importNotes(String path) =>
      worker.importNotes(path, mediaDir: mediaDir);

  Future<Note> captureVoice({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  }) => worker.captureVoice(
    mediaUri: mediaUri,
    mediaBytes: mediaBytes,
    durationMs: durationMs,
  );

  Future<Note> capturePhoto({
    required String mediaUri,
    required Uint8List mediaBytes,
  }) => worker.capturePhoto(mediaUri: mediaUri, mediaBytes: mediaBytes);

  Future<Note> captureFile({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  }) => worker.captureFile(
    mediaUri: mediaUri,
    mediaBytes: mediaBytes,
    originalFilename: originalFilename,
    mimeType: mimeType,
  );

  Future<void> updateNote(String id, String content) async {
    await worker.updateNote(id, content);
    // The pending notification carries the note's text, baked in when it was
    // scheduled. An edit that did not re-schedule left a reminder whose
    // notification said something the note had already stopped saying until
    // the next launch happened to rebuild it. The alarm instant is unchanged;
    // only its payload is refreshed.
    try {
      final note = await worker.getById(id);
      if (note != null && note.dueAt != null) {
        await reminders.schedule(note);
      }
    } catch (_) {}
    await refreshTimeline();
  }

  /// Soft-deletes a note and cancels whatever alarm it still had pending.
  ///
  /// The alarm used to survive the note: the OS keeps its own schedule, the
  /// library is only consulted to rebuild, and nothing in the delete path
  /// told the scheduler anything — so a deleted note's reminder still fired,
  /// tapped through to nothing, and the plugin's boot receiver re-armed it
  /// again at every reboot. Cancelling here is what makes the library the
  /// record it claims to be: if the note is not in it, no alarm exists.
  Future<void> deleteNote(String id) async {
    await worker.deleteNote(id);
    // Best-effort: the row is already soft-deleted, so a failure here must
    // not roll the visible state back; the next reconcile would catch it.
    try {
      await reminders.cancel(id);
    } catch (_) {}
    await refreshTimeline();
  }

  /// Undoes a soft delete, and re-arms the note's alarm if it has one.
  Future<void> undelete(String id) async {
    await worker.undelete(id);
    // The delete path cancelled the alarm (as it must). Restoring the note
    // without restoring its reminder would make delete lose data — the one
    // thing an undo is not allowed to do. A past-due one-off stays quiet,
    // matching [NexReminders.schedule]'s own rule for missed reminders.
    try {
      final note = await worker.getById(id);
      if (note != null && note.dueAt != null) {
        await reminders.schedule(note);
      }
    } catch (_) {}
    await refreshTimeline();
  }

  /// Sets or clears when a note should come back up, and moves the alarm to
  /// match. Both halves or neither: a due date with no alarm behind it is a
  /// reminder that never arrives, and an alarm with no due date is one that
  /// cannot be seen or cancelled.
  Future<void> setDueAt(
    String id,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) async {
    await worker.setDueAt(id, when, repeat: repeat);
    final note = await worker.getById(id);
    if (note == null) return;
    if (when == null) {
      await reminders.cancel(id);
    } else {
      await reminders.schedule(note);
    }
    await refreshTimeline();
  }

  /// Puts every pending alarm back from the library. Run at launch — an OS
  /// alarm does not survive a reinstall or a restore, and the note does.
  Future<void> restoreReminders() async {
    if (!NexReminders.supported) return;
    try {
      await reminders.syncFromLibrary(await worker.upcomingReminders());
    } catch (_) {
      // A library that cannot be read here is a library the timeline will
      // fail to read too, and that path already reports it.
    }
  }

  Future<void> setCaption(String id, String caption) =>
      worker.setCaption(id, caption);

  Future<void> setTitle(String id, String? title) => worker.setTitle(id, title);

  Future<void> summarizeInto(String id, String summary) =>
      worker.setSummaryText(id, summary);

  Future<void> setLinkMetadata(String id, {String? title, String? excerpt}) =>
      worker.setLinkMetadata(id, title: title, excerpt: excerpt);

  Future<void> toggleChecklistItem(String id, int index) =>
      worker.toggleChecklistItem(id, index);

  /// Pins [id] when fewer than five notes are already pinned.
  Future<bool> pinNote(String id) => worker.pinNote(id);

  Future<void> unpinNote(String id) => worker.unpinNote(id);

  Future<int> pinnedNoteCount() => worker.pinnedNoteCount();

  /// Persists a manual order for exactly the notes in [orderedIds] — the
  /// currently-displayed set a Rearrange drag was performed against.
  /* ---------------------------------------------------------------- tags */

  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) => worker.addTag(noteId: noteId, name: name, color: color);

  Future<void> removeTag({required String noteId, required String tagId}) =>
      worker.removeTag(noteId: noteId, tagId: tagId);

  Future<Tag> createTag(String name, {String? color}) =>
      worker.createTag(name, color: color);

  Future<List<Tag>> listTags() => worker.listTags();

  Future<void> setTagColor({required String tagId, String? color}) =>
      worker.setTagColor(tagId: tagId, color: color);

  /* -------------------------------------------------------------- search */

  Future<List<Note>> timeline({
    int limit = 50,
    int offset = 0,
    String? tagId,
  }) => worker.timeline(limit: limit, offset: offset, tagId: tagId);

  Future<List<Note>> search(SearchFilters filters) => worker.search(filters);

  /* ------------------------------------------------- library maintenance */

  Future<List<Note>> deletedNotes({int limit = 200}) =>
      worker.deletedNotes(limit: limit);

  Future<void> purgeDeletedBefore(DateTime cutoff) =>
      worker.purgeDeletedBefore(cutoff);

  Future<void> purgeNote(String id) => worker.purgeNote(id);

  Future<void> purgeAllDeleted() => worker.purgeAllDeleted();

  /// Clears attachment files no note points at any more, at most once a day.
  ///
  /// Purging a note deletes its file now, so from here on nothing is left
  /// behind. This is for what was left behind *before* that: every install
  /// upgrading from an earlier version carries the photos and recordings of
  /// every note it ever deleted for good, and no amount of deleting things
  /// correctly from now on will reach them. It also catches the rarer strays
  /// — a capture whose file was written and whose row then failed, or a purge
  /// whose unlink lost a race with a file handle.
  ///
  /// Throttled because it walks the media directory and stats every file in
  /// it: worth doing, not worth doing on every launch. Called away from the
  /// critical path — nothing waits on it, and a failure is not worth
  /// reporting, since the next sweep does the same work again.
  ///
  /// Returns how many files went, or zero when it was not due.
  Future<int> sweepOrphanMediaIfDue({
    Duration interval = const Duration(hours: 24),
  }) async {
    if (!_preferences.mediaSweepDue(interval)) return 0;
    // Marked before the walk, not after. A sweep that throws halfway has
    // still deleted whatever it deleted, and retrying it on every launch
    // because it never got to write a timestamp is how a background chore
    // turns into a launch cost.
    await _preferences.markMediaSwept();
    return worker.sweepOrphanMedia();
  }

  Future<List<TagUsage>> tagUsage() => worker.tagUsage();

  Future<void> renameTag(String id, String name) => worker.renameTag(id, name);

  Future<void> mergeTag({required String sourceId, required String targetId}) =>
      worker.mergeTag(sourceId: sourceId, targetId: targetId);

  Future<void> deleteTag(String id) => worker.deleteTag(id);

  Future<Note?> nearestMiss(String query) => worker.nearestMiss(query);

  /// What the library is made of, the offline model included.
  ///
  /// The model is measured here rather than in the repository: it lives in
  /// the app's support directory, which the database has no business knowing
  /// about, and it is also the single largest thing most installations will
  /// ever hold — a storage figure that quietly leaves out two gigabytes is
  /// worse than no figure at all, which is what made the old row useless.
  ///
  /// A failure to read that directory costs the breakdown one row rather than
  /// the whole screen: nothing about a storage figure is worth an error page.
  Future<StorageSnapshot> storage() async {
    final snapshot = await worker.storage(
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    try {
      return snapshot.withModels(await NexModelStore.totalInstalledBytes());
    } catch (_) {
      return snapshot;
    }
  }

  /* ---------------------------------------------------------- enrichment */

  Future<List<TagSuggestion>> suggestTags(String noteId) =>
      worker.suggestTags(noteId);

  Future<Summary?> summarizeOnDemand(String noteId) =>
      worker.summarizeOnDemand(noteId);

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      worker.relatedNotes(noteId, limit: limit);

  Future<List<SemanticHit>> semanticSearch(String query, {int limit = 20}) =>
      worker.semanticSearch(query, limit: limit);

  /// How many notes [refreshTimeline] keeps in the stream.
  ///
  /// Every mutation elsewhere — capture, tag edit, delete, sync — calls
  /// [refreshTimeline] with no idea how far the timeline has been scrolled,
  /// so the window has to live here rather than as an argument threaded
  /// through every one of those call sites. Only [loadMoreTimeline] grows it;
  /// nothing shrinks it, so a capture or a sync elsewhere never truncates a
  /// scrolled-down timeline back to the first page.
  int _timelineWindow = 200;

  Future<void> refreshTimeline() async {
    if (_closed) return;
    _timelineController.add(await worker.timeline(limit: _timelineWindow));
  }

  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      worker.loadMore(offset: offset, limit: limit);

  /// The scroll-to-bottom half of pagination: fetches the page past the
  /// current window with [loadMore], and — only if that page was not empty —
  /// grows the window and reloads through the same [refreshTimeline] every
  /// other mutation uses, so the result is the one canonical ordering rather
  /// than a hand-appended list that could drift from it.
  ///
  /// Returns false once a fetch turns up nothing to add, so the caller —
  /// [TimelineScreenState] — knows to stop asking until something changes.
  Future<bool> loadMoreTimeline({int by = 50}) async {
    if (_closed) return false;
    final more = await worker.loadMore(offset: _timelineWindow, limit: by);
    if (more.isEmpty) return false;
    _timelineWindow += more.length;
    await refreshTimeline();
    return true;
  }

  /// Backup is throttled and runs off the launch path, inside the worker
  /// isolate. It used to be a synchronous full-file copy on every launch.
  Future<void> _maybeBackupInBackground() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    if (_closed) return;
    await backupIfDue();
  }

  /// The decision itself, without the launch delay in front of it. Returns
  /// whether a backup was actually written.
  ///
  /// Split out from [_maybeBackupInBackground] so it can be exercised without
  /// a test having to wait five real seconds for it.
  @visibleForTesting
  Future<bool> backupIfDue() async {
    try {
      if (!await _backupPolicy.isDue()) return false;
      // Nothing worth protecting yet. The policy is due the first time it is
      // ever asked — which is right, a new library should not wait twelve
      // hours for its first backup — but on a brand-new install that lands
      // five seconds in, on an empty database, and Settings then greets a
      // first-time user with "1 backup" holding nothing at all. The clock is
      // deliberately left unmarked too: the first backup belongs to the first
      // note, not to twelve hours after the app was first opened.
      final anything = await worker.timeline(limit: 1);
      if (anything.isEmpty) return false;
      await worker.backup(backupDir, mediaDir: mediaDir);
      await _backupPolicy.markDone();
      return true;
    } catch (_) {
      // Fail open — never block or crash the app on backup.
      return false;
    }
  }

  /// Writes the whole library to a zip and returns its path.
  ///
  /// The file lands in the cache directory rather than the system temp root:
  /// on Android the share provider is configured for app storage, and a file
  /// under `/tmp` could not be handed to another app at all.
  Future<String> exportNow() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(':', '-');
    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, 'Nex-$stamp.zip');
    return worker.exportArchive(outputPath: out, mediaRoot: mediaDir);
  }

  /// Reads an exported archive back into this library.
  ///
  /// Additive: notes already here are left alone, so importing the same file
  /// twice changes nothing. Media is copied into this device's media folder.
  Future<ImportResult> importArchive(String archivePath) async {
    final result = await worker.importArchive(
      archivePath: archivePath,
      mediaRoot: mediaDir,
    );
    await refreshTimeline();
    return result;
  }

  /// Takes a backup right now, outside the once-a-day policy.
  Future<void> backupNow() async {
    await worker.backup(backupDir, mediaDir: mediaDir);
    await _backupPolicy.markDone();
  }

  /// Runs a sync cycle against the user-configured endpoint.
  ///
  /// There is no default endpoint: http://127.0.0.1:4000 resolved to the device
  /// itself and is blocked as cleartext on Android 9+. Release builds refuse a
  /// non-HTTPS endpoint outright.
  Future<SyncResult> syncNow({String? baseUrl, String? bearerToken}) async {
    final url = baseUrl ?? _preferences.syncBaseUrl;
    if (url == null || url.isEmpty) throw const SyncNotConfigured();

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) throw const SyncNotConfigured();

    if (uri.scheme != 'https' && kReleaseMode) {
      throw StateError('Refusing to sync over cleartext in a release build.');
    }

    final SyncResult result;
    try {
      result = await worker.sync(
        baseUrl: url,
        bearerToken: bearerToken ?? _preferences.syncBearerToken,
      );
    } catch (error) {
      // Recorded before it is rethrown, because every caller catches this
      // with `catch (_)` and shows one sentence that names neither the
      // operation nor the reason. The banner is also transient: it appears
      // at the top of whatever screen you are on and is gone before you have
      // worked out what it was about. The server's own words — a status code,
      // a constraint name — survive here, in the file "Share diagnostics"
      // sends, so a failure can still be read after the banner has gone.
      unawaited(_noteDiagnostic('sync failed: $error'));
      rethrow;
    }
    await refreshTimeline();
    return result;
  }

  /// The last thing sync said when it failed, short enough to put in a banner.
  ///
  /// The full text goes to the diagnostics file; this is the part worth
  /// showing someone standing in front of the screen.
  static String describeFailure(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 120 ? text : '${text.substring(0, 119)}…';
  }

  /// Newest-first list of local SQLite backup files (FR-7.2).
  ///
  /// Synchronous, like the retention sweep in [NexDatabase.createBackup]
  /// already is: a handful of files in one directory does not need the
  /// stream machinery `Directory.list()` brings with it.
  Future<List<File>> listBackups() async {
    final dir = Directory(backupDir);
    if (!dir.existsSync()) return const [];

    final entries =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => NexBackupArchive.isBackupFile(f.path))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    return entries;
  }

  /// Removes one local backup file. Plain filesystem I/O, the same as the
  /// export path already does (`nexSendFileOut`) — a backup is not part of
  /// the note database the worker isolate guards.
  Future<void> deleteBackup(File backup) async => backup.deleteSync();

  Future<RestartRequired> restoreLatestBackup() async {
    final backups = await listBackups();
    if (backups.isEmpty) throw StateError('No backups available');
    return restoreBackup(backups.first);
  }

  /// Restores from [backup] and invalidates this service graph.
  ///
  /// The caller MUST rebuild via NexRestartScope.of(context).restart(). The
  /// [RestartRequired] return value makes that contract explicit — previously
  /// restore closed the database and returned void, leaving every field
  /// dangling, and dispose() then closed the same handle a second time.
  ///
  /// The restore itself runs in a background isolate: decoding the zip,
  /// `PRAGMA integrity_check` on the staged copy and copying the media are
  /// all work big enough to drop frames, and this was the one path that
  /// still did them on the UI isolate. The worker is closed first — the swap
  /// needs no live handle and must not race one — so a failure past this
  /// point is a dead session regardless; the error still propagates so the
  /// caller can say what happened instead of bricking silently.
  @useResult
  Future<RestartRequired> restoreBackup(File backup) async {
    await _closeOnce();
    final dbPath = this.dbPath;
    final mediaDir = this.mediaDir;
    final backupPath = backup.path;
    await Isolate.run(
      () => NexBackupArchive.restore(
        liveDbPath: dbPath,
        mediaDir: mediaDir,
        backupFile: backupPath,
      ),
    );
    return const RestartRequired();
  }

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    await worker.close();
  }

  Future<void> dispose() async {
    await _timelineController.close();
    await _closeOnce();
  }
}
