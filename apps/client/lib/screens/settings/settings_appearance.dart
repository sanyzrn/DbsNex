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

/// A stack of cards at a density, drawn rather than named: how many fit, and
/// how much room each takes.
class _DensityPreview extends StatelessWidget {
  const _DensityPreview({required this.density});

  final NexCardDensity density;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (count, height, gap) = switch (density) {
      NexCardDensity.compact => (4, 6.0, 2.5),
      NexCardDensity.standard => (3, 9.0, 3.5),
      NexCardDensity.readable => (2, 14.0, 4.0),
    };
    return SizedBox(
      width: 40,
      height: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(height: gap),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: scheme.outline, width: 1),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: height - 3,
                  height: height - 3,
                  margin: const EdgeInsetsDirectional.only(start: 1.5),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.md,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            // The three choices here used to be rows that each opened a
            // sheet to pick from — a tap to see the choices, a tap to make
            // one, and the result only visible once the sheet was gone. They
            // are the choices themselves now, in place, the way Language and
            // calendar shows its own.
            NexPanel(
              title: l10n.theme,
              icon: Icons.contrast,
              child: NexChoiceCards<ThemeMode>(
                selected: preferences.themeMode,
                onSelected: preferences.setThemeMode,
                choices: [
                  for (final (mode, label) in [
                    (ThemeMode.light, l10n.themeLight),
                    (ThemeMode.dark, l10n.themeDark),
                    (ThemeMode.system, l10n.themeSystem),
                  ])
                    NexChoice(
                      value: mode,
                      label: label,
                      preview: NexThemeSwatch(
                        mode: mode,
                        comfort: preferences.comfortMode,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: l10n.uiScale,
              icon: Icons.format_size,
              // The four steps are unchanged, but the type ramp underneath
              // them came down a step — so "Large" is roughly what "Default"
              // used to be, which is where anyone who liked the old size
              // should land.
              child: NexChoiceCards<double>(
                selected: preferences.uiScale,
                onSelected: preferences.setUiScale,
                choices: [
                  for (final (scale, label, size) in [
                    (0.9, l10n.uiScaleSmall, 13.0),
                    (1.0, l10n.uiScaleDefault, 17.0),
                    (1.15, l10n.uiScaleLarge, 21.0),
                    (1.3, l10n.uiScaleLarger, 25.0),
                  ])
                    NexChoice(
                      value: scale,
                      label: label,
                      preview: _TextSizePreview(fontSize: size),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: l10n.cardDensity,
              icon: Icons.view_agenda_outlined,
              child: NexChoiceCards<NexCardDensity>(
                selected: preferences.cardDensity,
                onSelected: preferences.setCardDensity,
                choices: [
                  for (final (density, label) in [
                    (NexCardDensity.compact, l10n.cardDensityCompact),
                    (NexCardDensity.standard, l10n.cardDensityStandard),
                    (NexCardDensity.readable, l10n.cardDensityReadable),
                  ])
                    NexChoice(
                      value: density,
                      label: label,
                      preview: _DensityPreview(density: density),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            _SettingsCard(
              children: [
                _AccentColorRow(preferences: preferences),
                _SwitchRow(
                  icon: Icons.blur_on_rounded,
                  title: l10n.liquidGlass,
                  subtitle: l10n.liquidGlassSubtitle,
                  value: preferences.liquidGlass,
                  onChanged: preferences.setLiquidGlass,
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            Text(
              nexLabel(
                context,
                'Your everyday atmosphere',
                'حال‌وهوای روزمرهٔ شما',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _PaletteGallery(preferences: preferences),
            const SizedBox(height: NexSpacing.lg),
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
        const SizedBox(height: NexSpacing.xs),
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
        const SizedBox(height: NexSpacing.md),
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
        borderRadius: BorderRadius.circular(NexRadius.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: NexMotion.standard,
          padding: const EdgeInsets.all(NexSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NexRadius.lg),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                // A little inside the tile: a preview the full width of a
                // third of the screen read as a poster, not an icon.
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.sm),
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
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_circle, size: 16, color: scheme.primary),
                    const SizedBox(width: NexSpacing.xs),
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
