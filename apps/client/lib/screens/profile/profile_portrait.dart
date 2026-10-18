import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_banner.dart';

part 'profile_portrait_written.dart';

/// The writing portrait at the foot of the profile (2.1.7).
///
/// Two layers, deliberately. The counted one — when somebody writes, what
/// kind of notes they keep, how often, about what — is arithmetic over the
/// library and needs nothing but the phone, so it is there for everyone once
/// there is enough to count. The written one is a model reading a sample of
/// the notes, and is only ever asked for here, by a button that says what it
/// sends.
///
/// Locked until there is something to read: a ring fills toward
/// [NexWritingStats.minNotes] notes on [NexWritingStats.minDays] days, so
/// the empty state is a goal rather than a blank.
class ProfilePortrait extends StatefulWidget {
  const ProfilePortrait({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<ProfilePortrait> createState() => _ProfilePortraitState();
}

class _ProfilePortraitState extends State<ProfilePortrait> {
  /// Notes a portrait is written from at most; said on the button.
  static const _sample = 80;

  NexWritingStats? _stats;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  Future<void> _count() async {
    final notes = await widget.services.portraitNotes();
    if (!mounted) return;
    setState(() => _stats = nexWritingStats(notes));
  }

  Future<void> _write() async {
    if (_writing) return;
    setState(() => _writing = true);
    final portrait = await widget.services.writePortrait();
    if (!mounted) return;
    setState(() => _writing = false);
    if (portrait == null) {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).portraitFailed,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = _stats;
    final portrait = widget.preferences.profilePortrait;
    return DecoratedBox(
      key: const ValueKey('profile-portrait'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.13),
              scheme.surfaceContainerLow,
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.03),
              scheme.surfaceContainerLow,
            ),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: NexAnimatedSize(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(l10n: l10n),
              const SizedBox(height: NexSpacing.lg),
              if (stats == null)
                const NexSkeleton(height: 72)
              else if (!stats.unlocked && portrait == null)
                _Locked(stats: stats)
              else ...[
                if (stats.notes > 0) ...[
                  _Counted(stats: stats),
                  const SizedBox(height: NexSpacing.lg),
                  Divider(color: scheme.primary.withValues(alpha: 0.15)),
                  const SizedBox(height: NexSpacing.md),
                ],
                if (_writing)
                  _Writing(label: l10n.portraitWriting)
                else if (portrait != null)
                  _Written(
                    portrait: portrait,
                    preferences: widget.preferences,
                    onRewrite:
                        widget.services.portraitWritable && stats.unlocked
                        ? () => unawaited(_write())
                        : null,
                  )
                else if (widget.services.portraitWritable)
                  _Ask(
                    onWrite: () => unawaited(_write()),
                    privacy: l10n.portraitPrivacy(
                      nexDigits('$_sample', persian: l10n.localeName == 'fa'),
                    ),
                  )
                else
                  Text(
                    l10n.portraitNeedsAi,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  l10n.portraitDisclaimer,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primaryContainer],
            ),
          ),
          child: Icon(Icons.auto_awesome, size: 22, color: scheme.onPrimary),
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.portraitTitle, style: theme.textTheme.titleMedium),
              Text(
                l10n.portraitSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Not enough to read yet: a ring filling toward the notes needed.
class _Locked extends StatelessWidget {
  const _Locked({required this.stats});

  final NexWritingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final progress = (stats.notes / NexWritingStats.minNotes).clamp(0.0, 1.0);
    return Row(
      key: const ValueKey('profile-portrait-locked'),
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: NexMotion.of(context, NexMotion.slow),
                curve: NexMotion.curve,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                ),
              ),
              Center(
                child: Text(
                  nexDigits(
                    '${stats.notes.clamp(0, NexWritingStats.minNotes)}/'
                    '${NexWritingStats.minNotes}',
                    persian: persian,
                  ),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stats.notesToGo > 0)
                Text(
                  _digits(l10n.portraitLocked(stats.notesToGo), persian),
                  style: theme.textTheme.bodyMedium,
                ),
              if (stats.daysToGo > 0)
                Text(
                  _digits(l10n.portraitLockedDays(stats.daysToGo), persian),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _digits(String text, bool persian) => nexDigits(text, persian: persian);

/// The counted layer: rhythm, three figures, what kind of notes, tags.
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
        const SizedBox(height: NexSpacing.lg),
        // One height for all three, whichever label wraps.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Figure(
                value: nexDigits('${stats.notes}', persian: persian),
                label: l10n.portraitNotes,
              ),
              const SizedBox(width: NexSpacing.sm),
              _Figure(
                value: nexDigits('${stats.activeLast30}', persian: persian),
                label: l10n.portraitActiveDays,
              ),
              if (rate != null) ...[
                const SizedBox(width: NexSpacing.sm),
                _Figure(
                  value: nexDigits(
                    '${(rate * 100).round()}%',
                    persian: persian,
                  ),
                  label: l10n.portraitTicked,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.lg),
        Text(l10n.portraitKinds, style: label),
        const SizedBox(height: NexSpacing.sm),
        _Kinds(stats: stats),
        if (stats.tags.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.lg),
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
                    color: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(NexRadius.xl),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  // No middle dot: in Vazirmatn it reads as a Persian zero.
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
      ],
    );
  }
}

/// Four columns, one per part of the day, the busiest one in full colour.
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
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: most == 0 ? 0 : stats.dayParts[i] / most,
                    ),
                    duration: NexMotion.of(context, NexMotion.slow),
                    curve: NexMotion.curve,
                    builder: (context, value, _) => Container(
                      height: 6 + (tallest - 6) * value,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(
                          alpha: i == peak ? 1 : 0.32,
                        ),
                        borderRadius: BorderRadius.circular(NexRadius.sm),
                      ),
                    ),
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
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.sm,
          vertical: NexSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(NexRadius.lg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
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

/// One bar split by kind of note, and its key.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(NexRadius.sm),
          child: SizedBox(
            height: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (type, count) in kinds)
                  Expanded(
                    flex: count,
                    child: ColoredBox(color: tint(type)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.md,
          runSpacing: NexSpacing.xs,
          children: [
            for (final (type, count) in kinds)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: tint(type),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: NexSpacing.xs),
                  Text(
                    '${l10n.noteType(type.name)} '
                    '${nexDigits('$count', persian: persian)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask({required this.onWrite, required this.privacy});

  final VoidCallback onWrite;
  final String privacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('profile-portrait-write'),
          onPressed: onWrite,
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.portraitWrite),
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          privacy,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Writing extends StatelessWidget {
  const _Writing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: NexSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}
