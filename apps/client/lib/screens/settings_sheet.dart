import 'dart:async';
import 'dart:io';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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
import 'package:nex_ai/cloud.dart';
import '../platform/daily_nudge.dart';
import '../platform/nex_preferences.dart';
import '../platform/notification_settings.dart';
import '../platform/nex_services.dart';
import '../platform/profile_photo.dart';
import '../platform/reminders.dart';
import '../platform/update_service.dart';
import '../platform/os_capture_bridge.dart';
import 'about_screen.dart';
import '../widgets/feature_label.dart';
import '../platform/app_icon.dart';
import '../platform/hold_menu.dart';
import '../platform/theme_presets.dart';
import 'backup_screen.dart';
import 'guide_screen.dart';
import 'assistant_screen.dart';
import 'brief_screen.dart';
import 'disclosures_screen.dart';
import 'metrics_screen.dart';
import 'intelligence_screen.dart';
import 'profile_screen.dart';
import 'security_screen.dart';
import 'widget_settings_screen.dart';
import 'update_sheet.dart';

part 'settings/settings_search.dart';
part 'settings/settings_rows.dart';
part 'settings/settings_profile.dart';
part 'settings/settings_gestures.dart';
part 'settings/settings_appearance.dart';

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
    // Leaves the sheet short of the top edge so the handle and title are
    // never pinned under the status bar.
    final tallest = MediaQuery.sizeOf(context).height * 0.9;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: tallest),
        child: _SettingsSearch(
          // While searching, the sheet stays at its full height: a handful
          // of results used to shrink it to the bottom of the screen, where
          // the keyboard covered every one of them.
          builder: (context, query, field) => SizedBox(
            height: query.isEmpty ? null : tallest,
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
                field,
                Flexible(
                  child: NexDismissOnOverscroll(
                    // Every picker writes through `preferences`, which notifies —
                    // without this the row that opened one would still show the
                    // old value when the picker closed, since the sheet itself is
                    // stateless and nothing else rebuilds it.
                    child: ListenableBuilder(
                      listenable: preferences,
                      builder: (context, _) => SingleChildScrollView(
                        // The keyboard sits over the sheet's bottom edge, so
                        // the last rows scroll up clear of it.
                        padding: EdgeInsets.fromLTRB(
                          NexSpacing.md,
                          0,
                          NexSpacing.md,
                          NexSpacing.lg + keyboard,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: query.isEmpty
                              ? _groups(context, l10n)
                              : _matching(context, l10n, query),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Every row, from every section, that the query finds — each still the
  /// real row, so a switch found here is switched here (W6.6). A section
  /// whose own name matches brings all of its rows.
  List<Widget> _matching(
    BuildContext context,
    AppLocalizations l10n,
    String query,
  ) {
    final theme = Theme.of(context);
    final words = _fold(query).split(' ').where((w) => w.isNotEmpty);
    bool finds(String text) {
      final folded = _fold(text);
      return words.every(folded.contains);
    }

    final out = <Widget>[];
    for (final group in _groups(context, l10n)) {
      if (group is! _Section) continue;
      final rows = finds(group.title)
          ? group.children
          : [
              for (final row in group.children)
                if (finds(_searchTextOf(row))) row,
            ];
      if (rows.isEmpty) continue;
      out.add(
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.sm,
            NexSpacing.sm,
            NexSpacing.sm,
            NexSpacing.xs,
          ),
          child: Text(
            group.title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      out.add(
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      );
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.all(NexSpacing.xl),
          child: Text(
            nexLabel(
              context,
              'No setting matches that.',
              'تنظیمی با این عبارت پیدا نشد.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return out;
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
    // Recurring items used to have a section here, because Settings was the
    // only place they could be reached from. They have a button in the bar
    // along the bottom of the timeline now, which is where they belong: a
    // list of somebody's bills and medication is their data, not a
    // preference about how the app behaves.
    _Section(
      id: 'security',
      preferences: preferences,
      title: l10n.securityTitle,
      children: [
        _Row(
          icon: Icons.shield_outlined,
          title: l10n.securityAppLock,
          keywords:
              'lock app lock fingerprint biometric screen lock قفل اثر انگشت',
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
        _Row(
          icon: Icons.cloud_upload_outlined,
          title: l10n.disclosuresTitle,
          keywords:
              'privacy sent provider log disclosure data left device حریم خصوصی ارسال فرستاده خارج شد',
          value: l10n.disclosuresRow,
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => DisclosuresScreen(services: services),
            ),
          ),
        ),
      ],
    ),
    _Section(
      id: 'intelligence',
      preferences: preferences,
      title: l10n.intelligence,
      children: [
        _Row(
          icon: Icons.auto_awesome_outlined,
          title: l10n.intelligenceOpen,
          keywords:
              'AI provider API key model offline transcription OCR هوش مصنوعی ارائه‌دهنده کلید مدل آفلاین رونویسی',
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
        // The AI language used to have a row of its own here. It is in the
        // Smart summary screen instead — it is the most visible thing
        // about a brief and this was the last place anyone looked for it.
        // Still one setting: the assistant answers in it and transcriptions
        // come back in it, which the line under the picker says.
        _Row(
          icon: Icons.chat_bubble_outline,
          title: l10n.assistant,
          keywords: 'chat tone answer length stay in my notes دستیار گفتگو لحن',
          value: l10n.assistantSubtitle,
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => AssistantScreen(preferences: preferences),
            ),
          ),
        ),
        // Configure the provider and assistant before customizing the summary.
        _Row(
          icon: Icons.article_outlined,
          title: l10n.briefTitle,
          keywords: 'smart summary brief tokens greeting خلاصه هوشمند توکن',
          value: switch (preferences.briefStyle) {
            NexBriefStyle.assistant => l10n.briefStyleAssistant,
            NexBriefStyle.blended => l10n.briefStyleBlended,
            NexBriefStyle.report => l10n.briefStyleReport,
            NexBriefStyle.planner => l10n.briefStylePlanner,
            NexBriefStyle.custom => l10n.briefStyleCustom,
          },
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => BriefScreen(preferences: preferences),
            ),
          ),
        ),
      ],
    ),
    _Section(
      id: 'appearance',
      preferences: preferences,
      title: l10n.appearance,
      children: [
        _Row(
          icon: Icons.calendar_month_outlined,
          title: l10n.calendar,
          value: preferences.solarCalendar
              ? l10n.calendarPersian
              : l10n.calendarGregorian,
          onTap: () => unawaited(
            _pick<bool>(
              context: context,
              title: l10n.calendar,
              selected: preferences.solarCalendar,
              onSelected: preferences.setSolarCalendar,
              choices: [
                NexChoice(
                  value: false,
                  label: l10n.calendarGregorian,
                  preview: const Icon(Icons.calendar_today_outlined),
                ),
                NexChoice(
                  value: true,
                  label: l10n.calendarPersian,
                  preview: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
          ),
        ),
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
          icon: Icons.palette_outlined,
          title: l10n.theme,
          keywords:
              'dark light mode accent colour color palette text size font card size density compact app icon تم تیره روشن رنگ تأکیدی پالت اندازه متن اندازه کارت فشرده آیکون',
          value: nexThemePresetLabel(context, preferences.themePreset),
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => _ThemeScreen(preferences: preferences),
            ),
          ),
        ),
        _Row(
          icon: Icons.widgets_outlined,
          title: l10n.widgetSettingsTitle,
          keywords: 'home screen widget ویجت صفحه اصلی',
          value: _widgetFilterSummary(l10n, preferences),
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => WidgetSettingsScreen(
                preferences: preferences,
                services: services,
              ),
            ),
          ),
        ),
      ],
    ),
    _Section(
      id: 'capture',
      preferences: preferences,
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
          keywords: 'swipe gesture edge کشیدن لبه',
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
        // Right after the swipe: the other gesture a note answers to.
        _Row(
          icon: Icons.touch_app_outlined,
          title: nexLabel(context, 'Hold menu', 'منوی نگه‌داشتن'),
          keywords: 'long press hold menu actions نگه داشتن منو',
          value: nexLabel(
            context,
            '${preferences.holdMenuActions.length} actions',
            '${preferences.holdMenuActions.length} گزینه',
          ),
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => _HoldMenuScreen(preferences: preferences),
            ),
          ),
        ),
        _SwitchRow(
          icon: Icons.timeline_outlined,
          title: l10n.threadSuggestions,
          subtitle: l10n.threadSuggestionsSubtitle,
          value: preferences.threadSuggestions,
          onChanged: preferences.setThreadSuggestions,
        ),
        // The Quick Settings tile needs no switch — it is added from the
        // shade's own edit screen — but a notification that stays in the
        // shade is something to opt into.
        if (defaultTargetPlatform == TargetPlatform.android)
          _SwitchRow(
            icon: Icons.notifications_none_outlined,
            title: nexLabel(
              context,
              'Capture from notifications',
              'ثبت از کشوی اعلان‌ها',
            ),
            subtitle: nexLabel(
              context,
              'A silent row with Note, Voice and Photo. The Quick Settings '
                  'tile "Nex capture" can be added from the shade.',
              'یک ردیف بی‌صدا با یادداشت، صدا و عکس. کاشی «ثبت در Nex» را '
                  'هم می‌توانید در تنظیمات سریع اضافه کنید.',
            ),
            value: preferences.quickCaptureNotification,
            onChanged: (value) => unawaited(() async {
              if (value) await services.reminders.requestPermission();
              await preferences.setQuickCaptureNotification(value);
              await QuickCaptureNotification.setEnabled(value);
            }()),
          ),
      ],
    ),
    _Section(
      id: 'notifications',
      preferences: preferences,
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
        // Sound, vibration and importance live on the OS side of the line —
        // see [NexNotificationSettings] for why an in-app picker would only
        // pretend to work — so these two rows are doors to the right screen
        // rather than controls of their own.
        if (NexNotificationSettings.supported) ...[
          _Row(
            icon: Icons.music_note_outlined,
            title: l10n.notificationSoundReminders,
            value: l10n.notificationSoundSubtitle,
            onTap: () =>
                unawaited(_openChannel(context, NexReminders.remindersChannel)),
          ),
          if (preferences.dailyNudge)
            _Row(
              icon: Icons.music_note_outlined,
              title: l10n.notificationSoundDaily,
              value: l10n.notificationSoundSubtitle,
              onTap: () =>
                  unawaited(_openChannel(context, NexReminders.dailyChannel)),
            ),
        ],
      ],
    ),
    _Section(
      id: 'data',
      preferences: preferences,
      title: l10n.dataAndBackup,
      children: [
        _Searchable(
          text:
              '${l10n.exportTitle} backup restore export complete recovery '
              'پشتیبان بازیابی خروجی',
          child: FutureBuilder<List<File>>(
            future: services.listBackups(),
            builder: (context, snapshot) => _Row(
              icon: Icons.import_export,
              title: l10n.exportTitle,
              value: l10n.backupCount(snapshot.data?.length ?? 0),
              onTap: () => Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) => BackupScreen(
                    services: services,
                    preferences: preferences,
                  ),
                ),
              ),
            ),
          ),
        ),
        _Searchable(
          text: 'import Google Keep Takeout archive درون‌ریزی',
          child: _ImportRow(services: services, preferences: preferences),
        ),
        // Sync is not offered here. The server exists and the client talks
        // to it, but there is no pairing flow in the app — the row asked
        // people to paste a base URL and a bearer token they have no way to
        // obtain, which is a setting that can only be got wrong. The code
        // stays; the row comes back when there is a way to pair.
      ],
    ),
    _Section(
      id: 'about',
      preferences: preferences,
      title: l10n.about,
      children: [
        _Searchable(
          text: '${l10n.checkForUpdate} update version به‌روزرسانی نسخه',
          child: _UpdateRow(updates: updates, preferences: preferences),
        ),
        _SwitchRow(
          icon: Icons.update_outlined,
          title: l10n.autoUpdateCheck,
          subtitle: l10n.autoUpdateCheckHint,
          value: preferences.autoUpdateCheck,
          onChanged: preferences.setAutoUpdateCheck,
        ),
        // The guide lives with the rest of "what is this app", rather than
        // as a category of its own holding one row.
        _Row(
          icon: Icons.menu_book_outlined,
          title: l10n.guideTitle,
          keywords: 'help guide how راهنما',
          value: l10n.guideSubtitle,
          onTap: () => unawaited(GuideScreen.show(context)),
        ),
        _Row(
          icon: Icons.speed_outlined,
          title: l10n.metricsTitle,
          keywords:
              'speed performance metrics measure startup reliability crash سرعت کارایی اندازه‌گیری پایداری',
          value: preferences.metricsEnabled
              ? l10n.metricsRowOn
              : l10n.metricsRowOff,
          onTap: () => Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => MetricsScreen(preferences: preferences),
            ),
          ),
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
