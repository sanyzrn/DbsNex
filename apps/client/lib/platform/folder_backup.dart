part of 'nex_services.dart';

/// The automatic copy to a chosen folder (W1.6).
extension NexFolderBackup on NexServices {
  /// Copies an encrypted complete backup into the folder the person chose,
  /// at most once a day unless [force]d. Returns whether a copy landed.
  ///
  /// The complete-backup format, with the recovery code chosen when the
  /// folder was: the library with its media, settings and service keys —
  /// never the private vault, which only ever leaves in a backup made by
  /// hand. A failure is recorded for Settings to show, and never thrown.
  Future<bool> backupToFolderIfDue({bool force = false}) async {
    final uri = _preferences.backupFolderUri;
    if (uri == null) return false;
    final last = _preferences.backupFolderLastAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < NexServices.backupFolderInterval) {
      return false;
    }
    String? output;
    try {
      // Nothing to keep yet: the first copy belongs to the first note.
      if (!force && (await worker.timeline(limit: 1)).isEmpty) return false;
      final key = await _preferences.backupFolderKey();
      if (key == null) {
        await _preferences.markBackupFolderFailed(NexBackupFolderFailure.code);
        return false;
      }
      if (!await backupFolder.reachable(uri)) {
        await _preferences.markBackupFolderFailed(
          NexBackupFolderFailure.access,
        );
        return false;
      }
      try {
        output = await exportFullBackup(
          key,
          includeModel: false,
          reuseFresh: true,
        );
      } catch (error) {
        unawaited(
          NexServices.noteDiagnostic(
            'folder backup: ${NexServices._why(error)}',
          ),
        );
        await _preferences.markBackupFolderFailed(
          NexBackupFolderFailure.backup,
          detail: NexServices._why(error),
        );
        return false;
      }
      final problem = await backupFolder.copy(
        uri,
        output,
        nexAutoBackupName(DateTime.now()),
      );
      if (problem == null) {
        await _preferences.markBackupFolderCopied();
        return true;
      }
      unawaited(NexServices.noteDiagnostic('folder backup copy: $problem'));
      await _preferences.markBackupFolderFailed(
        NexBackupFolderFailure.write,
        detail: problem,
      );
      return false;
    } catch (error) {
      unawaited(
        NexServices.noteDiagnostic(
          'folder backup failed: ${NexServices._why(error)}',
        ),
      );
      await _preferences.markBackupFolderFailed(
        NexBackupFolderFailure.backup,
        detail: NexServices._why(error),
      );
      return false;
    } finally {
      if (output != null) {
        try {
          await File(output).delete();
        } catch (_) {}
      }
    }
  }
}
