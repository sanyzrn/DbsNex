import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../widgets/choice_cards.dart';
import '../widgets/nex_dialog.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/update_service.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'intelligence_screen.dart';
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
    this.updates,
  });

  final NexServices services;
  final NexPreferences preferences;

  /// Null in tests that do not care about updates.
  final UpdateService? updates;

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
                          child: NexChoiceCards<ThemeMode>(
                            haptics: preferences.haptics,
                            selected: preferences.themeMode,
                            onSelected: preferences.setThemeMode,
                            choices: [
                              NexChoice(
                                value: ThemeMode.light,
                                label: l10n.themeLight,
                                preview: NexThemeSwatch(
                                  mode: ThemeMode.light,
                                  comfort: preferences.comfortMode,
                                ),
                              ),
                              NexChoice(
                                value: ThemeMode.dark,
                                label: l10n.themeDark,
                                preview: NexThemeSwatch(
                                  mode: ThemeMode.dark,
                                  comfort: preferences.comfortMode,
                                ),
                              ),
                              NexChoice(
                                value: ThemeMode.system,
                                label: l10n.themeSystem,
                                preview: NexThemeSwatch(
                                  mode: ThemeMode.system,
                                  comfort: preferences.comfortMode,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          secondary: const Icon(Icons.wb_twilight_outlined),
                          title: Text(l10n.comfortMode),
                          subtitle: Text(l10n.comfortModeSubtitle),
                          value: preferences.comfortMode,
                          onChanged: preferences.setComfortMode,
                        ),
                        _SubHeading(icon: Icons.translate, label: l10n.language),
                        _Inset(
                          child: NexChoiceCards<String>(
                            haptics: preferences.haptics,
                            selected:
                                preferences.locale?.languageCode ?? 'system',
                            onSelected: preferences.setLocale,
                            choices: [
                              NexChoice(
                                value: 'system',
                                label: l10n.languageSystem,
                                preview: const NexScriptSample(
                                  icon: Icons.phone_iphone_outlined,
                                ),
                              ),
                              // Each language in its own script: recognising
                              // your own alphabet does not require reading the
                              // language the app is currently in.
                              const NexChoice(
                                value: 'en',
                                label: 'English',
                                preview: NexScriptSample(sample: 'Aa'),
                              ),
                              const NexChoice(
                                value: 'fa',
                                label: 'فارسی',
                                preview: NexScriptSample(sample: 'اَ'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.person_outline,
                      title: l10n.yourName,
                      footnote: l10n.yourNameHint,
                      children: [_NameRow(preferences: preferences)],
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
                      icon: Icons.backup_outlined,
                      title: l10n.dataAndBackup,
                      children: [
                        FutureBuilder<List<File>>(
                          future: services.listBackups(),
                          builder: (context, snapshot) => ListTile(
                            contentPadding: _rowPadding,
                            leading: const Icon(Icons.import_export),
                            title: Text(l10n.exportTitle),
                            subtitle: Text(
                              l10n.backupCount(snapshot.data?.length ?? 0),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => BackupScreen(
                                  services: services,
                                  preferences: preferences,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _SyncRow(
                          services: services,
                          preferences: preferences,
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.info_outline,
                      title: l10n.about,
                      children: [
                        _UpdateRow(
                          updates: updates,
                          preferences: preferences,
                        ),
                        SwitchListTile(
                          contentPadding: _rowPadding,
                          secondary: const Icon(Icons.update_outlined),
                          title: Text(l10n.autoUpdateCheck),
                          subtitle: Text(l10n.autoUpdateCheckHint),
                          value: preferences.autoUpdateCheck,
                          onChanged: preferences.setAutoUpdateCheck,
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

/// Sync, and whether it is set up at all.
///
/// It used to be a bare "Sync now" button that reported "the operation failed"
/// on every tap, because there is no default server and nowhere in the app to
/// name one. Sync is optional, so the honest row says that, and offers the
/// field that makes it work rather than hiding the reason.
class _SyncRow extends StatefulWidget {
  const _SyncRow({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends State<_SyncRow> {
  bool _busy = false;

  Future<void> _configure() async {
    final l10n = AppLocalizations.of(context);
    final url = TextEditingController(
      text: widget.preferences.syncBaseUrl ?? '',
    );
    final token = TextEditingController(
      text: widget.preferences.syncBearerToken ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.syncServer),
        content: NexDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.syncServer,
                  hintText: l10n.syncServerHint,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              TextField(
                controller: token,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.syncToken),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.preferences.setSyncBaseUrl(url.text.trim());
      await widget.preferences.setSyncBearerToken(token.text.trim());
      if (mounted) setState(() {});
    }
    url.dispose();
    token.dispose();
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await widget.services.syncNow();
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.syncComplete} · ${result.pushed}↑ ${result.pulled}↓')),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.operationFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final server = widget.preferences.syncBaseUrl;
    return ListTile(
      contentPadding: _rowPadding,
      leading: const Icon(Icons.sync),
      title: Text(l10n.sync),
      subtitle: Text(server ?? l10n.syncNotConfigured),
      onTap: _configure,
      trailing: server == null
          ? const Icon(Icons.chevron_right)
          : TextButton(
              onPressed: _busy ? null : () => unawaited(_syncNow()),
              child: Text(l10n.syncNow),
            ),
    );
  }
}

/// A label inside a section card, for a control that is not a list tile.
///
/// The theme and language pickers are both card rows, and without this the
/// second one would sit under the first with nothing saying what it chooses.
class _SubHeading extends StatelessWidget {
  const _SubHeading({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NexSpacing.md,
        end: NexSpacing.md,
        top: NexSpacing.contentGap,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.secondary),
          const SizedBox(width: NexSpacing.sm),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The name the app greets you by.
///
/// Stateful because the settings sheet is not: without this the row would
/// still show the old name until the sheet was closed and reopened.
class _NameRow extends StatefulWidget {
  const _NameRow({required this.preferences});

  final NexPreferences preferences;

  @override
  State<_NameRow> createState() => _NameRowState();
}

class _NameRowState extends State<_NameRow> {
  Future<void> _edit() async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: widget.preferences.displayName ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.yourName),
        content: NexDialogBody(
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: l10n.yourNamePlaceholder),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await widget.preferences.setDisplayName(saved);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.preferences.displayName;
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: _rowPadding,
      leading: const Icon(Icons.waving_hand_outlined),
      title: Text(name ?? l10n.yourName),
      subtitle: Text(name == null ? l10n.yourNamePlaceholder : l10n.edit),
      trailing: const Icon(Icons.chevron_right),
      onTap: _edit,
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


/// The update row, with the same dot the settings icon carries.
///
/// Two dots for one fact, deliberately: the icon says "there is something in
/// settings", and this says which thing. Without the second one the user opens
/// settings and has to hunt.
class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.updates, required this.preferences});

  final UpdateService? updates;
  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = updates;
    Widget row({required bool waiting, String? version, bool ready = false}) =>
        ListTile(
          contentPadding: _rowPadding,
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.system_update_outlined),
              if (waiting)
                const PositionedDirectional(
                  top: -2,
                  end: -2,
                  child: NexBadgeDot(),
                ),
            ],
          ),
          title: Text(l10n.checkForUpdate),
          subtitle: Text(
            switch ((waiting, version)) {
              // Saying it is already downloaded is the point of downloading it
              // early: the next tap is an install, not a wait.
              (true, final v?) when ready => '${l10n.updateAvailable(v)} · ${l10n.updateReady}',
              (true, final v?) => l10n.updateAvailable(v),
              _ => l10n.installedVersion(nexAppVersion),
            },
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => UpdateSheet.show(
            context,
            haptics: preferences.haptics,
            service: service,
          ),
        );

    if (service == null) return row(waiting: false);
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => row(
        waiting: service.hasUpdate,
        version: service.available?.version.toString(),
        ready: service.downloaded != null,
      ),
    );
  }
}
