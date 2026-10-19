part of '../settings_sheet.dart';

/// The intelligence layer at a glance, at the top of its category: whether it
/// is on and with whom, and which of its six abilities are working — lit or
/// dim — before opening anything.
class _IntelligenceGlance extends StatelessWidget {
  const _IntelligenceGlance({
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = preferences.aiEnabled;
    final abilities = nexAbilityGlance(preferences);
    return InkWell(
      key: const ValueKey('intelligence-glance'),
      onTap: () => Navigator.push(
        context,
        NexPageRoute<void>(
          builder: (_) =>
              IntelligenceScreen(services: services, preferences: preferences),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Row(
          children: [
            NexIntelligenceOrb(lit: on),
            const SizedBox(width: NexSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    on
                        ? l10n.intelligenceStateOn(
                            nexProviderName(
                              l10n,
                              preferences.aiProvider.provider,
                            ),
                          )
                        : l10n.intelligenceOff,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  if (on)
                    Wrap(
                      spacing: NexSpacing.xs,
                      children: [
                        for (final (glyph, working) in abilities)
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: working
                                  ? scheme.primary
                                  : scheme.surfaceContainerHigh,
                            ),
                            child: IconTheme(
                              data: IconThemeData(
                                size: 14,
                                color: working
                                    ? scheme.onPrimary
                                    : scheme.outline,
                              ),
                              child: Center(child: glyph),
                            ),
                          ),
                      ],
                    )
                  else
                    Text(
                      l10n.intelligenceStateOffShort,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
