import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../widgets/choice_cards.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_toast.dart';
import '../widgets/tag_color_picker.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/update_service.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'intelligence_screen.dart';
import 'update_sheet.dart';

String _swipeLabel(AppLocalizations l10n, SwipeAction action) =>
    switch (action) {
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
                    child: Text(
                      l10n.settings,
                      style: theme.textTheme.titleLarge,
                    ),
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
              child: _DismissOnOverscroll(
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
                          _SubHeading(
                            icon: Icons.format_size,
                            label: l10n.uiScale,
                          ),
                          _Inset(
                            child: NexChoiceCards<double>(
                              haptics: preferences.haptics,
                              selected: preferences.uiScale,
                              onSelected: preferences.setUiScale,
                              choices: [
                                NexChoice(
                                  value: 0.9,
                                  label: l10n.uiScaleSmall,
                                  preview: const _TextSizePreview(fontSize: 14),
                                ),
                                NexChoice(
                                  value: 1.0,
                                  label: l10n.uiScaleDefault,
                                  preview: const _TextSizePreview(fontSize: 18),
                                ),
                                NexChoice(
                                  value: 1.15,
                                  label: l10n.uiScaleLarge,
                                  preview: const _TextSizePreview(fontSize: 22),
                                ),
                                NexChoice(
                                  value: 1.3,
                                  label: l10n.uiScaleLarger,
                                  preview: const _TextSizePreview(fontSize: 26),
                                ),
                              ],
                            ),
                          ),
                          _SubHeading(
                            icon: Icons.translate,
                            label: l10n.language,
                          ),
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
                          _AccentColorRow(preferences: preferences),
                        ],
                      ),
                      _Section(
                        icon: Icons.person_outline,
                        title: l10n.yourName,
                        footnote: l10n.yourNameHint,
                        children: [_NameRow(preferences: preferences)],
                      ),
                      _Section(
                        icon: Icons.edit_note_outlined,
                        title: l10n.capture,
                        children: [
                          SwitchListTile(
                            contentPadding: _rowPadding,
                            secondary: const Icon(Icons.keyboard_return),
                            title: Text(l10n.enterSubmitsCapture),
                            subtitle: Text(l10n.enterSubmitsCaptureSubtitle),
                            value: preferences.enterSubmitsCapture,
                            onChanged: preferences.setEnterSubmitsCapture,
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

/// Closes the sheet on a downward drag anywhere over [child], once it is
/// already scrolled to the top.
///
/// The sheet's own drag-to-dismiss only ever saw the header above the
/// scroll view: a plain `SingleChildScrollView` wins the same vertical drag
/// in the gesture arena outright, whether or not it has anywhere left to
/// scroll, so a swipe that started over the settings themselves never
/// reached it. `OverscrollNotification` is what the scroll view reports
/// instead of moving once it is pinned at its own boundary — a negative
/// value is exactly a downward drag past the top — so it stands in for the
/// drag-to-dismiss the content itself cannot forward.
///
/// [OverscrollNotification.dragDetails] is what keeps this to an actual drag
/// at the top: a fast fling from further down the list can cross the whole
/// scroll range and bounce past the top boundary in one continuous motion,
/// which reports overscroll too, but with `dragDetails: null` — no finger is
/// pressing at that point, the scrollable is just settling its own fling.
/// Without this check that fling closed the sheet on the way to the top
/// instead of merely scrolling it there; only a second, deliberate drag once
/// it has actually arrived should do that.
class _DismissOnOverscroll extends StatefulWidget {
  const _DismissOnOverscroll({required this.child});

  final Widget child;

  @override
  State<_DismissOnOverscroll> createState() => _DismissOnOverscrollState();
}

class _DismissOnOverscrollState extends State<_DismissOnOverscroll> {
  bool _dismissed = false;

  bool _onNotification(OverscrollNotification notification) {
    if (!_dismissed &&
        notification.dragDetails != null &&
        notification.overscroll < -8) {
      _dismissed = true;
      Navigator.of(context).maybePop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<OverscrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}

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
                  style: theme.textTheme.bodySmall?.copyWith(
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.lg),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    // None before the first row, and none right after a
                    // _SubHeading — a subheading is a caption for the row
                    // that follows it, not a control of its own, so a
                    // divider there only separated a label from the one
                    // thing it was labelling. That showed up as a stray
                    // extra line under "Language", directly above the
                    // picker it introduces.
                    if (i > 0 && children[i - 1] is! _SubHeading)
                      // The quiet token, now that the section has no outline
                      // around it: `outline` is for a boundary you can act on,
                      // and at full strength with nothing enclosing it these
                      // read as the loudest thing in Settings.
                      Divider(
                        height: 1,
                        indent: NexSpacing.md,
                        endIndent: NexSpacing.md,
                        color: theme.colorScheme.outlineVariant,
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
        nexToast(
          content: Text(
            '${l10n.syncComplete} · ${result.pushed}↑ ${result.pulled}↓',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(nexToast(content: Text(l10n.operationFailed)));
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
    final controller = TextEditingController(
      text: widget.preferences.displayName ?? '',
    );
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
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(NexSpacing.md), child: child);
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
    await widget.preferences.setSwipeAction(
      isLeading: isLeading,
      action: action,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The leading edge is the left in LTR and the right in RTL, so the arrow
    // that describes the gesture has to follow the reading direction.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Shared between both edges: a choice's value carries no per-edge state,
    // only which edge is "selected" differs.
    final choices = [
      for (final action in SwipeAction.values)
        NexChoice(
          value: action,
          label: _swipeLabel(l10n, action),
          preview: _SwipeActionPreview(action: action),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeading(
          icon: rtl ? Icons.arrow_back : Icons.arrow_forward,
          label: l10n.swipeLeading,
        ),
        _Inset(
          child: NexChoiceCards<SwipeAction>(
            haptics: widget.preferences.haptics,
            selected: widget.preferences.leadingAction,
            onSelected: (action) => _select(isLeading: true, action: action),
            choices: choices,
          ),
        ),
        _SubHeading(
          icon: rtl ? Icons.arrow_forward : Icons.arrow_back,
          label: l10n.swipeTrailing,
        ),
        _Inset(
          child: NexChoiceCards<SwipeAction>(
            haptics: widget.preferences.haptics,
            selected: widget.preferences.trailingAction,
            onSelected: (action) => _select(isLeading: false, action: action),
            choices: choices,
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

/// A swipe action's card preview: the same tinted-circle language the
/// theme/language pickers already use, coloured per action so Delete reads
/// as destructive and Add tag doesn't.
class _SwipeActionPreview extends StatelessWidget {
  const _SwipeActionPreview({required this.action});

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final color = _swipeColor(Theme.of(context), action);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(_swipeIcon(action), size: 20, color: color),
    );
  }
}

/// A card preview that shows the size rather than naming it — the same
/// "Aa" at a different scale every text-size control uses, since a number
/// of points means nothing next to actually seeing it.
/// One seed colour, recolouring the caret, focus rings and every other
/// accent-tinted control — see [NexAccentPalette] for how the other three
/// shades a theme actually needs follow from it.
class _AccentColorRow extends StatelessWidget {
  const _AccentColorRow({required this.preferences});

  final NexPreferences preferences;

  Future<void> _pick(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await TagColorPicker.show(
      context,
      // The picker's own fallback when nothing is passed is an arbitrary
      // starter blue meant for a brand-new tag — here it has to be today's
      // actual accent, seed or default, so editing starts from what is
      // already on screen rather than jumping to an unrelated hue.
      initial: preferences.accentSeed ?? _hex(NexColors.accentLight),
      title: l10n.accentColorPickerTitle,
    );
    if (result == null) return;
    await preferences.setAccentSeed(result.color);
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final swatch =
        nexParseTagColor(preferences.accentSeed) ?? NexColors.accentLight;
    return ListTile(
      contentPadding: _rowPadding,
      leading: const Icon(Icons.color_lens_outlined),
      title: Text(l10n.accentColorSetting),
      subtitle: Text(l10n.accentColorSettingSubtitle),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: swatch,
          border: Border.all(color: theme.colorScheme.outline),
        ),
      ),
      onTap: () => unawaited(_pick(context)),
    );
  }
}

class _TextSizePreview extends StatelessWidget {
  const _TextSizePreview({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: Center(
      child: Text(
        'Aa',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
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
          subtitle: Text(switch ((waiting, version)) {
            // Saying it is already downloaded is the point of downloading it
            // early: the next tap is an install, not a wait.
            (true, final v?) when ready =>
              '${l10n.updateAvailable(v)} · ${l10n.updateReady}',
            (true, final v?) => l10n.updateAvailable(v),
            _ => l10n.installedVersion(nexAppVersion),
          }),
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
