part of 'profile_portrait.dart';

/// The written layer: a headline, a paragraph, five traits as bars, the
/// strengths, one suggestion.
class _Written extends StatelessWidget {
  const _Written({
    required this.portrait,
    required this.preferences,
    required this.onRewrite,
  });

  final NexPortrait portrait;
  final NexPreferences preferences;
  final VoidCallback? onRewrite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    return Column(
      key: const ValueKey('profile-portrait-written'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Staged(
          slot: 5,
          child: _Sheen(
            child: NexTextSurface(
              portrait.headline,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        _Staged(
          slot: 6,
          child: NexTextSurface(
            portrait.portrait,
            selectable: true,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
        const SizedBox(height: NexSpacing.lg),
        if (portrait.traits.length >= 3) ...[
          _Staged(
            slot: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.portraitShape,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.xs),
                _TraitRadar(traits: portrait.traits, slot: 7),
              ],
            ),
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        for (var i = 0; i < portrait.traits.length; i++) ...[
          _Staged(
            slot: 8 + i.clamp(0, 4),
            child: _Trait(
              trait: portrait.traits[i],
              persian: persian,
              slot: 8 + i.clamp(0, 4),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        if (portrait.strengths.isNotEmpty)
          _Staged(
            slot: 13,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.portraitStrengths,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final strength in portrait.strengths)
                      Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          NexSpacing.sm,
                          NexSpacing.xs + 2,
                          NexSpacing.md,
                          NexSpacing.xs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(NexRadius.xl),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: NexSpacing.xs),
                            Flexible(
                              child: NexTextSurface.line(
                                strength,
                                style: theme.textTheme.labelMedium,
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
        if (portrait.invitation.isNotEmpty)
          _Staged(
            slot: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: NexSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(NexRadius.lg),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.portraitInvitation,
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: NexSpacing.xs),
                            NexTextSurface(
                              portrait.invitation,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NexSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.portraitWritten(
                  nexDisplayDate(
                    portrait.writtenAt,
                    solar: preferences.solarCalendar,
                    persian: persian,
                  ),
                  nexDigits('${portrait.basedOn}', persian: persian),
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onRewrite != null)
              TextButton.icon(
                key: const ValueKey('profile-portrait-rewrite'),
                onPressed: onRewrite,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.portraitRewrite),
              ),
          ],
        ),
      ],
    );
  }
}

class _Trait extends StatelessWidget {
  const _Trait({
    required this.trait,
    required this.persian,
    required this.slot,
  });

  final NexPortraitTrait trait;
  final bool persian;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '${trait.name}, ${trait.score}%. ${trait.line}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: NexTextSurface.line(
                  trait.name,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              _CountUp(
                value: trait.score,
                slot: slot,
                persian: persian,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: AnimatedBuilder(
              animation: _Entrance.of(context),
              builder: (context, _) => LinearProgressIndicator(
                value:
                    trait.score /
                    100 *
                    _slice(_Entrance.of(context).value, slot, span: 0.45),
                minHeight: 6,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          if (trait.line.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.xs),
            NexTextSurface(
              trait.line,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One soft band of light that crosses the headline once as it arrives.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final entrance = _Entrance.of(context);
    final glint = Theme.of(context).colorScheme.onPrimary;
    return AnimatedBuilder(
      animation: entrance,
      child: child,
      builder: (context, child) {
        final t = _slice(entrance.value, 5, span: 0.5);
        // Off the edge before it starts and after it ends, so a settled card
        // carries no shader at all.
        if (t <= 0 || t >= 1) return child!;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [
              glint.withValues(alpha: 0),
              glint.withValues(alpha: 0.55),
              glint.withValues(alpha: 0),
            ],
            stops: [
              (t * 1.6 - 0.6).clamp(0.0, 1.0),
              (t * 1.6 - 0.3).clamp(0.0, 1.0),
              (t * 1.6).clamp(0.0, 1.0),
            ],
          ).createShader(rect, textDirection: Directionality.of(context)),
          child: child,
        );
      },
    );
  }
}
