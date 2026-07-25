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
