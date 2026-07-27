import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'package:nex_data/nex_data.dart';
import '../restart_scope.dart';
import 'about_screen.dart';
import 'recently_deleted_screen.dart';
import 'tag_manager_screen.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.services, required this.preferences});
  final NexServices services;
  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.settings, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        Text(l10n.appearance, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
            ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
          ],
          selected: {preferences.themeMode},
          onSelectionChanged: (value) => preferences.setThemeMode(value.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.comfortMode),
          subtitle: Text(l10n.comfortModeSubtitle),
          value: preferences.comfortMode,
          onChanged: preferences.setComfortMode,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.language),
          trailing: DropdownButton<String>(
            value: preferences.locale?.languageCode ?? 'system',
            items: [
              DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem)),
              DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              DropdownMenuItem(value: 'fa', child: Text(l10n.languagePersian)),
            ],
            onChanged: (value) { if (value != null) preferences.setLocale(value); },
          ),
        ),
        const Divider(),
        Text(l10n.accessibility, style: Theme.of(context).textTheme.bodySmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.reduceMotion),
          value: preferences.reduceMotion,
          onChanged: preferences.setReduceMotion,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.haptics),
          value: preferences.haptics,
          onChanged: preferences.setHaptics,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.quietAnniversary),
          subtitle: Text(l10n.quietAnniversarySubtitle),
          value: preferences.quietAnniversary,
          onChanged: preferences.setQuietAnniversary,
        ),
        const Divider(),
        Text(l10n.swipeActions, style: Theme.of(context).textTheme.bodySmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.swapSwipeMapping),
          trailing: const Icon(Icons.swap_horiz),
          onTap: preferences.swapSwipeMapping,
        ),
        const Divider(),
        Text(l10n.intelligence, style: Theme.of(context).textTheme.bodySmall),
        Text(l10n.intelligenceLocal, style: Theme.of(context).textTheme.bodySmall),
        _AiSwitch(
          title: l10n.transcription,
          value: preferences.aiCapabilities.transcription,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(transcription: value), services),
        ),
        _AiSwitch(
          title: l10n.ocr,
          value: preferences.aiCapabilities.ocr,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(ocr: value), services),
        ),
        _AiSwitch(
          title: l10n.tagSuggestions,
          value: preferences.aiCapabilities.tagSuggestions,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(tagSuggestions: value), services),
        ),
        _AiSwitch(
          title: l10n.semanticSearch,
          value: preferences.aiCapabilities.semanticSearch,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(semanticSearch: value), services),
        ),
        _AiSwitch(
          title: l10n.summarization,
          value: preferences.aiCapabilities.summarization,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(summarization: value), services),
        ),
        _AiSwitch(
          title: l10n.relatedNotes,
          value: preferences.aiCapabilities.relatedNotes,
          onChanged: (value) => _setAi(preferences,
            preferences.aiCapabilities.copyWith(relatedNotes: value), services),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.cloudAi),
          subtitle: Text(l10n.cloudAiSubtitle),
          value: preferences.cloudAiOptIn,
          onChanged: preferences.setCloudAiOptIn,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.tags),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => TagManagerScreen(services: services))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore_from_trash_outlined),
          title: Text(l10n.recentlyDeleted),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => RecentlyDeletedScreen(services: services))),
        ),
        FutureBuilder<StorageSnapshot>(
          future: services.storage(),
          builder: (context, snapshot) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.storage),
            subtitle: snapshot.hasData ? Text(
              l10n.storageUsed(nexFormatBytes(snapshot.requireData.total))) : null,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.about),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => AboutScreen(services: services))),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sync),
          title: Text(l10n.sync),
          trailing: TextButton(
            onPressed: () async {
              try {
                await services.syncNow();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l10n.syncComplete)));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.operationFailed)));
                }
              }
            },
            child: Text(l10n.syncNow),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.ios_share_outlined),
          title: Text(l10n.export),
          onTap: () async {
            try {
              final path = await services.exportNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.exportedTo(path))));
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.operationFailed)));
              }
            }
          },
        ),
        FutureBuilder<List<File>>(
          future: services.listBackups(),
          builder: (context, snapshot) {
            final backups = snapshot.data ?? const <File>[];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: Text(l10n.restoreBackup),
              subtitle: Text(l10n.backupCount(backups.length)),
              onTap: backups.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.restoreBackup),
                          content: Text(l10n.restoreBody),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l10n.cancel)),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l10n.restore)),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      // The restore invalidates the whole service graph; the
                      // returned token is the contract that the caller must
                      // rebuild it.
                      final _ = await services.restoreBackup(backups.first);
                      if (!context.mounted) return;
                      NexRestartScope.of(context).restart();
                    },
            );
          },
        ),
      ]),
    ));
  }

  static Future<void> _setAi(
    NexPreferences preferences,
    AiCapabilities capabilities,
    NexServices services,
  ) async {
    await preferences.setAiCapabilities(capabilities);
    services.applyAiPreferences(preferences);
  }
}

class _AiSwitch extends StatelessWidget {
  const _AiSwitch({required this.title, required this.value, required this.onChanged});
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );
}