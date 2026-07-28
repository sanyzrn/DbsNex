import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../widgets/nex_dialog.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'package:nex_data/nex_data.dart';
import '../restart_scope.dart';
import 'about_screen.dart';
import 'intelligence_screen.dart';
import 'recently_deleted_screen.dart';
import 'tag_manager_screen.dart';
import 'update_sheet.dart';

String _swipeLabel(AppLocalizations l10n, SwipeAction action) => switch (action) {
      SwipeAction.none => l10n.swipeNone,
      SwipeAction.delete => l10n.delete,
      SwipeAction.addTag => l10n.addTag,
    };

/// The v1 preference surface.
///
/// Still one sheet rather than a nested settings app, but the preferences are
/// grouped into labelled cards instead of a single flat run of tiles — the
/// sheet had grown past twenty controls with nothing but bare text headings to
/// separate them, and it opened flush against the status bar.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Leaves the sheet short of the top edge so the handle and title are
        // never pinned under the status bar.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.settings, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: l10n.cancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  0,
                  NexSpacing.md,
                  NexSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      icon: Icons.palette_outlined,
                      title: l10n.appearance,
                      children: [
                        _Inset(
                          child: SegmentedButton<ThemeMode>(
                            segments: [
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: const Icon(Icons.light_mode_outlined),
                                label: Text(l10n.themeLight),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: const Icon(Icons.dark_mode_outlined),
                                label: Text(l10n.themeDark),
                              ),
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: const Icon(Icons.brightness_auto_outlined),
                                label: Text(l10n.themeSystem),
                              ),
                            ],
                            showSelectedIcon: false,
                            selected: {preferences.themeMode},
                            onSelectionChanged: (value) =>
                                preferences.setThemeMode(value.first),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          title: Text(l10n.comfortMode),
                          subtitle: Text(l10n.comfortModeSubtitle),
                          value: preferences.comfortMode,
                          onChanged: preferences.setComfortMode,
                        ),
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.translate),
                          title: Text(l10n.language),
                          trailing: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value:
                                  preferences.locale?.languageCode ?? 'system',
                              borderRadius: BorderRadius.circular(16),
                              items: [
                                DropdownMenuItem(
                                  value: 'system',
                                  child: Text(l10n.languageSystem),
                                ),
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text(l10n.languageEnglish),
                                ),
                                DropdownMenuItem(
                                  value: 'fa',
                                  child: Text(l10n.languagePersian),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) preferences.setLocale(value);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.accessibility_new_outlined,
                      title: l10n.accessibility,
                      children: [
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          secondary: const Icon(Icons.animation_outlined),
                          title: Text(l10n.reduceMotion),
                          value: preferences.reduceMotion,
                          onChanged: preferences.setReduceMotion,
                        ),
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          secondary: const Icon(Icons.vibration),
                          title: Text(l10n.haptics),
                          value: preferences.haptics,
                          onChanged: preferences.setHaptics,
                        ),
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          secondary: const Icon(Icons.cake_outlined),
                          title: Text(l10n.quietAnniversary),
                          subtitle: Text(l10n.quietAnniversarySubtitle),
                          value: preferences.quietAnniversary,
                          onChanged: preferences.setQuietAnniversary,
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.swipe_outlined,
                      title: l10n.swipeActions,
                      footnote: l10n.swipeActionsHint,
                      children: [_SwipeMapping(preferences: preferences)],
                    ),
                    _Section(
                      icon: Icons.auto_awesome_outlined,
                      title: l10n.intelligence,
                      children: [
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(l10n.intelligenceOpen),
                          subtitle: Text(
                            preferences.aiEnabled
                                ? preferences.aiProvider.provider.label
                                : l10n.intelligenceOff,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => IntelligenceScreen(
                                services: services,
                                preferences: preferences,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.inventory_2_outlined,
                      title: l10n.libraryTitle,
                      children: [
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.label_outline),
                          title: Text(l10n.tags),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TagManagerScreen(services: services),
                            ),
                          ),
                        ),
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.restore_from_trash_outlined),
                          title: Text(l10n.trash),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RecentlyDeletedScreen(
                                services: services,
                                preferences: preferences,
                              ),
                            ),
                          ),
                        ),
                        FutureBuilder<StorageSnapshot>(
                          future: services.storage(),
                          builder: (context, snapshot) => ListTile(
                            contentPadding: _rowPadding,
                            leading: const Icon(Icons.storage_outlined),
                            title: Text(l10n.storage),
                            subtitle: snapshot.hasData
                                ? Text(
                                    l10n.storageUsed(
                                      nexFormatBytes(snapshot.requireData.total),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.backup_outlined,
                      title: l10n.dataAndBackup,
                      children: [
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.sync),
                          title: Text(l10n.sync),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await services.syncNow();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.syncComplete)),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: NexDialogBody(child: Text(l10n.operationFailed)),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text(l10n.syncNow),
                          ),
                        ),
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.ios_share_outlined),
                          title: Text(l10n.export),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            try {
                              final path = await services.exportNow();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.exportedTo(path))),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.operationFailed)),
                                );
                              }
                            }
                          },
                        ),
                        FutureBuilder<List<File>>(
                          future: services.listBackups(),
                          builder: (context, snapshot) {
                            final backups = snapshot.data ?? const <File>[];
                            return ListTile(
                              contentPadding: _rowPadding,
                              leading: const Icon(Icons.restore),
                              title: Text(l10n.restoreBackup),
                              subtitle: Text(l10n.backupCount(backups.length)),
                              enabled: backups.isNotEmpty,
                              onTap: backups.isEmpty
                                  ? null
                                  : () => _restore(context, backups.first, l10n),
                            );
                          },
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.info_outline,
                      title: l10n.about,
                      children: [
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.system_update_outlined),
                          title: Text(l10n.checkForUpdate),
                          subtitle: Text(l10n.installedVersion(nexAppVersion)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => UpdateSheet.show(
                            context,
                            haptics: preferences.haptics,
                          ),
                        ),
                        ListTile(
                          contentPadding: _rowPadding,
                          leading: const Icon(Icons.auto_stories_outlined),
                          title: Text(l10n.about),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AboutScreen(services: services),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    File backup,
    AppLocalizations l10n,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreBackup),
        content: NexDialogBody(child: Text(l10n.restoreBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // The restore invalidates the whole service graph; the returned token is
    // the contract that the caller must rebuild it.
    final _ = await services.restoreBackup(backup);
    if (!context.mounted) return;
    NexRestartScope.of(context).restart();
  }

}

const _rowPadding = EdgeInsetsDirectional.only(
  start: NexSpacing.md,
  end: NexSpacing.sm,
);

/// One labelled group of preferences, drawn as a card.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.xs,
              bottom: NexSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.secondary),
                const SizedBox(width: NexSpacing.sm),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexColors.cardRadius),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexColors.cardRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: NexSpacing.md,
                        endIndent: NexSpacing.md,
                        color: theme.colorScheme.outline,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: NexSpacing.xs,
                top: NexSpacing.sm,
              ),
              child: Text(footnote!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Padding for controls that are not list tiles, so they line up with them.
class _Inset extends StatelessWidget {
  const _Inset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: child,
      );
}

/// The FR-2.7 swipe mapping.
///
/// ADR-022 fixes the action set at exactly Delete and Add Tag; the only choice
/// is which edge does which. Showing the live mapping makes that choice
/// legible — the bare "swap" tile gave no way to tell what the current state
/// even was, and because the settings sheet is stateless, swapping did not
/// even repaint. This owns its own state so the rows update on the spot.
class _SwipeMapping extends StatefulWidget {
  const _SwipeMapping({required this.preferences});

  final NexPreferences preferences;

  @override
  State<_SwipeMapping> createState() => _SwipeMappingState();
}

class _SwipeMappingState extends State<_SwipeMapping> {
  Future<void> _swap() async {
    await widget.preferences.swapSwipeMapping();
    if (mounted) setState(() {});
  }

  Future<void> _select({
    required bool isLeading,
    required SwipeAction action,
  }) async {
    await widget.preferences.setSwipeAction(isLeading: isLeading, action: action);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The leading edge is the left in LTR and the right in RTL, so the arrow
    // that describes the gesture has to follow the reading direction.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwipeRow(
          icon: rtl ? Icons.arrow_back : Icons.arrow_forward,
          title: l10n.swipeLeading,
          action: widget.preferences.leadingAction,
          onSelected: (action) => _select(isLeading: true, action: action),
        ),
        _SwipeRow(
          icon: rtl ? Icons.arrow_forward : Icons.arrow_back,
          title: l10n.swipeTrailing,
          action: widget.preferences.trailingAction,
          onSelected: (action) => _select(isLeading: false, action: action),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.sm,
            0,
            NexSpacing.md,
            NexSpacing.sm,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _swap,
              icon: const Icon(Icons.swap_horiz),
              label: Text(l10n.swapSwipeMapping),
            ),
          ),
        ),
      ],
    );
  }
}

IconData _swipeIcon(SwipeAction action) => switch (action) {
      SwipeAction.none => Icons.block,
      SwipeAction.delete => Icons.delete_outline,
      SwipeAction.addTag => Icons.label_outline,
    };

Color _swipeColor(ThemeData theme, SwipeAction action) => switch (action) {
      SwipeAction.none => theme.colorScheme.outline,
      SwipeAction.delete => theme.colorScheme.error,
      SwipeAction.addTag => theme.colorScheme.secondary,
    };

/// One edge of the mapping, with its action chosen from a menu.
///
/// A menu rather than a swap button: the control has to say what the choices
/// *are*. It also survives a third action being added — that becomes one more
/// entry here, not another rewrite of this widget.
class _SwipeRow extends StatelessWidget {
  const _SwipeRow({
    required this.icon,
    required this.title,
    required this.action,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final SwipeAction action;
  final ValueChanged<SwipeAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = _swipeColor(theme, action);
    return PopupMenuButton<SwipeAction>(
      tooltip: title,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final candidate in SwipeAction.values)
          PopupMenuItem(
            value: candidate,
            child: Row(
              children: [
                Icon(
                  _swipeIcon(candidate),
                  size: 18,
                  color: _swipeColor(theme, candidate),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_swipeLabel(l10n, candidate))),
                if (candidate == action)
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
      child: ListTile(
        contentPadding: _rowPadding,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Row(
          children: [
            Icon(_swipeIcon(action), size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              _swipeLabel(l10n, action),
              style: theme.textTheme.bodyMedium?.copyWith(color: accent),
            ),
          ],
        ),
        trailing: const Icon(Icons.expand_more),
      ),
    );
  }
}

