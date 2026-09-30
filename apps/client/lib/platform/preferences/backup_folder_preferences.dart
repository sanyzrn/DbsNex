part of '../nex_preferences.dart';

/// The folder automatic backups are copied into (W1.6).
mixin _BackupFolderPreferences on _PreferencesStore {
  // The folder automatic backups are copied into (W1.6). The grant is this
  // phone's, so none of it travels in a backup.
  static const _kBackupFolderUri = 'backup_folder.uri';
  static const _kBackupFolderName = 'backup_folder.name';
  static const _kBackupFolderLastAt = 'backup_folder.last_at_ms';
  static const _kBackupFolderFailedAt = 'backup_folder.failed_at_ms';
  static const _kBackupFolderFailure = 'backup_folder.failure';
  static const _kBackupFolderKey = 'nex.backup_folder.key';

  String? get backupFolderUri => _prefs.getString(_kBackupFolderUri);
  String get backupFolderName => _prefs.getString(_kBackupFolderName) ?? '';

  /// When the last copy landed, or null if none has.
  DateTime? get backupFolderLastAt => _millis(_kBackupFolderLastAt);

  /// When the last attempt failed, if it failed after the last success.
  DateTime? get backupFolderFailedAt => _millis(_kBackupFolderFailedAt);

  /// What went wrong with that attempt, as [NexBackupFolderFailure]'s name,
  /// with the device's own words after a colon when there are any.
  String? get backupFolderFailure => _prefs.getString(_kBackupFolderFailure);

  /// The recovery code every automatic backup is encrypted with, kept where
  /// the API keys are.
  Future<String?> backupFolderKey() =>
      _secureStorage.read(key: _kBackupFolderKey);

  Future<void> setBackupFolder({
    required String uri,
    required String name,
    required String key,
  }) async {
    await _secureStorage.write(key: _kBackupFolderKey, value: key);
    if (await _secureStorage.read(key: _kBackupFolderKey) != key) {
      throw StateError('Cannot keep the recovery code');
    }
    await _prefs.setString(_kBackupFolderUri, uri);
    await _prefs.setString(_kBackupFolderName, name);
    await _prefs.remove(_kBackupFolderLastAt);
    await _prefs.remove(_kBackupFolderFailedAt);
    await _prefs.remove(_kBackupFolderFailure);
    notifyListeners();
  }

  Future<void> clearBackupFolder() async {
    await _secureStorage.delete(key: _kBackupFolderKey);
    for (final key in [
      _kBackupFolderUri,
      _kBackupFolderName,
      _kBackupFolderLastAt,
      _kBackupFolderFailedAt,
      _kBackupFolderFailure,
    ]) {
      await _prefs.remove(key);
    }
    notifyListeners();
  }

  Future<void> markBackupFolderCopied() async {
    await _prefs.setInt(
      _kBackupFolderLastAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _prefs.remove(_kBackupFolderFailedAt);
    await _prefs.remove(_kBackupFolderFailure);
    notifyListeners();
  }

  Future<void> markBackupFolderFailed(
    NexBackupFolderFailure why, {
    String? detail,
  }) async {
    await _prefs.setInt(
      _kBackupFolderFailedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _prefs.setString(
      _kBackupFolderFailure,
      detail == null ? why.name : '${why.name}:$detail',
    );
    notifyListeners();
  }
}
