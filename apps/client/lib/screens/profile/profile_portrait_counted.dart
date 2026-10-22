part of 'profile_portrait.dart';

/// The counted layer: rhythm, figures, the last 30 days, what kind of notes,
/// tags. Each block arrives in turn ([_Staged]), the numbers count up and the
/// charts draw themselves.
class _Counted extends StatelessWidget {
  const _Counted({required this.stats});

  final NexWritingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final label = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final peak = stats.peak;
    final rate = stats.checklistRate;
    return Column(
      key: const ValueKey('profile-portrait-counted'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Staged(
          slot: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.portraitRhythm, style: label),
              const SizedBox(height: NexSpacing.sm),
              _Rhythm(stats: stats),
              if (peak != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(switch (peak) {
                  NexDayPart.morning => l10n.portraitPeakMorning,
                  NexDayPart.afternoon => l10n.portraitPeakAfternoon,
                  NexDayPart.evening => l10n.portraitPeakEvening,
                  NexDayPart.night => l10n.portraitPeakNight,
                }, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.lg),
        // One height for all of them, whichever label wraps.
        _Staged(
          slot: 1,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Figure(
                  value: stats.notes,
                  slot: 1,
                  label: l10n.portraitNotes,
                  persian: persian,
                ),
                const SizedBox(width: NexSpacing.sm),
                _Figure(
                  value: stats.streak,
                  slot: 2,
                  label: l10n.portraitStreak,
                  persian: persian,
                  icon: Icons.local_fire_department_outlined,
                ),
                const SizedBox(width: NexSpacing.sm),
                _Figure(
                  value: stats.activeLast30,
                  slot: 3,
                  label: l10n.portraitActiveDays,
                  persian: persian,
                ),
                if (rate != null) ...[
                  const SizedBox(width: NexSpacing.sm),
                  _Figure(
                    value: (rate * 100).round(),
                    suffix: '%',
                    slot: 4,
                    label: l10n.portraitTicked,
                    persian: persian,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (stats.recent.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.lg),
          _Staged(
            slot: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.portraitLast30, style: label),
                const SizedBox(height: NexSpacing.sm),
                _Pulse(days: stats.recent, slot: 2),
                if (stats.longestStreak > 1) ...[
                  const SizedBox(height: NexSpacing.sm),
                  Text(
                    nexDigits(
                      l10n.portraitBestStreak(stats.longestStreak),
                      persian: persian,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: NexSpacing.lg),
        _Staged(
          slot: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.portraitKinds, style: label),
              const SizedBox(height: NexSpacing.sm),
              _Kinds(stats: stats),
            ],
          ),
        ),
        if (stats.tags.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.lg),
          _Staged(
            slot: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.portraitTopics, style: label),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final (name, count) in stats.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.md,
                          vertical: NexSpacing.xs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest.withValues(
                            alpha: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(NexRadius.xl),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        // No middle dot: in Vazirmatn it reads as a Persian
                        // zero.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: NexTextSurface.line(
                                '#$name',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                            const SizedBox(width: NexSpacing.sm),
                            Text(
                              nexDigits('$count', persian: persian),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Four columns, one per part of the day, the busiest one in full colour. The
/// columns grow with the entrance.
class _Rhythm extends StatelessWidget {
  const _Rhythm({required this.stats});

  final NexWritingStats stats;

  static const _icons = [
    Icons.wb_twilight,
    Icons.wb_sunny_outlined,
    Icons.brightness_6_outlined,
    Icons.bedtime_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entrance = _Entrance.of(context);
    final names = [
      l10n.portraitMorning,
      l10n.portraitAfternoon,
      l10n.portraitEvening,
      l10n.portraitNight,
    ];
    final most = stats.dayParts.fold<int>(0, (a, b) => a > b ? a : b);
    final peak = stats.peak?.index;
    const tallest = 56.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < NexDayPart.values.length; i++) ...[
          if (i > 0) const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Semantics(
              label: '${names[i]}: ${stats.dayParts[i]}',
              excludeSemantics: true,
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: entrance,
                    builder: (context, _) {
                      final grown = most == 0
                          ? 0.0
                          : stats.dayParts[i] /
                                most *
                                _slice(entrance.value, i, span: 0.4);
                      return Container(
                        height: 6 + (tallest - 6) * grown,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(
                            alpha: i == peak ? 1 : 0.32,
                          ),
                          borderRadius: BorderRadius.circular(NexRadius.sm),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: NexSpacing.xs + 2),
                  Icon(
                    _icons[i],
                    size: 18,
                    color: i == peak ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  Text(
                    names[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: i == peak
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.slot,
    required this.label,
    required this.persian,
    this.suffix = '',
    this.icon,
  });

  final int value;
  final int slot;
  final String label;
  final bool persian;
  final String suffix;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.xs,
          vertical: NexSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(NexRadius.lg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null && value > 0) ...[
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 2),
                  ],
                  _CountUp(
                    value: value,
                    suffix: suffix,
                    slot: slot,
                    persian: persian,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the library is made of: a ring beside its key.
class _Kinds extends StatelessWidget {
  const _Kinds({required this.stats});

  final NexWritingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final kinds = [
      for (final (type, count) in stats.types)
        if (count > 0) (type, count),
    ];
    if (kinds.isEmpty) return const SizedBox.shrink();
    Color tint(NoteType type) => nexNoteTypeTint(type.wireName, scheme);
    return Row(
      children: [
        _KindsDonut(
          kinds: kinds,
          tint: tint,
          slot: 3,
          total: stats.notes,
          persian: persian,
        ),
        const SizedBox(width: NexSpacing.lg),
        Expanded(
          child: Wrap(
            spacing: NexSpacing.md,
            runSpacing: NexSpacing.sm,
            children: [
              for (final (type, count) in kinds)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: tint(type),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: NexSpacing.xs),
                    Text(
                      '${l10n.noteType(type.name)} '
                      '${nexDigits('$count', persian: persian)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
