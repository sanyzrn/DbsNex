import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../widgets/choice_cards.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/tag_color_picker.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/update_service.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'assistant_screen.dart';
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
/// One sheet, grouped into labelled cards. What changed, and why:
///
/// Every choice used to be spelled out inline — three theme cards, four text
/// sizes, three languages, two swipe mappings, all expanded, all at once. It
/// was legible in isolation and unusable in aggregate: roughly two and a half
/// screens of picker before the first ordinary switch, and no way to see the
/// shape of Settings at all. The pickers themselves were not the problem, so
/// they are not gone — each one now sits behind the row that names it, and
/// opens as its own small sheet, previews and all. The list you scroll is one
/// line per setting with its current value beside it.
///
/// The profile card at the top is the one addition rather than a move. The
/// name had a section to itself, which is a lot of furniture for one field,
/// and being a section put it in the middle of the run rather than above it.
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
                // Every picker writes through `preferences`, which notifies —
                // without this the row that opened one would still show the
                // old value when the picker closed, since the sheet itself is
                // stateless and nothing else rebuilds it.
                child: ListenableBuilder(
                  listenable: preferences,
                  builder: (context, _) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      NexSpacing.md,
                      0,
                      NexSpacing.md,
                      NexSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _groups(context, l10n),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groups(BuildContext context, AppLocalizations l10n) => [
    _ProfileCard(preferences: preferences),
    _Section(
      title: l10n.intelligence,
      children: [
        _Row(
          icon: Icons.auto_awesome_outlined,
          title: l10n.intelligenceOpen,
          value: preferences.aiEnabled
              ? preferences.aiProvider.provider.label
              : l10n.intelligenceOff,
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
        _Row(
          icon: Icons.g_translate_outlined,
          title: l10n.aiOutputLanguage,
          value: _aiLanguageLabel(l10n, preferences.aiOutputLanguage),
          onTap: () => unawaited(
            _pick<AiOutputLanguage>(
              context: context,
              title: l10n.aiOutputLanguage,
              footnote: l10n.aiOutputLanguageSubtitle,
              selected: preferences.aiOutputLanguage,
              onSelected: preferences.setAiOutputLanguage,
              choices: [
                NexChoice(
                  value: AiOutputLanguage.auto,
                  label: l10n.aiOutputLanguageAuto,
                  preview: const NexScriptSample(icon: Icons.auto_awesome),
                ),
                NexChoice(
                  value: AiOutputLanguage.english,
                  label: l10n.aiOutputLanguageEnglish,
                  preview: const NexScriptSample(sample: 'Aa'),
                ),
                NexChoice(
                  value: AiOutputLanguage.persian,
                  label: l10n.aiOutputLanguagePersian,
                  preview: const NexScriptSample(sample: 'اَ'),
                ),
              ],
            ),
          ),
        ),
        _Row(
          icon: Icons.chat_bubble_outline,
          title: l10n.assistant,
          value: l10n.assistantSubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AssistantScreen(preferences: preferences),
            ),
          ),
        ),
      ],
    ),
    _Section(
      title: l10n.appearance,
      children: [
        _Row(
          icon: Icons.translate,
          title: l10n.language,
          value: switch (preferences.locale?.languageCode) {
            'en' => 'English',
            'fa' => 'فارسی',
            _ => l10n.languageSystem,
          },
          onTap: () => unawaited(
            _pick<String>(
              context: context,
              title: l10n.language,
              selected: preferences.locale?.languageCode ?? 'system',
              onSelected: preferences.setLocale,
              choices: [
                NexChoice(
                  value: 'system',
                  label: l10n.languageSystem,
                  preview: const NexScriptSample(
                    icon: Icons.phone_iphone_outlined,
                  ),
                ),
                // Each language in its own script: recognising your own
                // alphabet does not require reading the language the app is
                // currently in.
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
        ),
        _Row(
          icon: Icons.dark_mode_outlined,
          title: l10n.theme,
          value: switch (preferences.themeMode) {
            ThemeMode.light => l10n.themeLight,
            ThemeMode.dark => l10n.themeDark,
            ThemeMode.system => l10n.themeSystem,
          },
          onTap: () => unawaited(
            _pick<ThemeMode>(
              context: context,
              title: l10n.theme,
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
        ),
        _AccentColorRow(preferences: preferences),
        _Row(
          icon: Icons.format_size,
          title: l10n.uiScale,
          value: switch (preferences.uiScale) {
            < 1.0 => l10n.uiScaleSmall,
            < 1.1 => l10n.uiScaleDefault,
            < 1.25 => l10n.uiScaleLarge,
            _ => l10n.uiScaleLarger,
          },
          // The four steps are unchanged, but the type ramp underneath them
          // came down a step — so "Large" is roughly what "Default" used to
          // be, which is where anyone who liked the old size should land.
          onTap: () => unawaited(
            _pick<double>(
              context: context,
              title: l10n.uiScale,
              selected: preferences.uiScale,
              onSelected: preferences.setUiScale,
              choices: [
                NexChoice(
                  value: 0.9,
                  label: l10n.uiScaleSmall,
                  preview: const _TextSizePreview(fontSize: 13),
                ),
                NexChoice(
                  value: 1.0,
                  label: l10n.uiScaleDefault,
                  preview: const _TextSizePreview(fontSize: 17),
                ),
                NexChoice(
                  value: 1.15,
                  label: l10n.uiScaleLarge,
                  preview: const _TextSizePreview(fontSize: 21),
                ),
                NexChoice(
                  value: 1.3,
                  label: l10n.uiScaleLarger,
                  preview: const _TextSizePreview(fontSize: 25),
                ),
              ],
            ),
          ),
        ),
        _SwitchRow(
          icon: Icons.wb_twilight_outlined,
          title: l10n.comfortMode,
          value: preferences.comfortMode,
          onChanged: preferences.setComfortMode,
        ),
      ],
    ),
    _Section(
      title: l10n.capture,
      children: [
        _SwitchRow(
          icon: Icons.keyboard_return,
          title: l10n.enterSubmitsCapture,
          subtitle: l10n.enterSubmitsCaptureSubtitle,
          value: preferences.enterSubmitsCapture,
          onChanged: preferences.setEnterSubmitsCapture,
        ),
        _Row(
          icon: Icons.swipe_outlined,
          title: l10n.swipeActions,
          value:
              '${_swipeLabel(l10n, preferences.leadingAction)} · '
              '${_swipeLabel(l10n, preferences.trailingAction)}',
          onTap: () => unawaited(
            nexShowSheet<void>(
              context: context,
              builder: (_) => _PickerSheet(
                title: l10n.swipeActions,
                footnote: l10n.swipeActionsHint,
                // The one picker that is two choices rather than one, so it
                // keeps its own widget and stays open across both.
                child: _SwipeMapping(preferences: preferences),
              ),
            ),
          ),
        ),
      ],
    ),
    _Section(
      title: l10n.accessibility,
      children: [
        _SwitchRow(
          icon: Icons.animation_outlined,
          title: l10n.reduceMotion,
          value: preferences.reduceMotion,
          onChanged: preferences.setReduceMotion,
        ),
        _SwitchRow(
          icon: Icons.vibration,
          title: l10n.haptics,
          value: preferences.haptics,
          onChanged: preferences.setHaptics,
        ),
      ],
    ),
    _Section(
      title: l10n.dataAndBackup,
      children: [
        FutureBuilder<List<File>>(
          future: services.listBackups(),
          builder: (context, snapshot) => _Row(
            icon: Icons.import_export,
            title: l10n.exportTitle,
            value: l10n.backupCount(snapshot.data?.length ?? 0),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    BackupScreen(services: services, preferences: preferences),
              ),
            ),
          ),
        ),
        // Sync is not offered here. The server exists and the client talks
        // to it, but there is no pairing flow in the app — the row asked
        // people to paste a base URL and a bearer token they have no way to
        // obtain, which is a setting that can only be got wrong. The code
        // stays; the row comes back when there is a way to pair.
      ],
    ),
    _Section(
      title: l10n.about,
      children: [
        _UpdateRow(updates: updates, preferences: preferences),
        _SwitchRow(
          icon: Icons.update_outlined,
          title: l10n.autoUpdateCheck,
          subtitle: l10n.autoUpdateCheckHint,
          value: preferences.autoUpdateCheck,
          onChanged: preferences.setAutoUpdateCheck,
        ),
        _Row(
          icon: Icons.auto_stories_outlined,
          title: l10n.about,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  AboutScreen(services: services, preferences: preferences),
            ),
          ),
        ),
      ],
    ),
  ];
}

String _aiLanguageLabel(AppLocalizations l10n, AiOutputLanguage value) =>
    switch (value) {
      AiOutputLanguage.auto => l10n.aiOutputLanguageAuto,
      AiOutputLanguage.english => l10n.aiOutputLanguageEnglish,
      AiOutputLanguage.persian => l10n.aiOutputLanguagePersian,
    };

/// Opens one setting's choices as their own sheet, and applies the pick.
///
/// The cards themselves are unchanged — this is the same [NexChoiceCards]
/// that used to sit inline, previews and all. Only where it lives moved.
/// Closing on selection rather than offering a Save button: there is one
/// choice, it takes effect immediately, and a picker that stays open after
/// you have picked invites a second look for a confirmation that never comes.
Future<void> _pick<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<NexChoice<T>> choices,
  required ValueChanged<T> onSelected,
  String? footnote,
}) async {
  final picked = await nexShowSheet<T>(
    context: context,
    builder: (sheetContext) => _PickerSheet(
      title: title,
      footnote: footnote,
      child: NexChoiceCards<T>(
        selected: selected,
        choices: choices,
        onSelected: (value) => Navigator.pop(sheetContext, value),
      ),
    ),
  );
  if (picked != null) onSelected(picked);
}

/// The frame every setting's picker sheet shares.
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexSheetBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: NexSpacing.md),
          child,
          if (footnote != null) ...[
            const SizedBox(height: NexSpacing.md),
            Text(
              footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
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
///
/// The label lost the icon it used to carry. With every row inside the card
/// now leading with an icon tile of its own, a seventh icon floating above
/// them was the one that meant least and drew the most.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
              start: NexSpacing.sm,
              bottom: NexSpacing.sm,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
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
                    if (i > 0)
                      // The quiet token, now that the section has no outline
                      // around it: `outline` is for a boundary you can act on,
                      // and at full strength with nothing enclosing it these
                      // read as the loudest thing in Settings. Indented past
                      // the icon tiles so the run of rows reads as a column of
                      // labels rather than a stack of boxes.
                      Divider(
                        height: 1,
                        indent: _dividerIndent,
                        endIndent: NexSpacing.md,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a divider starts: past the icon tile, level with the row's title.
const _dividerIndent = NexSpacing.md + _iconTileSize + NexSpacing.md;
const _iconTileSize = 36.0;

/// A row's leading mark, on its own rounded ground.
///
/// A bare icon at the start of a row is the Material default and reads as
/// decoration hanging off the text. Sitting each one on a tile of the same
/// size turns the left edge into a column — which is the single change that
/// makes a long settings list scan as a list rather than as paragraphs.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.badge = false});

  final IconData icon;

  /// Draws the same dot the settings gear carries — see [_UpdateRow].
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _iconTileSize,
          height: _iconTileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(NexRadius.md),
          ),
          child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        ),
        if (badge)
          const PositionedDirectional(top: -2, end: -2, child: NexBadgeDot()),
      ],
    );
  }
}

/// One tappable setting: mark, name, current value, chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.value,
    this.trailing,
    this.badge = false,
    this.onTap,
  });

  final IconData icon;
  final String title;

  /// What the setting is currently set to, under its name. Null for the rows
  /// that only open something and have no state to report.
  final String? value;

  /// Replaces the chevron — the sync row puts a button here.
  final Widget? trailing;
  final bool badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: _rowPadding,
    leading: _IconTile(icon, badge: badge),
    title: Text(title),
    subtitle: value == null ? null : Text(value!),
    trailing: trailing ?? const Icon(Icons.chevron_right),
    // Here rather than at each call site: every row in this screen goes
    // through this widget, and Settings was the one surface the Haptics
    // switch could not be felt on — including on the switch itself.
    onTap: onTap == null
        ? null
        : () {
            nexTick();
            onTap!();
          },
  );
}

/// One setting that is simply on or off.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: _rowPadding,
    secondary: _IconTile(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    // A bump, not a tick: a switch is a thing changing state, not a
    // selection moving across a set of options.
    onChanged: (next) {
      nexBump();
      onChanged(next);
    },
  );
}

/// The name, above the settings rather than among them.
///
/// It had a section of its own — a labelled card holding one field — which is
/// both more furniture than one text input needs and, being a section, put it
/// somewhere in the middle of the run. As a header it reads as whose settings
/// these are, which is what a name at the top of a settings screen means
/// everywhere else.
///
/// Stateful for the same reason the row it replaces was: the sheet does not
/// rebuild itself on a name change from the dialog it opens.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.preferences});

  final NexPreferences preferences;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  Future<void> _edit() async {
    final saved = await editDisplayName(context, widget.preferences);
    if (saved && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = widget.preferences.displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.lg),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(_edit()),
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHigh,
                  ),
                  child: name == null
                      // No name is not a blank circle: the placeholder says
                      // what tapping would do.
                      ? Icon(
                          Icons.person_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Text(
                          // `characters` rather than `[0]`: a Persian name's
                          // first letter, and any emoji, is more than one code
                          // unit, and slicing one in half renders as a box.
                          name.characters.first.toUpperCase(),
                          style: theme.textTheme.titleLarge,
                        ),
                ),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? l10n.yourName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.yourNameHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
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
    final banner = NexBannerHost.of(context);
    setState(() => _busy = true);
    try {
      final result = await widget.services.syncNow();
      banner?.show(
        message: '${l10n.syncComplete} · ${result.pushed}↑ ${result.pulled}↓',
      );
    } catch (_) {
      banner?.show(message: l10n.operationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final server = widget.preferences.syncBaseUrl;
    return _Row(
      icon: Icons.sync,
      title: l10n.sync,
      value: server ?? l10n.syncNotConfigured,
      onTap: _configure,
      trailing: server == null
          ? null
          : TextButton(
              onPressed: _busy ? null : () => unawaited(_syncNow()),
              child: Text(l10n.syncNow),
            ),
    );
  }
}

/// Asks for the name the app greets you by, and stores it.
///
/// Returns whether anything was saved, so a caller that draws the name can
/// repaint. Shared rather than private to the profile card: onboarding asks
/// the same question, and asking it twice in two different dialogs is how the
/// two drift apart.
Future<bool> editDisplayName(
  BuildContext context,
  NexPreferences preferences,
) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: preferences.displayName ?? '');
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
  if (saved == null) return false;
  await preferences.setDisplayName(saved);
  return true;
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
    Widget edge(IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: NexSpacing.sm),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        edge(rtl ? Icons.arrow_back : Icons.arrow_forward, l10n.swipeLeading),
        NexChoiceCards<SwipeAction>(
          selected: widget.preferences.leadingAction,
          onSelected: (action) => _select(isLeading: true, action: action),
          choices: choices,
        ),
        const SizedBox(height: NexSpacing.md),
        edge(rtl ? Icons.arrow_forward : Icons.arrow_back, l10n.swipeTrailing),
        NexChoiceCards<SwipeAction>(
          selected: widget.preferences.trailingAction,
          onSelected: (action) => _select(isLeading: false, action: action),
          choices: choices,
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

  Future<void> _pickColor(BuildContext context) async {
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
    return _Row(
      icon: Icons.color_lens_outlined,
      title: l10n.accentColorSetting,
      // The swatch says which colour better than any name would, so the row
      // spends its subtitle on what the colour actually reaches instead.
      value: l10n.accentColorSettingSubtitle,
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: swatch,
          border: Border.all(color: theme.colorScheme.outline),
        ),
      ),
      onTap: () => unawaited(_pickColor(context)),
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
        _Row(
          icon: Icons.system_update_outlined,
          badge: waiting,
          title: l10n.checkForUpdate,
          value: switch ((waiting, version)) {
            // Saying it is already downloaded is the point of downloading it
            // early: the next tap is an install, not a wait.
            (true, final v?) when ready =>
              '${l10n.updateAvailable(v)} · ${l10n.updateReady}',
            (true, final v?) => l10n.updateAvailable(v),
            _ => l10n.installedVersion(nexAppVersion),
          },
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
