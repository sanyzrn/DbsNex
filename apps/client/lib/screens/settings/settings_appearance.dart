part of '../settings_sheet.dart';

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
      initial: preferences.accentSeed ?? _hex(_themeAccent(preferences)),
      title: l10n.accentColorPickerTitle,
      preferences: preferences,
      // The app always has an accent — something is drawing the caret right
      // now — so "no colour" was never one of the answers here. The picker
      // was offering it anyway, as a crossed-out empty dot, for what is
      // actually "back to the one Nex ships with". Naming the colour lets the
      // swatch show it.
      defaultColor: _themeAccent(preferences),
    );
    if (result == null) return;
    await preferences.setAccentSeed(result.color);
  }

  /// The accent the chosen palette brings, or the shipped one for Classic.
  static Color _themeAccent(NexPreferences preferences) =>
      nexThemePresetSeed(preferences.themePreset) ?? NexColors.accentLight;

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // What is actually on screen: a palette's own accent when nothing custom
    // was picked. Showing the shipped blue here after choosing Forest made
    // the row disagree with every control around it.
    final swatch =
        nexParseTagColor(preferences.accentSeed) ?? _themeAccent(preferences);
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

class _ThemeScreen extends StatelessWidget {
  const _ThemeScreen({required this.preferences});
  final NexPreferences preferences;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.theme)),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            _Row(
              icon: Icons.view_agenda_outlined,
              title: l10n.cardDensity,
              keywords:
                  'density compact card size readable تراکم فشرده خوانا کارت',
              value: switch (preferences.cardDensity) {
                NexCardDensity.compact => l10n.cardDensityCompact,
                NexCardDensity.standard => l10n.cardDensityStandard,
                NexCardDensity.readable => l10n.cardDensityReadable,
              },
              onTap: () => unawaited(
                _pick<NexCardDensity>(
                  context: context,
                  title: l10n.cardDensity,
                  selected: preferences.cardDensity,
                  onSelected: preferences.setCardDensity,
                  choices: [
                    NexChoice(
                      value: NexCardDensity.compact,
                      label: l10n.cardDensityCompact,
                      preview: const Icon(Icons.density_small),
                    ),
                    NexChoice(
                      value: NexCardDensity.standard,
                      label: l10n.cardDensityStandard,
                      preview: const Icon(Icons.density_medium),
                    ),
                    NexChoice(
                      value: NexCardDensity.readable,
                      label: l10n.cardDensityReadable,
                      preview: const Icon(Icons.density_large),
                    ),
                  ],
                ),
              ),
            ),
            _AccentColorRow(preferences: preferences),
            const SizedBox(height: 24),
            Text(
              nexLabel(
                context,
                'Your everyday atmosphere',
                'حال‌وهوای روزمرهٔ شما',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final preset in nexThemePresets)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: preset.seed,
                    child: Icon(preset.icon, color: Colors.white),
                  ),
                  title: Text(nexThemePresetLabel(context, preset.id)),
                  subtitle: Text(
                    nexLabel(
                      context,
                      preset.enDescription,
                      preset.faDescription,
                    ),
                  ),
                  trailing: preferences.themePreset == preset.id
                      ? const Icon(Icons.check_circle)
                      : null,
                  // A palette arrives with its own accent. A custom accent
                  // picked earlier would otherwise keep overriding it, and
                  // choosing "Forest" would leave a blue caret behind.
                  onTap: () async {
                    await preferences.setAccentSeed(null);
                    await preferences.setThemePreset(preset.id);
                  },
                ),
              ),
            // Last on the page: the icon on the home screen is part of how
            // the app looks, but it is the one choice that is not about the
            // inside of it.
            if (NexAppIcons.supported) const _AppIconPicker(),
          ],
        ),
      ),
    );
  }
}

/// Six launcher icons to choose from, at the end of the Theme page.
class _AppIconPicker extends StatefulWidget {
  const _AppIconPicker();

  @override
  State<_AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<_AppIconPicker> {
  String? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      NexAppIcons.current().then((id) {
        if (mounted) setState(() => _current = id);
      }),
    );
  }

  Future<void> _choose(String id) async {
    if (_busy || id == _current) return;
    setState(() => _busy = true);
    final ok = await NexAppIcons.set(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _current = id;
    });
    nexShowBanner(
      context,
      kind: ok ? NexBannerKind.done : NexBannerKind.failed,
      message: ok
          ? nexLabel(
              context,
              'Icon changed. Your launcher may take a moment to show it.',
              'آیکون عوض شد. ممکن است چند لحظه طول بکشد تا لانچر نشانش دهد.',
            )
          : nexLabel(
              context,
              'The icon could not be changed.',
              'تغییر آیکون انجام نشد.',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          nexLabel(context, 'App icon', 'آیکون برنامه'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          nexLabel(
            context,
            'Changes the icon on your home screen and app drawer. A shortcut '
                'you placed on the home screen may need adding again.',
            'آیکون صفحهٔ اصلی و فهرست برنامه‌ها را عوض می‌کند. ممکن است لازم '
                'باشد میان‌بری را که روی صفحهٔ اصلی گذاشته‌اید دوباره اضافه کنید.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final (index, id) in NexAppIcons.ids.indexed)
              _AppIconTile(
                id: id,
                label: index == 0
                    ? nexLabel(context, 'Nex', 'نکس')
                    : nexLabel(
                        context,
                        'Icon ${index + 1}',
                        'آیکون ${index + 1}',
                      ),
                selected: _current == id,
                onTap: _busy ? null : () => unawaited(_choose(id)),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _AppIconTile extends StatelessWidget {
  const _AppIconTile({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('app-icon-$id'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: NexMotion.standard,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipOval(
                    child: Image.asset(
                      NexAppIcons.preview(id),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (context, _, _) =>
                          ColoredBox(color: scheme.surfaceContainerHigh),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_circle, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
