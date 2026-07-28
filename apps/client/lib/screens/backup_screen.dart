import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../restart_scope.dart';
import '../widgets/nex_dialog.dart';

/// Everything about getting the library out of this device, and back in.
///
/// These four things used to be four rows in the settings sheet with nothing
/// saying what any of them did, and two of them did not really work: Export
/// wrote a zip to a temp path nobody on a phone could reach, and there was no
/// way at all to read an export back — which made it a one-way write and left
/// the automatic backup, stored on the same device, as the only real copy.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<File> _backups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final found = await widget.services.listBackups();
    if (mounted) setState(() => _backups = found);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Runs [action], keeping the screen from starting a second one on top of it.
  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() => _guard(() async {
        final l10n = AppLocalizations.of(context);
        try {
          await widget.services.backupNow();
          await _load();
          _say(l10n.backupDone);
        } catch (_) {
          _say(l10n.operationFailed);
        }
      });

  Future<void> _export() => _guard(() async {
        final l10n = AppLocalizations.of(context);
        try {
          final path = await widget.services.exportNow();
          if (!mounted) return;
          // Handing it to the share sheet is the whole point: a zip sitting in
          // the app's cache directory is not a backup a person can keep.
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(path)],
              fileNameOverrides: [path.split(Platform.pathSeparator).last],
            ),
          );
        } catch (_) {
          _say(l10n.operationFailed);
        }
      });

  Future<void> _import() => _guard(() async {
        final l10n = AppLocalizations.of(context);
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Nex export', extensions: ['zip']),
          ],
        );
        if (file == null) return;
        try {
          final result = await widget.services.importArchive(file.path);
          _say(l10n.importDone(result.imported, result.skipped));
        } catch (_) {
          _say(l10n.importFailed);
        }
      });

  Future<void> _restore(File backup) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreBackup),
        content: NexDialogBody(child: Text(l10n.restoreBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // The restore invalidates the whole service graph; the returned token is
    // the contract that the caller must rebuild it.
    final _ = await widget.services.restoreBackup(backup);
    if (!mounted) return;
    NexRestartScope.of(context).restart();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataAndBackup)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _Heading(l10n.exportTitle),
          _Explained(
            icon: Icons.ios_share_outlined,
            title: l10n.export,
            body: l10n.exportExplained,
            action: l10n.exportAndShare,
            onPressed: _busy ? null : () => unawaited(_export()),
          ),
          _Explained(
            icon: Icons.file_download_outlined,
            title: l10n.importTitle,
            body: l10n.importExplained,
            action: l10n.chooseFile,
            onPressed: _busy ? null : () => unawaited(_import()),
          ),
          const Divider(height: NexSpacing.xl),
          _Heading(l10n.localBackupsTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              0,
              NexSpacing.lg,
              NexSpacing.md,
            ),
            child: Text(
              l10n.localBackupsExplained,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => unawaited(_backupNow()),
                icon: const Icon(Icons.backup_outlined),
                label: Text(l10n.backupNow),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
              child: Text(
                l10n.backupCount(0),
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final backup in _backups)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.lg,
                ),
                leading: const Icon(Icons.history),
                // Every backup is offered, not only the newest: the newest one
                // is also the most likely to contain a mistake just made.
                title: Text(_stamp(backup)),
                subtitle: Text(nexFormatBytes(backup.lengthSync())),
                trailing: TextButton(
                  onPressed: _busy ? null : () => unawaited(_restore(backup)),
                  child: Text(l10n.restore),
                ),
              ),
        ],
      ),
    );
  }

  /// Backups are named with a sortable timestamp; show the file's own mtime,
  /// which is the same instant and is already localised by the platform.
  String _stamp(File backup) {
    final at = backup.lastModifiedSync();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}  ${two(at.hour)}:${two(at.minute)}';
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.lg,
          NexSpacing.lg,
          NexSpacing.sm,
        ),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// A thing you can do, with a sentence saying what it does.
///
/// The sentence is the point of this screen: "Export" on its own does not tell
/// anyone what comes out, where it goes, or whether it can be read back.
class _Explained extends StatelessWidget {
  const _Explained({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.lg,
        NexSpacing.sm,
        NexSpacing.lg,
        NexSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, end: NexSpacing.md),
            child: Icon(icon, color: theme.colorScheme.secondary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: NexSpacing.xs),
                Text(body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: NexSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonal(
                    onPressed: onPressed,
                    child: Text(action),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
