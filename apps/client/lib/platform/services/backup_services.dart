part of '../nex_services.dart';

/// Backups, export, restore and sync — the library leaving and coming back.
/// Split out of NexServices (REL-10).
extension NexBackupServices on NexServices {
  Future<void> _maybeBackupInBackground() => Future<void>.delayed(
    const Duration(seconds: 5),
  ).then((_) => backupWhenDue());

  /// Both automatic backups, each when its interval has passed — at launch
  /// and on every return to the app. Launch alone left someone who reopens
  /// Nex from recent apps without a backup for days.
  Future<void> backupWhenDue() => _closed
      ? Future<void>.value()
      : _backingUp ??= _backUpBoth().whenComplete(() => _backingUp = null);

  Future<void> _backUpBoth() async {
    await backupIfDue();
    if (!_closed) await backupToFolderIfDue();
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
      // A library whose every note is set aside is not empty.
      final anything = await worker.timeline(limit: 1);
      if (anything.isEmpty && await worker.setAsideCount() == 0) return false;
      await worker.backup(backupDir, mediaDir: mediaDir);
      await _backupPolicy.markDone();
      return true;
    } catch (error) {
      unawaited(NexCrashLog.handled('backup.automatic', error));
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
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final dir = await getTemporaryDirectory();
    await cleanExportCache(dir);
    final out = p.join(dir.path, 'Nex-$stamp.zip');
    return worker.exportArchive(outputPath: out, mediaRoot: mediaDir);
  }

  Future<String> exportFullBackup(
    String key, {
    required bool includeModel,
    bool includeVault = false,
    bool reuseFresh = false,
  }) async {
    final settings = _preferences.backupSettings();
    if (includeVault) settings['vault'] = await VaultStore().backup();
    // The folder's copy reuses a restore point made moments ago rather than
    // adding one: with five kept, a second point a day pushed history out.
    final fresh = NexServices._newestBackups(backupDir).firstOrNull;
    if (!reuseFresh ||
        fresh == null ||
        DateTime.now().difference(fresh.lastModifiedSync()) >
            const Duration(minutes: 5)) {
      await worker.backup(backupDir, mediaDir: mediaDir);
      await _backupPolicy.markDone();
    }
    final backups = NexServices._newestBackups(backupDir);
    final library = await portableBackup(backups.first);
    final cache = await getTemporaryDirectory();
    final output = p.join(
      cache.path,
      'Nex-${DateTime.now().microsecondsSinceEpoch}.nexfull',
    );
    final store = await NexModelStore.open();
    // The model in use, if it is on the phone — the one a restore should
    // bring back working.
    final chosen = store.selected;
    final model = includeModel && store.isInstalled(chosen)
        ? store.fileFor(chosen).path
        : null;
    await Isolate.run(
      () => FullBackup.create(
        library: library,
        output: output,
        settings: settings,
        key: key,
        model: model,
        modelHash: model == null ? null : chosen.sha256,
      ),
    );
    return output;
  }

  @useResult
  Future<RestartRequired> restoreFullBackup(
    File source,
    String key, {
    bool allowVaultRestore = false,
    Future<bool> Function()? authorizeVaultRestore,
  }) async {
    final cache = await getTemporaryDirectory();
    final staging = await cache.createTemp('.nex-portable-full-');
    var recoveryStarted = false;
    try {
      final path = staging.path;
      // Which model the backup carries, from its unencrypted header; unpack
      // then verifies the file against that model's own digest and size, so
      // a header that lies only fails the restore.
      final backedUp =
          NexModels.bySha256(FullBackup.modelHashOf(source.path)) ??
          NexModels.standard;
      final settings = await Isolate.run(
        () => FullBackup.unpack(
          source.path,
          path,
          key,
          modelHash: backedUp.sha256,
          modelBytes: backedUp.sizeBytes,
        ),
      );
      NexPreferences.validateBackupSettings(settings);
      if (settings.containsKey('vault') &&
          !allowVaultRestore &&
          !(await authorizeVaultRestore?.call() ?? false)) {
        throw VaultAuthenticationRequired();
      }
      // A secure undo journal survives force-close between library, preference
      // and model installation. Bootstrap rolls the whole restore back if the
      // final commit marker was never cleared.
      final safety = await Directory(backupDir).createTemp('full-restore-');
      await worker.backup(safety.path, mediaDir: mediaDir);
      final safetyLibrary = safety
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.nexbak'))
          .path;
      await _preferences.beginRestoreRecovery(
        safetyLibrary,
        includeVault: settings.containsKey('vault'),
      );
      recoveryStarted = true;
      final result = await restoreBackup(File(p.join(path, 'library.nexbak')));
      if (result.error != null) return result;
      try {
        await _preferences.restoreSettings(settings);
        final model = File(p.join(path, 'model.litertlm'));
        if (await model.exists()) {
          final store = await NexModelStore.open();
          final target = store.fileFor(backedUp);
          await target.parent.create(recursive: true);
          // Stage beside the destination so rename remains atomic across volumes.
          final pending = await model.copy('${target.path}.restore');
          await pending.rename(target.path);
          await store.select(backedUp);
        }
      } catch (error) {
        // The restart path reads the secure journal and restores the original
        // library and settings together, even after another process death.
        return RestartRequired(error: NexServices.describeFailure(error));
      }
      try {
        await _preferences.finishRestoreRecovery();
      } catch (error) {
        return RestartRequired(error: NexServices.describeFailure(error));
      }
      try {
        if (p.isWithin(backupDir, safety.path)) {
          await safety.delete(recursive: true);
        }
      } catch (_) {
        /* A leftover safety copy does not invalidate a committed restore. */
      }
      return const RestartRequired();
    } catch (error) {
      if (_closed) {
        return RestartRequired(error: NexServices.describeFailure(error));
      }
      if (recoveryStarted) await _preferences.finishRestoreRecovery();
      rethrow;
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {
        /* Export-cache cleanup retries stale staging directories. */
      }
    }
  }

  Future<String> portableBackup(File backup) async {
    if (backup.path.endsWith('.sqlite')) return backup.path;
    final cache = await getTemporaryDirectory();
    await cleanExportCache(cache);
    final output = p.join(
      cache.path,
      'Nex-backup-${DateTime.now().microsecondsSinceEpoch}.nexbak',
    );
    final source = backup.path;
    return Isolate.run(() => NexBackupArchive.portable(source, output));
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
    // An archive carries reminders and recurring items; their alarms are
    // this device's to set.
    await restoreReminders();
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
      unawaited(
        NexServices.noteDiagnostic('sync failed: ${error.runtimeType}'),
      );
      rethrow;
    }
    await refreshTimeline();
    return result;
  }

  /// Newest-first list of local SQLite backup files (FR-7.2).
  ///
  /// Synchronous, like the retention sweep in [NexDatabase.createBackup]
  /// already is: a handful of files in one directory does not need the
  /// stream machinery `Directory.list()` brings with it.
  Future<List<File>> listBackups() async {
    final dir = Directory(backupDir);
    if (!dir.existsSync()) return const [];

    final safetyDir = Directory(p.join(backupDir, 'before-restore'));
    final entries =
        [...dir.listSync(), if (safetyDir.existsSync()) ...safetyDir.listSync()]
            .whereType<File>()
            .where((f) => NexBackupArchive.isBackupFile(f.path))
            .toList()
          ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return entries;
  }

  /// Removes one local backup file. Plain filesystem I/O, the same as the
  /// export path already does (`nexSendFileOut`) — a backup is not part of
  /// the note database the worker isolate guards.
  Future<void> deleteBackup(File backup) async {
    await backup.delete();
    final parent = backup.parent.path;
    await Isolate.run(() => NexBackupArchive.collectUnusedMedia(parent));
  }

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
    // A selected recovery copy may itself be the oldest file in the safety
    // folder. Preserve it before that folder's retention sweep runs.
    File? selectedCopy;
    if (p.equals(p.dirname(backup.path), p.join(backupDir, 'before-restore'))) {
      selectedCopy = await backup.copy(
        p.join(
          backup.parent.path,
          '.restore-source-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await selectedCopy.setLastModified(DateTime.now());
    }
    try {
      // Separate retention folder: making the safety copy must not prune the
      // older backup the user has just selected for restoration.
      await worker.backup(
        p.join(backupDir, 'before-restore'),
        mediaDir: this.mediaDir,
      );
      await _closeOnce();
      final dbPath = this.dbPath;
      final mediaDir = this.mediaDir;
      final backupPath = selectedCopy?.path ?? backup.path;
      try {
        await Isolate.run(
          () => NexBackupArchive.restore(
            liveDbPath: dbPath,
            mediaDir: mediaDir,
            backupFile: backupPath,
          ),
        );
        return const RestartRequired();
      } catch (error) {
        // Rollback has already restored the live files. The caller must reopen
        // the service graph on failure just as it must after a successful swap.
        return RestartRequired(error: NexServices.describeFailure(error));
      }
    } finally {
      if (selectedCopy != null && await selectedCopy.exists()) {
        await selectedCopy.delete();
      }
    }
  }
}
