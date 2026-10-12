part of '../nex_services.dart';

/// «Cycle»'s reads and writes. Split out of NexServices (REL-10).
extension NexCycleServices on NexServices {
  /// Starts a period on [day]. A forgotten open one is closed at the
  /// expected length first.
  Future<CyclePeriod> cycleStartPeriod(DateTime day) async {
    final prediction = await cyclePrediction();
    return _cycleWrite(
      worker.cycleStartPeriod(
        day,
        closeAfter:
            prediction?.averagePeriod ?? _preferences.cycleTypicalPeriod,
      ),
    );
  }

  Future<void> cycleEndPeriod(String id, DateTime day) =>
      _cycleWrite(worker.cycleEndPeriod(id, day));

  Future<void> cycleUpdatePeriod(String id, DateTime start, DateTime? end) =>
      _cycleWrite(worker.cycleUpdatePeriod(id, start, end));

  Future<void> cycleDeletePeriod(String id) =>
      _cycleWrite(worker.cycleDeletePeriod(id));

  Future<List<CycleDayLog>> cycleDays(DateTime from, DateTime to) =>
      worker.cycleDays(from, to);

  Future<void> cycleSaveDay(CycleDayLog log) =>
      _cycleWrite(worker.cycleSaveDay(log));

  /// What the cycle screen shows, from everything logged. Null until a
  /// period has been.
  Future<CyclePrediction?> cyclePrediction({DateTime? today}) async =>
      CyclePredictor.predict(
        periods: await worker.cyclePeriods(),
        today: CycleDate.of(today ?? DateTime.now()),
        typicalCycle: _preferences.cycleTypicalLength,
        typicalPeriod: _preferences.cycleTypicalPeriod,
      );

  /// Every period, every logged day, the settings and the reminders —
  /// gone, and nothing else touched.
  Future<void> cycleDeleteAll() async {
    await worker.cycleDeleteAll();
    await reminders.cancelCycle();
    await _preferences.resetCycle();
    if (!_cycleController.isClosed) _cycleController.add(null);
    await _replaceBackupsHoldingDeleted();
  }

  /// The library backups on this phone, made before Cycle (or a module's
  /// data) was deleted, still held every period and logged day (SEC-10), and
  /// they are not encrypted:
  /// "deleted from this phone" was not true while they were there. One new
  /// backup is made without it, and only once it exists are the older ones
  /// removed, so the notes are never left without a backup. Copies saved to
  /// a folder or shared elsewhere are outside the app's reach; the
  /// confirmation says so.
  Future<void> _replaceBackupsHoldingDeleted() async {
    try {
      final dir = Directory(backupDir);
      if (!dir.existsSync()) return;
      List<File> backups() => dir
          .listSync()
          .whereType<File>()
          .where((file) => NexBackupArchive.isBackupFile(file.path))
          .toList();
      final older = backups();
      if (older.isEmpty) return;
      await worker.backup(backupDir, mediaDir: mediaDir);
      final kept = backups()
          .where((file) => !older.any((old) => old.path == file.path))
          .toList();
      if (kept.isEmpty) return;
      for (final file in older) {
        if (file.existsSync()) file.deleteSync();
      }
      NexBackupArchive.collectUnusedMedia(backupDir);
    } catch (_) {
      // Best effort: the live data is already gone, and a backup that could
      // not be replaced must never take the notes' backups with it.
    }
  }
}
