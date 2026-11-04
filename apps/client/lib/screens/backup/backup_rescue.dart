part of '../backup_screen.dart';

extension _BackupRescue on _BackupScreenState {
  Widget _rescueRow(AppLocalizations l) => ListTile(
    leading: const Icon(Icons.health_and_safety_outlined),
    title: Text(l.rescueBackupTitle),
    subtitle: Text(l.rescueBackupHint),
    onTap: _busy ? null : () => unawaited(_exportRescue()),
  );

  Future<List<String>> _rescueInventory(String path) async {
    try {
      return await widget.services.backupMissingMedia(path);
    } catch (_) {
      return const [];
    } // Restore itself reports malformed archives.
  }

  Future<void> _exportRescue() => _guard(() async {
    final l = AppLocalizations.of(context);
    final approved = await nexShowDialog<bool>(
      context: context,
      builder: (ctx) => NexAlertDialog(
        title: Text(l.rescueBackupTitle),
        content: NexDialogBody(child: Text(l.rescueBackupWarning)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.export),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      final result = await widget.services.exportRescueBackup();
      if (!mounted) return;
      final share = await nexShowDialog<bool>(
        context: context,
        builder: (ctx) => NexAlertDialog(
          title: Text(l.rescueBackupTitle),
          content: NexDialogBody(
            child: Text(
              '${l.rescueBackupWarning}\n\n'
              '${l.rescueBackupMissing(result.missing.length)}\n'
              '${result.missing.take(10).join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.share),
            ),
          ],
        ),
      );
      if (share != true || !mounted) return;
      await nexSendFileOut(result.path, mimeType: 'application/zip');
    } catch (error) {
      unawaited(NexCrashLog.handled('backup.rescue', error));
      _say('${l.exportFailed} (${NexServices.describeFailure(error)})');
    }
  });
}
