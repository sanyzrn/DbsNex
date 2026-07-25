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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmBody),
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
      widget.services.restoreLatestBackup();
      setState(() => _status = 'Restored. Restart the app to continue.');
    } catch (_) {
      setState(() => _status = 'No backup available');
    }
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

            // Preference group 2: appearance / Comfort Mode (ADR-023).
            Text(l10n.appearance, style: Theme.of(context).textTheme.bodySmall),
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
