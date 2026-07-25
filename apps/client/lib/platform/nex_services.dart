import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// App-wide services. Local-only — no network (Phase 1.8).
class NexServices {
  NexServices._({
    required this.db,
    required this.repo,
    required this.capture,
    required this.tags,
    required this.search,
    required this.dbPath,
    required this.mediaDir,
    required this.backupDir,
  });

  final NexDatabase db;
  final NoteRepository repo;
  final CaptureService capture;
  final TagService tags;
  final SearchService search;
  final String dbPath;
  final String mediaDir;
  final String backupDir;

  final _timelineController = StreamController<List<Note>>.broadcast();

  Stream<List<Note>> get timelineStream => _timelineController.stream;

  static Future<NexServices> bootstrap({String? deviceId}) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows)) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final support = await getApplicationSupportDirectory();
    final dbPath = p.join(support.path, 'nex.sqlite');
    final mediaDir = p.join(support.path, 'media');
    final backupDir = p.join(support.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);

    final db = NexDatabase.open(dbPath);
    final id = deviceId ?? Platform.localHostname;
    final repo = NoteRepository(db, localDeviceId: id);
    final services = NexServices._(
      db: db,
      repo: repo,
      capture: CaptureService(repo, deviceId: id),
      tags: TagService(repo),
      search: SearchService(repo),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    services.refreshTimeline();
    // Automatic rotating backup on launch (FR-7.1).
    try {
      services.repo.backup(backupDir);
    } catch (_) {
      // Fail open — never block launch on backup (06-development error handling).
    }
    return services;
  }

  static NexServices forTest({
    required NexDatabase db,
    required NoteRepository repo,
    required CaptureService capture,
    required TagService tags,
    required SearchService search,
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) {
    return NexServices._(
      db: db,
      repo: repo,
      capture: capture,
      tags: tags,
      search: search,
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  void refreshTimeline() {
    _timelineController.add(search.timeline(limit: 200));
  }

  List<Note> loadMore({required int offset, int limit = 50}) {
    return search.timeline(limit: limit, offset: offset);
  }

  Future<File> exportNow() {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final out = p.join(
      Directory.systemTemp.path,
      'nex-export-$stamp.zip',
    );
    return repo.exportArchive(outputPath: out, mediaRoot: mediaDir);
  }

  String get deviceId => capture.deviceId;

  /// Phase 2: flush outbox and pull remote deltas.
  Future<SyncResult> syncNow({String baseUrl = 'http://127.0.0.1:4000'}) async {
    final client = SyncClient(
      baseUrl: baseUrl,
      deviceId: deviceId,
      repo: repo,
    );
    try {
      final result = await client.sync();
      refreshTimeline();
      return result;
    } finally {
      client.close();
    }
  }

  void restoreLatestBackup() {
    final dir = Directory(backupDir);
    if (!dir.existsSync()) {
      throw StateError('No backups available');
    }
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (backups.isEmpty) {
      throw StateError('No backups available');
    }
    db.close();
    NexDatabase.restoreFromBackup(
      liveDbPath: dbPath,
      backupFile: backups.first.path,
    );
  }

  void dispose() {
    _timelineController.close();
    db.close();
  }
}
