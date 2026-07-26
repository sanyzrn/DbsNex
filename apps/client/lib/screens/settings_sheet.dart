import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String? _status;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPrefs);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await widget.services.exportNow();
      setState(() => _status = '${l10n.export}: ${p.basename(file.path)}');
    } catch (_) {
      setState(() => _status = 'Export failed');
    }
  }

  Future<void> _sync() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await widget.services.syncNow();
      setState(
        () => _status = l10n.syncOk(result.pushed, result.pulled),
      );
    } catch (_) {
      setState(() => _status = l10n.syncFailed);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final backups = widget.services.listBackups();
    if (backups.isEmpty) {
      setState(() => _status = 'No backup available');
      return;
    }

    late final File backup;
    if (backups.length == 1) {
      backup = backups.first;
    } else {
      final picked = await showModalBottomSheet<File>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xs,
                ),
                child: Text(
                  l10n.chooseBackup,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (var i = 0; i < backups.length; i++)
                ListTile(
                  leading: Icon(
                    i == 0 ? Icons.backup : Icons.history,
                  ),
                  title: Text(_backupLabel(backups[i])),
                  subtitle: Text(
                    [
                      if (i == 0) l10n.latestBackup,
                      nexFormatBytes(backups[i].lengthSync()),
                    ].join(' · '),
                  ),
                  onTap: () => Navigator.pop(ctx, backups[i]),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      backup = picked;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(
          l10n.restoreConfirmBodyNamed(_backupLabel(backup)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      widget.services.restoreBackup(backup);
      setState(() => _status = 'Restored. Restart the app to continue.');
    } catch (_) {
      setState(() => _status = 'No backup available');
    }
  }

  String _backupLabel(File file) {
    final name = p.basenameWithoutExtension(file.path);
    // Prefer human timestamp from mtime when filename isn't already clear.
    final mtime = file.lastModifiedSync().toLocal();
    final stamp =
        '${mtime.year}-${mtime.month.toString().padLeft(2, '0')}-${mtime.day.toString().padLeft(2, '0')} '
        '${mtime.hour.toString().padLeft(2, '0')}:${mtime.minute.toString().padLeft(2, '0')}';
    if (name.contains(RegExp(r'\d{4}'))) return '$name ($stamp)';
    return stamp;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = widget.preferences;
    return Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.settings, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: NexSpacing.md),

            // Preference group 1: swipe mapping (ADR-022).
            Text(l10n.swipeActions, style: Theme.of(context).textTheme.bodySmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.swipeSummary(
                  prefs.leadingAction.label,
                  prefs.trailingAction.label,
                ),
              ),
              subtitle: Text(l10n.swapSwipeMapping),
              trailing: IconButton(
                tooltip: l10n.swapSwipeMapping,
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => prefs.swapSwipeMapping(),
              ),
            ),

            const Divider(),

            // Preference group 2: appearance — theme + Comfort Mode.
            Text(l10n.appearance, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: NexSpacing.sm),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l10n.themeLight),
                  icon: const Icon(Icons.light_mode_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l10n.themeDark),
                  icon: const Icon(Icons.dark_mode_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l10n.themeSystem),
                  icon: const Icon(Icons.brightness_auto_outlined, size: 16),
                ),
              ],
              selected: {prefs.themeMode},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) prefs.setThemeMode(set.first);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.comfortMode),
              subtitle: Text(l10n.comfortModeSubtitle),
              value: prefs.comfortMode,
              onChanged: (v) => prefs.setComfortMode(v),
            ),

            const Divider(),

            Text('Intelligence', style: Theme.of(context).textTheme.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Transcription'),
              subtitle: const Text('Voice notes become keyword-searchable'),
              value: prefs.aiCapabilities.transcription,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(transcription: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('OCR'),
              subtitle: const Text('Photo notes become keyword-searchable'),
              value: prefs.aiCapabilities.ocr,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(ocr: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tag suggestions'),
              value: prefs.aiCapabilities.tagSuggestions,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(tagSuggestions: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Semantic search'),
              value: prefs.aiCapabilities.semanticSearch,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(semanticSearch: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Summarization'),
              value: prefs.aiCapabilities.summarization,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(summarization: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Related notes'),
              value: prefs.aiCapabilities.relatedNotes,
              onChanged: (v) async {
                await prefs.setAiCapabilities(
                  prefs.aiCapabilities.copyWith(relatedNotes: v),
                );
                widget.services.applyAiPreferences(prefs);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cloud AI (opt-in)'),
              subtitle: const Text('Off by default — on-device only'),
              value: prefs.cloudAiOptIn,
              onChanged: (v) => prefs.setCloudAiOptIn(v),
            ),

            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync),
              title: Text(l10n.sync),
              subtitle: Text(l10n.syncSubtitle),
              trailing: TextButton(
                onPressed: _sync,
                child: Text(l10n.syncNow),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.ios_share_outlined),
              title: Text(l10n.export),
              subtitle: Text(l10n.exportSubtitle),
              onTap: _export,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: Text(l10n.restore),
              subtitle: Text(l10n.restoreSubtitle),
              onTap: _restore,
            ),
            if (_status != null) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: NexSpacing.md),
          ],
        ),
      ),
    );
  }
}
