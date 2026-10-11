part of '../backup_screen.dart';

/// The sheets and the summary at the top of [BackupScreen].
extension _BackupSections on _BackupScreenState {
  /// The folder: what it is and the button to choose one, or — once there
  /// is one — what can be done with it.
  Future<void> _openFolder() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final set = widget.preferences.backupFolderUri != null;
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.backupFolderTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: NexSpacing.sm),
            Text(
              l10n.backupFolderExplained,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            if (!set)
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheet, 'choose'),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(l10n.backupFolderChoose),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(l10n.backupFolderCopyNow),
                onTap: () => Navigator.pop(sheet, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l10n.backupFolderShowKey),
                onTap: () => Navigator.pop(sheet, 'key'),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: Text(l10n.backupFolderChange),
                onTap: () => Navigator.pop(sheet, 'choose'),
              ),
              ListTile(
                leading: Icon(
                  Icons.folder_off_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.backupFolderStop,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => Navigator.pop(sheet, 'stop'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'choose':
        await _chooseFolder();
      case 'copy':
        await _copyToFolderNow();
      case 'key':
        await _showFolderKey();
      case 'stop':
        await _stopFolder();
    }
  }

  /// One restore point: restore it, send it somewhere, or delete it.
  Future<void> _openBackup(File backup) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_stamp(backup), style: theme.textTheme.titleLarge),
            const SizedBox(height: NexSpacing.xs),
            Text(
              _detail(l10n, backup),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l10n.restore),
              onTap: () => Navigator.pop(sheet, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: Text(l10n.share),
              onTap: () => Navigator.pop(sheet, 'share'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                l10n.deleteBackup,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'restore':
        await _restore(backup);
      case 'share':
        await _shareBackup(backup);
      case 'delete':
        await _deleteBackup(backup);
    }
  }

  bool _beforeRestore(File backup) =>
      p.basename(backup.parent.path) == 'before-restore';

  String _detail(AppLocalizations l10n, File backup) => [
    nexFormatBytes(_metadata[backup.path]?.size ?? 0),
    if (_beforeRestore(backup)) l10n.backupBeforeRestore,
  ].join(' · ');

  /// Whether this library is safe, in a sentence, with the button that
  /// makes it so.
  Widget _status(AppLocalizations l10n, ThemeData theme) {
    final scheme = theme.colorScheme;
    final newest = _backups
        ?.where((backup) => !_beforeRestore(backup))
        .firstOrNull;
    final folderFailed =
        widget.preferences.backupFolderUri != null &&
        widget.preferences.backupFolderFailedAt != null;
    final (icon, color) = folderFailed
        ? (Icons.error_outline, scheme.error)
        : newest == null
        ? (Icons.cloud_off_outlined, scheme.onSurfaceVariant)
        : (Icons.verified_outlined, scheme.primary);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: NexSpacing.sm),
            ],
            Row(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _backups == null
                            ? ''
                            : newest == null
                            ? l10n.backupStatusNone
                            : l10n.backupStatusLast(_stamp(newest)),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (widget.preferences.backupFolderUri != null)
                        DefaultTextStyle.merge(
                          style: theme.textTheme.bodySmall,
                          child: _folderLine(l10n, theme),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_backUpEverywhere()),
              icon: const Icon(Icons.backup_outlined),
              label: Text(l10n.backupNow),
            ),
          ],
        ),
      ),
    );
  }

  /// The folder in one line: off, its name and last copy, or why the last
  /// copy did not land.
  Widget _folderLine(AppLocalizations l10n, ThemeData theme) {
    final uri = widget.preferences.backupFolderUri;
    if (uri == null) return Text(l10n.backupFolderOff);
    final name = widget.preferences.backupFolderName;
    final folder = name.isEmpty ? l10n.backupFolderTitle : name;
    if (widget.preferences.backupFolderFailedAt != null) {
      return Text(
        _BackupScreenState._failure(
          l10n,
          widget.preferences.backupFolderFailure,
        ),
        style: TextStyle(color: theme.colorScheme.error),
      );
    }
    final last = widget.preferences.backupFolderLastAt;
    return Text(
      last == null
          ? l10n.backupFolderNever(folder)
          : l10n.backupFolderStatus(
              folder,
              nexDisplayDate(
                last,
                solar: widget.services.solarCalendar,
                persian: Localizations.localeOf(context).languageCode == 'fa',
                time: true,
              ),
            ),
    );
  }
}
