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
        NexTextSurface(
          portrait.headline,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexTextSurface(
          portrait.portrait,
          selectable: true,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        const SizedBox(height: NexSpacing.lg),
        for (final trait in portrait.traits) ...[
          _Trait(trait: trait, persian: persian),
          const SizedBox(height: NexSpacing.md),
        ],
        if (portrait.strengths.isNotEmpty) ...[
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
        if (portrait.invitation.isNotEmpty) ...[
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
  const _Trait({required this.trait, required this.persian});

  final NexPortraitTrait trait;
  final bool persian;

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
              Text(
                nexDigits('${trait.score}', persian: persian),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: trait.score / 100),
              duration: NexMotion.of(context, NexMotion.slow),
              curve: NexMotion.curve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
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
