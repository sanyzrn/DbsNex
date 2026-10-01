import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../platform/full_backup.dart';
import '../platform/app_lock.dart';
import '../platform/sharing.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../restart_scope.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/recovery_code.dart';

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
  /// Null until the first listing comes back — see the tag manager's own
  /// field. Here the false claim is "No backups", told to someone opening the
  /// one screen that exists to reassure them their data is recoverable.
  List<File>? _backups;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final found = await widget.services.listBackups();
    final metadata = <String, FileStat>{};
    for (final file in found) {
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.file) metadata[file.path] = stat;
    }
    if (mounted) {
      setState(() {
        _metadata = metadata;
        _backups = found
            .where((file) => metadata.containsKey(file.path))
            .toList();
      });
    }
  }

  Map<String, FileStat> _metadata = {};

  void _say(String message) {
    if (!mounted) return;
    nexShowBanner(context, message: message);
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

  Future<void> _exportFull() => _guard(() async {
    final l10n = AppLocalizations.of(context);
    final key = FullBackup.newKey();
    var includeModel = false;
    var includeVault = false;
    var retainedKey = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(l10n.fullBackupTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.fullBackupPrivateHint),
                const SizedBox(height: 12),
                NexRecoveryCode(key),
                CheckboxListTile(
                  value: retainedKey,
                  title: Text(l10n.backupKeySaved),
                  onChanged: (v) => update(() => retainedKey = v ?? false),
                ),
                CheckboxListTile(
                  value: includeModel,
                  title: Text(l10n.backupIncludeModel),
                  onChanged: (v) => update(() => includeModel = v ?? false),
                ),
                CheckboxListTile(
                  value: includeVault,
                  title: Text(l10n.backupIncludeVault),
                  onChanged: (v) => update(() => includeVault = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: retainedKey ? () => Navigator.pop(ctx, true) : null,
              child: Text(l10n.export),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (includeVault &&
          !await AppLockService().authenticate(
            reason: l10n.vaultAuthReason,
            biometricOnly: false,
          )) {
        return;
      }
      final path = await widget.services.exportFullBackup(
        key,
        includeModel: includeModel,
        includeVault: includeVault,
      );
      if (!mounted) return;
      await nexSendFileOut(path, mimeType: 'application/octet-stream');
    } catch (_) {
      _say(l10n.backupFailed);
    }
  });

  /// Picks the folder, shows the recovery code once, and makes the first
  /// copy straight away so the person sees it land.
  Future<void> _chooseFolder() => _guard(() async {
    final l10n = AppLocalizations.of(context);
    final picked = await widget.services.backupFolder.pick();
    if (picked == null || !mounted) return;
    final key =
        await widget.preferences.backupFolderKey() ?? FullBackup.newKey();
    if (!mounted) return;
    if (!await _confirmFolderKey(key)) {
      await widget.services.backupFolder.release(picked.uri);
      return;
    }
    final previous = widget.preferences.backupFolderUri;
    if (previous != null && previous != picked.uri) {
      await widget.services.backupFolder.release(previous);
    }
    await widget.preferences.setBackupFolder(
      uri: picked.uri,
      name: picked.name,
      key: key,
    );
    final copied = await widget.services.backupToFolderIfDue(force: true);
    _say(copied ? l10n.backupFolderCopied : l10n.backupFolderCopyFailed);
  });

  Future<bool> _confirmFolderKey(String key) async {
    final l10n = AppLocalizations.of(context);
    var saved = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(l10n.backupFolderTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.backupFolderKeyHint),
                const SizedBox(height: 12),
                NexRecoveryCode(key),
                CheckboxListTile(
                  value: saved,
                  title: Text(l10n.backupKeySaved),
                  onChanged: (v) => update(() => saved = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: saved ? () => Navigator.pop(ctx, true) : null,
              child: Text(l10n.backupFolderChoose),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _copyToFolderNow() => _guard(() async {
    final l10n = AppLocalizations.of(context);
    final copied = await widget.services.backupToFolderIfDue(force: true);
    _say(copied ? l10n.backupFolderCopied : l10n.backupFolderCopyFailed);
  });

  /// The code again, behind the same unlock as the vault: it opens every
  /// copy in the folder.
  Future<void> _showFolderKey() async {
    final l10n = AppLocalizations.of(context);
    if (!await AppLockService().authenticate(
      reason: l10n.backupFolderShowKey,
      biometricOnly: false,
    )) {
      return;
    }
    final key = await widget.preferences.backupFolderKey();
    if (key == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupFolderShowKey),
        content: NexRecoveryCode(key),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.closeLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _stopFolder() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupFolderStop),
        content: NexDialogBody(child: Text(l10n.backupFolderStopBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.backupFolderStop),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final uri = widget.preferences.backupFolderUri;
    if (uri != null) await widget.services.backupFolder.release(uri);
    await widget.preferences.clearBackupFolder();
    if (mounted) setState(() {});
  }

  /// The reason the last copy did not land, in words someone can act on.
  /// Older builds recorded no reason; they get the general sentence.
  static String _failure(AppLocalizations l10n, String? recorded) {
    final split = recorded?.indexOf(':') ?? -1;
    final kind = split < 0 ? recorded : recorded!.substring(0, split);
    final detail = split < 0 ? '' : recorded!.substring(split + 1);
    return switch (kind) {
      'code' => l10n.backupFolderFailedCode,
      'access' => l10n.backupFolderFailedAccess,
      'backup' => l10n.backupFolderFailedBackup(detail),
      'write' => l10n.backupFolderFailedWrite(detail),
      _ => l10n.backupFolderFailed,
    };
  }

  Widget _folderSection(AppLocalizations l10n, ThemeData theme) {
    final uri = widget.preferences.backupFolderUri;
    final name = widget.preferences.backupFolderName;
    final last = widget.preferences.backupFolderLastAt;
    final failed = widget.preferences.backupFolderFailedAt;
    final folder = name.isEmpty ? l10n.backupFolderTitle : name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Explained(
          icon: Icons.drive_folder_upload_outlined,
          title: l10n.backupFolderTitle,
          body: l10n.backupFolderExplained,
          action: l10n.backupFolderChoose,
          onPressed: _busy ? null : () => unawaited(_chooseFolder()),
        ),
        if (uri != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              0,
              NexSpacing.lg,
              NexSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  last == null
                      ? l10n.backupFolderNever(folder)
                      : l10n.backupFolderStatus(
                          folder,
                          nexDisplayDate(
                            last,
                            solar: widget.services.solarCalendar,
                            persian:
                                Localizations.localeOf(context).languageCode ==
                                'fa',
                            time: true,
                          ),
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
                if (failed != null)
                  Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.xs),
                    child: Text(
                      _failure(l10n, widget.preferences.backupFolderFailure),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.xs,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_copyToFolderNow()),
                      icon: const Icon(Icons.sync),
                      label: Text(l10n.backupFolderCopyNow),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_showFolderKey()),
                      child: Text(l10n.backupFolderShowKey),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => unawaited(_stopFolder()),
                      child: Text(l10n.backupFolderStop),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _askRecoveryKey() async {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.backupRecoveryKey),
          content: TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            textDirection: TextDirection.ltr,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l10n.restore),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _backupNow() => _guard(() async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.services.backupNow();
      await _load();
      _say(l10n.backupDone);
    } catch (error) {
      _say('${l10n.backupFailed} (${NexServices.describeFailure(error)})');
    }
  });

  Future<void> _export() => _guard(() async {
    final l10n = AppLocalizations.of(context);
    try {
      final path = await widget.services.exportNow();
      if (!mounted) return;
      // Getting it out of the app is the whole point: a zip sitting in the
      // app's own directory is not a backup a person can keep. On a phone
      // that means the share sheet; on Windows, which has no share sheet
      // worth the name, it means asking where to put it.
      final outcome = await nexSendFileOut(path, mimeType: 'application/zip');
      if (!mounted) return;
      if (outcome == SendOutcome.saved) _say(l10n.exportedTo(path));
    } catch (error) {
      _say('${l10n.exportFailed} (${NexServices.describeFailure(error)})');
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
      // Said out loud, because the alternative is a silent false promise.
      //
      // An import writes its notes as already-synced — the same call the
      // sync client uses for a note the server just sent it. So they never
      // enter the outbox, the next sync has nothing to push, and the server
      // never learns they exist. Nothing reports this: the import succeeds,
      // sync succeeds, and someone who has just restored their library onto
      // a new phone is told everything is fine while the only copy of it is
      // the phone in their hand.
      //
      // Changing that means re-uploading a whole library on every import and
      // proving it cannot resurrect anything deleted, which is a change to
      // sync semantics and wants a test that reaches it. Until then this at
      // least stops the app from implying a backup it does not have. Shown
      // only when a server is configured — with no sync set up there is
      // nothing to be wrong about.
      final syncing = widget.preferences.syncBaseUrl != null;
      _say(
        syncing
            ? '${l10n.importDone(result.imported, result.skipped)} · '
                  '${l10n.restoredStaysLocal}'
            : l10n.importDone(result.imported, result.skipped),
      );
    } catch (error) {
      _say('${l10n.importFailed} (${NexServices.describeFailure(error)})');
    }
  });

  Future<void> _shareBackup(File backup) => _guard(() async {
    try {
      await nexSendFileOut(
        await widget.services.portableBackup(backup),
        mimeType: 'application/zip',
      );
    } catch (error) {
      if (mounted) {
        _say(
          '${AppLocalizations.of(context).exportFailed} (${NexServices.describeFailure(error)})',
        );
      }
    }
  });

  Future<void> _chooseBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Nex backup',
          extensions: ['nexbak', 'sqlite', 'nexfull'],
        ),
      ],
    );
    if (file != null && mounted) await _restore(File(file.path));
  }

  Future<void> _deleteBackup(File backup) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteBackup),
        content: NexDialogBody(child: Text(l10n.deleteBackupBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() async {
      await widget.services.deleteBackup(backup);
      await _load();
    });
  }

  Future<void> _restore(File backup) => _guard(() => _confirmRestore(backup));

  Future<void> _confirmRestore(File backup) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreBackup),
        content: NexDialogBody(
          child: Text('${l10n.restoreBody}\n\n${p.basename(backup.path)}'),
        ),
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
    try {
      // The restore invalidates the whole service graph; the returned token
      // is the contract that the caller must rebuild it.
      final full = backup.path.endsWith('.nexfull');
      final key = full ? await _askRecoveryKey() : null;
      if (full && (key == null || key.isEmpty)) return;
      final result = full
          ? await widget.services.restoreFullBackup(
              backup,
              key!,
              authorizeVaultRestore: () => AppLockService().authenticate(
                reason: l10n.vaultRestoreAuth,
                biometricOnly: false,
              ),
            )
          : await widget.services.restoreBackup(backup);
      if (!mounted) return;
      final restart = NexRestartScope.of(context).restart;
      if (result.error != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.restoreBackup),
            content: Text(l10n.restoreFailed(result.error!)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.closeLabel),
              ),
            ],
          ),
        );
      }
      restart();
    } on VaultAuthenticationRequired {
      return;
    } on Object catch (error) {
      // The graph is already closed by the time restore touches live files —
      // this session cannot read or write the library anymore either way.
      // Failing silently here was the one path that left a user staring at a
      // screen where every action answered "unavailable" with no reason.
      if (!mounted) return;
      nexShowBanner(
        context,
        message: l10n.restoreFailed(error.runtimeType.toString()),
        kind: NexBannerKind.failed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final backups = _backups;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.dataAndBackup)),
        body: ListView(
          padding: EdgeInsets.only(
            bottom: NexSpacing.xl + nexBottomInset(context),
          ),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            _Explained(
              icon: Icons.enhanced_encryption_outlined,
              title: l10n.fullBackupTitle,
              body: l10n.fullBackupPrivateHint,
              action: l10n.exportAndShare,
              onPressed: _busy ? null : () => unawaited(_exportFull()),
            ),
            if (widget.services.backupFolder.supported)
              ListenableBuilder(
                listenable: widget.preferences,
                builder: (context, _) => _folderSection(l10n, theme),
              ),
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
            _Explained(
              icon: Icons.restore_page_outlined,
              title: l10n.restoreBackup,
              body: l10n.fullBackupExplained,
              action: l10n.chooseFile,
              onPressed: _busy ? null : () => unawaited(_chooseBackup()),
            ),
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
            if (backups == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: NexSpacing.lg),
                child: NexSkeleton(height: 16),
              )
            else if (backups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
                child: Text(
                  l10n.backupCount(0),
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final backup in backups)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.lg,
                  ),
                  leading: const Icon(Icons.history),
                  // Every backup is offered, not only the newest: the newest one
                  // is also the most likely to contain a mistake just made.
                  title: Text(_stamp(backup)),
                  subtitle: Text(
                    nexFormatBytes(_metadata[backup.path]?.size ?? 0),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.exportAndShare,
                        icon: const Icon(Icons.ios_share_outlined),
                        onPressed: _busy
                            ? null
                            : () => unawaited(_shareBackup(backup)),
                      ),
                      IconButton(
                        tooltip: l10n.deleteBackup,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () => unawaited(_deleteBackup(backup)),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => unawaited(_restore(backup)),
                        child: Text(l10n.restore),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Backups are named with a sortable timestamp; show the file's own mtime,
  /// which is the same instant and is already localised by the platform.
  String _stamp(File backup) {
    final at = _metadata[backup.path]?.modified ?? DateTime(1970);
    return nexDisplayDate(
      at,
      solar: widget.preferences.solarCalendar,
      persian: Localizations.localeOf(context).languageCode == 'fa',
      time: true,
    );
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
            padding: const EdgeInsetsDirectional.only(
              top: 2,
              end: NexSpacing.md,
            ),
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
