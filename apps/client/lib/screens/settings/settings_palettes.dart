part of '../settings_sheet.dart';

/// Every palette as a small window onto it, two to a row.
///
/// Each used to be a row with a coloured circle and two lines of text, which
/// named the look without showing it. A tile now is the look: the palette's
/// own page colour in the current light or dark mode, its motif rising from
/// the bottom, a note card in its own tones, and its name in its own ink —
/// so choosing one is choosing what you can already see.
class _PaletteGallery extends StatelessWidget {
  const _PaletteGallery({required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = NexSpacing.sm;
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final preset in nexThemePresets)
              SizedBox(
                width: width,
                child: _PaletteTile(
                  preset: preset,
                  selected: preferences.themePreset == preset.id,
                  // A palette arrives with its own accent. A custom accent
                  // picked earlier would otherwise keep overriding it, and
                  // choosing "Forest" would leave a blue caret behind.
                  onTap: () async {
                    await preferences.setAccentSeed(null);
                    await preferences.setThemePreset(preset.id);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final NexThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  static final _schemes = <(String, Brightness), ColorScheme>{};

  /// The palette's colours as the app would draw them now — built once per
  /// palette and brightness, since a whole theme is not cheap to make.
  static ColorScheme _schemeOf(String id, Brightness brightness) =>
      _schemes.putIfAbsent(
        (id, brightness),
        () => nexApplyThemePreset(
          brightness == Brightness.dark ? nexDarkTheme() : nexLightTheme(),
          id,
          null,
        ).colorScheme,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final scheme = _schemeOf(preset.id, brightness);
    final dark = brightness == Brightness.dark;
    final texture = nexThemeTexture(preset.id);
    final name = nexThemePresetLabel(context, preset.id);
    final ink = scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: NexMotion.fast,
        curve: NexMotion.curve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          border: Border.all(
            color: selected ? scheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(NexRadius.lg - 1),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('palette-${preset.id}'),
            onTap: () {
              nexTick();
              onTap();
            },
            child: AspectRatio(
              aspectRatio: 0.92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (texture != NexThemeTexture.none)
                    CustomPaint(
                      painter: NexTexturePainter(
                        texture: texture,
                        // A little stronger than on the full screen: the
                        // tile is small, and the motif is what it shows.
                        ink: ink.withValues(alpha: dark ? 0.2 : 0.16),
                        extent: 0.7,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                preset.icon,
                                size: 16,
                                color: scheme.onPrimary,
                              ),
                            ),
                            const Spacer(),
                            AnimatedScale(
                              scale: selected ? 1 : 0,
                              duration: NexMotion.fast,
                              curve: NexMotion.popCurve,
                              child: Icon(
                                Icons.check_circle,
                                size: 22,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        // A note as this palette draws one.
                        _MiniCard(scheme: scheme),
                        const Spacer(),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          nexThemePresetDescription(context, preset.id),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note card in miniature: two lines of "text" and a tag in the
/// palette's accent.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    Widget line(double factor, Color color) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor,
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(NexRadius.xs),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(NexSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NexRadius.md),
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(0.9, scheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(height: 5),
          line(0.6, scheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 7),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 30,
              height: 9,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(NexRadius.sm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
