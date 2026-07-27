import 'package:shared_preferences/shared_preferences.dart';

/// Throttles automatic backups so they never sit on the launch path.
///
/// The composition root used to call repo.backup(backupDir) synchronously on
/// the UI isolate during bootstrap() — a full database file copy on every
/// single launch, growing without bound as the library grows.
class BackupPolicy {
  const BackupPolicy(this._prefs, {this.interval = const Duration(hours: 12)});

  final SharedPreferences _prefs;
  final Duration interval;

  static const _kLastBackup = 'backup.last_at_ms';

  Future<bool> isDue() async {
    final last = _prefs.getInt(_kLastBackup);
    if (last == null) return true;

    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= interval.inMilliseconds;
  }

  Future<void> markDone() =>
      _prefs.setInt(_kLastBackup, DateTime.now().millisecondsSinceEpoch);
}
