part of '../settings_sheet.dart';

/// Sends the user to the OS screen, and says so when there isn't one.
///
/// A row that silently does nothing is worse than a row that is not there;
/// this one is offered on Android and still has to survive a ROM with no
/// activity behind the intent.
Future<void> _openChannel(BuildContext context, String channelId) async {
  final l10n = AppLocalizations.of(context);
  final opened = await NexNotificationSettings.open(channelId);
  if (opened || !context.mounted) return;
  nexShowBanner(
    context,
    message: l10n.notificationSoundUnavailable,
    kind: NexBannerKind.failed,
  );
}

/// What the widget is currently filtered to, in one line.
///
/// Says the filters rather than the screen's name: the row is worth opening
/// when it does not say "Everything", and worth leaving alone when it does.
String _widgetFilterSummary(AppLocalizations l10n, NexPreferences preferences) {
  final types = preferences.widgetTypes;
  final tags = preferences.widgetTags.values.where((n) => n.isNotEmpty);
  final kinds = types.isEmpty
      ? l10n.widgetSettingsEverything
      : types.map(l10n.noteType).join(', ');
  return tags.isEmpty ? kinds : '$kinds · ${tags.join(', ')}';
}

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

/// One category of settings: its rows, on one card.
///
/// It used to be an accordion — every category on the one page, each
/// opening and closing in place, the open ones remembered. With fourteen
/// rows spread over seven of them it was still a long page, and nobody could
/// see the shape of Settings without opening everything. The front page is
/// now a list of categories, one line each ([_CategoryRow]), and each one
/// opens on its own page ([_SettingsCategoryScreen]); search still finds any
/// row from anywhere.
///
/// [icon], [summary] and [badge] are how the category reads on the front
/// page; the card itself is what its page shows.
class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.icon,
    required this.title,
    required this.children,
    this.summary,
    this.badge = false,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? summary;
  final bool badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _SettingsCard(children: children);
}

/// Rows on a rounded card, with dividers between them.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
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
    );
  }
}

/// A category on the Settings front page.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.section, required this.onTap});

  final _Section section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey('settings-category-${section.id}'),
    child: _Row(
      icon: section.icon,
      title: section.title,
      value: section.summary,
      badge: section.badge,
      onTap: onTap,
    ),
  );
}

/// One category's own page.
///
/// It asks the sheet for its rows on every rebuild rather than holding the
/// list it was opened with, so a value changed here — or by a picker opened
/// from here — shows at once.
class _SettingsCategoryScreen extends StatelessWidget {
  const _SettingsCategoryScreen({required this.sheet, required this.id});

  final SettingsSheet sheet;
  final String id;

  _Section _section(BuildContext context) => sheet
      ._groups(context, AppLocalizations.of(context))
      .whereType<_Section>()
      .firstWhere((section) => section.id == id);

  @override
  Widget build(BuildContext context) {
    final updates = sheet.updates;
    return ListenableBuilder(
      listenable: Listenable.merge([sheet.preferences, ?updates]),
      builder: (context, _) {
        final section = _section(context);
        return Scaffold(
          appBar: AppBar(title: Text(section.title)),
          body: ListView(
            padding: const EdgeInsets.all(NexSpacing.md),
            children: [section],
          ),
        );
      },
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
    this.keywords = '',
  });

  final IconData icon;
  final String title;

  /// Words Settings search should find this row by, beyond its own — what
  /// the screen it opens contains, in both languages (W6.6).
  final String keywords;

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
