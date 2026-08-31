import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../widgets/choice_cards.dart';
import '../widgets/dismiss_on_overscroll.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_time_picker.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/tag_color_picker.dart';
import '../platform/ai_provider.dart';
import '../platform/daily_nudge.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/reminders.dart';
import '../platform/update_service.dart';
import '../platform/os_capture_bridge.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'assistant_screen.dart';
import 'intelligence_screen.dart';
import 'profile_screen.dart';
import 'security_screen.dart';
import 'update_sheet.dart';

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
                    tooltip: l10n.closeLabel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: NexDismissOnOverscroll(
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

  /// Turns the daily notification on or off.
  ///
  /// The permission request comes with the switch rather than at launch: this
  /// is the first thing in Nex that asks to notify without being told to by a
  /// specific note, so it is the first honest place to ask. Turning it off
  /// asks nothing and cancels what was scheduled.
  ///
  /// Both refusals are answered rather than ignored. A switch left sitting on
  /// after the phone said no is the app claiming something it has no way to
  /// do — and a daily notification that never arrives has nothing else to
  /// give the reader a clue, unlike a note reminder, which at least still
  /// shows its time on the card.
  /// Posts the reminder diagnostic: one notification now, one in ten
  /// seconds. The first exercises permission and the channel; the second
  /// exercises scheduling. A reminder that "does nothing" is one of those
  /// two halves broken, and from inside the app they are otherwise
  /// indistinguishable — both look like nothing happened.
  Future<void> _sendTestNotification(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final failure = await services.reminders.sendTestNotification(
      title: l10n.notificationTest,
      body: l10n.notificationTestHint,
    );
    if (!context.mounted) return;
    nexShowBanner(
      context,
      message: failure == null
          ? l10n.notificationTestSent
          : l10n.notificationTestFailed(failure),
      kind: failure == null ? NexBannerKind.done : NexBannerKind.failed,
    );
  }

  Future<void> _setNudge(BuildContext context, bool value) async {
    // Only where there is a notification backend to refuse. On a desktop
    // build `requestPermission` answers false because there is nothing to
    // ask, and reading that as "the user said no" would make the switch
    // impossible to turn on for a reason that has nothing to do with them.
    if (value && NexReminders.supported) {
      final allowed = await services.reminders.requestPermission();
      if (!context.mounted) return;
      if (!allowed) {
        final failure = services.reminders.lastError;
        nexShowBanner(
          context,
          message: failure == null
              ? AppLocalizations.of(context).remindDenied
              : '${AppLocalizations.of(context).nudgeNotScheduled} ($failure)',
          kind: NexBannerKind.failed,
        );
        return;
      }
    }
    await preferences.setDailyNudge(value);
    if (!context.mounted) return;
    final failure = await DailyNudge.apply(
      context: context,
      preferences: preferences,
      reminders: services.reminders,
      recap: preferences.lastRecap,
    );
    if (!context.mounted || failure == null || !value) return;
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).nudgeNotScheduled,
      kind: NexBannerKind.failed,
    );
  }

  Future<void> _pickNudgeTime(BuildContext context) async {
    final minutes = preferences.dailyNudgeMinutes;
    final picked = await nexPickTime(
      context,
      initial: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    await preferences.setDailyNudgeMinutes(picked.hour * 60 + picked.minute);
    if (!context.mounted) return;
    await DailyNudge.apply(
      context: context,
      preferences: preferences,
      reminders: services.reminders,
      recap: preferences.lastRecap,
    );
  }

  List<Widget> _groups(BuildContext context, AppLocalizations l10n) => [
    _ProfileCard(services: services, preferences: preferences),
    _Section(
      title: l10n.securityTitle,
      children: [
        _Row(
          icon: Icons.shield_outlined,
          title: l10n.securityAppLock,
          value: preferences.appLockEnabled
              ? preferences.appLockBiometricOnly
                    ? l10n.securityBiometric
                    : l10n.securityDevicePasscode
              : l10n.securityOff,
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => SecurityScreen(preferences: preferences),
            ),
          ),
        ),
      ],
    ),
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
            NexPageRoute<void>(
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
            NexPageRoute<void>(
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
        _SwitchRow(
          icon: Icons.blur_on_outlined,
          title: l10n.liquidGlass,
          subtitle: l10n.liquidGlassSubtitle,
          value: preferences.liquidGlass,
          onChanged: preferences.setLiquidGlass,
        ),
        _Row(
          icon: Icons.wallpaper_outlined,
          title: l10n.backgroundStyle,
          value: _backgroundLabel(l10n, preferences.backgroundPattern),
          onTap: () => unawaited(
            _pick<NexBackgroundPattern>(
              context: context,
              title: l10n.backgroundStyle,
              selected: preferences.backgroundPattern,
              onSelected: preferences.setBackgroundPattern,
              footnote: l10n.backgroundStyleSubtitle,
              choices: [
                for (final pattern in NexBackgroundPattern.values)
                  NexChoice(
                    value: pattern,
                    label: _backgroundLabel(l10n, pattern),
                    preview: NexBackgroundPreview(pattern: pattern),
                  ),
              ],
            ),
          ),
        ),
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
        _SwitchRow(
          icon: Icons.vibration,
          title: l10n.haptics,
          value: preferences.haptics,
          onChanged: preferences.setHaptics,
        ),
        _Row(
          icon: Icons.swipe_outlined,
          title: l10n.swipeActions,
          value:
              '${nexSwipeActionLabel(l10n, preferences.leadingAction)} · '
              '${nexSwipeActionLabel(l10n, preferences.trailingAction)}',
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
      title: l10n.notifications,
      children: [
        _SwitchRow(
          icon: Icons.notifications_active_outlined,
          title: l10n.nudgeTitle,
          subtitle: l10n.nudgeSubtitle,
          value: preferences.dailyNudge,
          onChanged: (next) => unawaited(_setNudge(context, next)),
        ),
        // Only once it is on. A time picker for a notification that is not
        // being sent is a control with nothing behind it, and the row it
        // would sit under already says what turning it on gets you.
        if (preferences.dailyNudge)
          _Row(
            icon: Icons.schedule_outlined,
            title: l10n.nudgeTime,
            value: TimeOfDay(
              hour: preferences.dailyNudgeMinutes ~/ 60,
              minute: preferences.dailyNudgeMinutes % 60,
            ).format(context),
            onTap: () => unawaited(_pickNudgeTime(context)),
          ),
        // The diagnostic that separates "my phone swallowed it" from "Nex
        // never sent it": one notification proves permission and the channel,
        // a scheduled one proves the alarm path. It existed in the engine and
        // had shipped strings — it just had no way to be reached.
        _Row(
          icon: Icons.notifications_none_outlined,
          title: l10n.notificationTest,
          value: l10n.notificationTestHint,
          onTap: () => unawaited(_sendTestNotification(context)),
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
              NexPageRoute<void>(
                builder: (_) =>
                    BackupScreen(services: services, preferences: preferences),
              ),
            ),
          ),
        ),
        _ImportRow(services: services, preferences: preferences),
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
            NexPageRoute<void>(
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

String _backgroundLabel(AppLocalizations l10n, NexBackgroundPattern pattern) =>
    switch (pattern) {
      NexBackgroundPattern.plain => l10n.backgroundPlain,
      NexBackgroundPattern.aurora => l10n.backgroundAurora,
      NexBackgroundPattern.ripple => l10n.backgroundRipple,
      NexBackgroundPattern.weave => l10n.backgroundWeave,
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

/// Both row types in this sheet share it, so the rhythm of the whole screen
/// is set here.
///
/// The vertical half is not decoration. With none, every row sat at
/// `ListTile`'s own minimum and the rows ran together — a stack of settings
/// reads as one dense block rather than as separate things you choose between,
/// and the switches made it worse by filling the height they were given.
const _rowPadding = EdgeInsetsDirectional.only(
  start: NexSpacing.md,
  end: NexSpacing.sm,
  top: NexSpacing.sm,
  bottom: NexSpacing.sm,
);

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
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            clipBehavior: Clip.antiAlias,
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
  Widget build(BuildContext context) => NexSwitchTile(
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
  const _ProfileCard({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  Future<void> _edit() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => ProfileScreen(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = widget.preferences.displayName;
    final photoPath = widget.preferences.profilePhotoPath;
    final photo = photoPath == null ? null : File(photoPath);
    final hasPhoto = photo?.existsSync() ?? false;
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
                  foregroundDecoration: hasPhoto
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: FileImage(photo!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : null,
                  child: name == null && !hasPhoto
                      // No name is not a blank circle: the placeholder says
                      // what tapping would do.
                      ? Icon(
                          Icons.person_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : hasPhoto
                      ? null
                      : Text(
                          // `characters` rather than `[0]`: a Persian name's
                          // first letter, and any emoji, is more than one code
                          // unit, and slicing one in half renders as a box.
                          name!.characters.first.toUpperCase(),
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
                        widget.preferences.profileBio.trim().isEmpty
                            ? l10n.profileOpenHint
                            : widget.preferences.profileBio,
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

/// The FR-2.7 swipe mapping, as two rows rather than two grids.
///
/// ADR-022 always said the action set was open; for a long time it held two
/// members, and two grids of two cards each was a fine way to show them. At
/// seven it is not — fourteen preview cards stacked in a sheet is a wall, and
/// the thing being chosen (which of *these* does that edge do) stops being
/// legible somewhere around the fifth.
///
/// So each edge is one row saying what it currently does, and the choice moves
/// behind it into a list. That is the shape every settings screen uses for a
/// list that can grow, and it means the next action costs one entry rather
/// than another row of cards.
class _SwipeMapping extends StatefulWidget {
  const _SwipeMapping({required this.preferences});

  final NexPreferences preferences;

  @override
  State<_SwipeMapping> createState() => _SwipeMappingState();
}

class _SwipeMappingState extends State<_SwipeMapping> {
  Future<void> _choose({required bool isLeading}) async {
    final l10n = AppLocalizations.of(context);
    final current = isLeading
        ? widget.preferences.leadingAction
        : widget.preferences.trailingAction;
    final picked = await nexShowSheet<SwipeAction>(
      context: context,
      builder: (sheetContext) => _PickerSheet(
        title: isLeading ? l10n.swipeLeadingEdge : l10n.swipeTrailingEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in SwipeAction.values)
              _SwipeChoiceRow(
                action: action,
                selected: action == current,
                onTap: () => Navigator.pop(sheetContext, action),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await widget.preferences.setSwipeAction(
      isLeading: isLeading,
      action: picked,
    );
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _SwipeEdgeRow(
          arrow: rtl ? Icons.arrow_back : Icons.arrow_forward,
          label: l10n.swipeLeading,
          action: widget.preferences.leadingAction,
          onTap: () => unawaited(_choose(isLeading: true)),
        ),
        const SizedBox(height: NexSpacing.sm),
        _SwipeEdgeRow(
          arrow: rtl ? Icons.arrow_forward : Icons.arrow_back,
          label: l10n.swipeTrailing,
          action: widget.preferences.trailingAction,
          onTap: () => unawaited(_choose(isLeading: false)),
        ),
      ],
    );
  }
}

/// One edge, saying what it does now and opening the list that changes it.
class _SwipeEdgeRow extends StatelessWidget {
  const _SwipeEdgeRow({
    required this.arrow,
    required this.label,
    required this.action,
    required this.onTap,
  });

  final IconData arrow;
  final String label;
  final SwipeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          nexTick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(arrow, size: 16, color: theme.colorScheme.secondary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall),
                    Text(
                      nexSwipeActionLabel(l10n, action),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              _SwipeActionPreview(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// One action in the picker: its glyph, its name, and one line saying what it
/// does — because "Pin" and "Share" explain themselves and "Ask" does not.
class _SwipeChoiceRow extends StatelessWidget {
  const _SwipeChoiceRow({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final SwipeAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SwipeActionPreview(action: action),
      title: Text(nexSwipeActionLabel(l10n, action)),
      subtitle: Text(
        nexSwipeActionHint(l10n, action),
        style: theme.textTheme.bodySmall,
      ),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: () {
        nexTick();
        onTap();
      },
    );
  }
}

/// The colour a swipe action wears in Settings.
///
/// The panel's own fill, dimmed onto a tinted disc, so the row in Settings and
/// the panel the gesture reveals are recognisably the same thing. [SwipeAction
/// .none] has no panel and no fill, so it borrows the outline.
Color _swipeColor(BuildContext context, SwipeAction action) =>
    nexSwipeSpec(AppLocalizations.of(context), action)?.color ??
    Theme.of(context).colorScheme.outline;

/// A swipe action's glyph on its tinted disc — the same language the theme and
/// language pickers use.
class _SwipeActionPreview extends StatelessWidget {
  const _SwipeActionPreview({required this.action});

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final color = _swipeColor(context, action);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(nexSwipeActionIcon(action), size: 20, color: color),
    );
  }
}

/// Reads another app's export into the library.
///
/// Lives beside Backup rather than in a screen of its own: an import is the
/// same kind of act as a restore — a file goes in, notes come out — and a
/// second screen for one button would be furniture.
///
/// Stateful only to hold "a file is being read". The read itself happens in
/// the database isolate, which is why this can be a row rather than a progress
/// screen: a Takeout export of years of notes does not block the frame.
class _ImportRow extends StatefulWidget {
  const _ImportRow({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_ImportRow> createState() => _ImportRowState();
}

class _ImportRowState extends State<_ImportRow> {
  bool _running = false;

  Future<void> _import() async {
    if (_running) return;
    final picked = await OsCaptureBridge.pickFile();
    if (picked == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    setState(() => _running = true);
    int count;
    try {
      count = await widget.services.importNotes(picked.path);
    } catch (_) {
      // Anything that goes wrong here is "that file was not an export",
      // which is one message rather than a stack trace someone has to read.
      count = -1;
    }
    if (mounted) setState(() => _running = false);
    if (count > 0) {
      widget.services.refreshTimeline();
      nexBump();
    }
    host?.show(
      message: count < 0
          ? l10n.foreignImportUnreadable
          : l10n.foreignImportDone(count),
      kind: count < 0 ? NexBannerKind.failed : NexBannerKind.done,
      haptics: widget.preferences.haptics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Row(
      icon: Icons.download_outlined,
      title: l10n.foreignImportTitle,
      value: _running ? l10n.foreignImportWorking : l10n.foreignImportSubtitle,
      trailing: _running
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _running ? null : () => unawaited(_import()),
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
