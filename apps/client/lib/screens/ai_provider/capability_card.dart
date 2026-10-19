part of '../ai_provider_screen.dart';

/// What the model on screen can do besides writing, found by asking it
/// (2.1.8) — one row per capability, filled in as each answer lands.
///
/// In place of the dropdowns that asked the person to say. A row that says
/// "no" says why in the words that fit: the provider has no such service,
/// the model refused, or the check could not get an answer just now.
class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.config,
    required this.found,
    required this.canCheck,
    required this.solar,
    required this.onCheck,
  });

  /// What is on screen, with the last stored check carried along.
  final AiProviderConfig config;

  /// What a check from this screen found for exactly these fields, or null.
  final Map<AiCapability, AiProbeResult?>? found;

  /// Whether "Check again" applies: the fields are saved and nothing runs.
  final bool canCheck;
  final bool solar;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final checking = found?.values.contains(null) ?? false;
    final checkedAt = config.checkedTime;
    final String status;
    if (checking) {
      status = l10n.aiCanDoChecking;
    } else if (checkedAt != null) {
      status = l10n.aiCanDoCheckedAt(
        nexReadableDate(checkedAt, solar: solar, persian: persian, time: true),
      );
    } else if (config.checkedFor.isNotEmpty) {
      status = l10n.aiCanDoStale;
    } else {
      status = l10n.aiCanDoUnchecked;
    }
    final rows = [
      (
        AiCapability.images,
        Icons.image_search,
        l10n.aiCanImages,
        l10n.aiCanImagesUse,
      ),
      (
        AiCapability.audio,
        Icons.graphic_eq,
        l10n.aiCanAudio,
        l10n.aiCanAudioUse,
      ),
      (
        AiCapability.embeddings,
        Icons.travel_explore,
        l10n.aiCanSearch,
        l10n.aiCanSearchUse,
      ),
      (
        AiCapability.video,
        Icons.smart_display_outlined,
        l10n.aiCanVideo,
        l10n.aiCanVideoUse,
      ),
    ];
    return Container(
      key: const ValueKey('ai-capability-card'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  l10n.aiCanDoTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 20 + NexSpacing.sm,
              bottom: NexSpacing.sm,
            ),
            child: Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final (capability, icon, title, use) in rows)
            _CapabilityRow(
              key: ValueKey('ai-capability-${capability.name}'),
              icon: icon,
              title: title,
              use: use,
              status: nexCapabilityLine(
                l10n,
                config,
                capability,
                found: found?[capability],
                checking: checking && found?[capability] == null,
              ),
            ),
          // Under the rows rather than beside the title: at large text the
          // title had no room left beside it.
          if (canCheck && !checking)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('ai-check-again'),
                onPressed: onCheck,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.aiCheckAgain),
              ),
            ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            l10n.aiCanDoPrivacy,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.use,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String use;
  final ({NexCapabilityState state, String line}) status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Widget mark, Color tone) = switch (status.state) {
      NexCapabilityState.works => (
        Icon(Icons.check_circle, size: 20, color: scheme.primary),
        scheme.primary,
      ),
      NexCapabilityState.checking => (
        const NexInlineSpinner(),
        scheme.onSurfaceVariant,
      ),
      NexCapabilityState.expected => (
        Icon(Icons.radio_button_unchecked, size: 20, color: scheme.outline),
        scheme.onSurfaceVariant,
      ),
      NexCapabilityState.unknown => (
        Icon(Icons.help_outline, size: 20, color: scheme.tertiary),
        scheme.tertiary,
      ),
      NexCapabilityState.off => (
        Icon(Icons.remove_circle_outline, size: 20, color: scheme.outline),
        scheme.onSurfaceVariant,
      ),
    };
    final line = status.line;
    return Semantics(
      container: true,
      label: '$title. $line',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  Text(
                    use,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: NexMotion.of(context, NexMotion.standard),
                    child: Text(
                      line,
                      key: ValueKey(line),
                      style: theme.textTheme.labelMedium?.copyWith(color: tone),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: AnimatedSwitcher(
                  duration: NexMotion.of(context, NexMotion.standard),
                  child: KeyedSubtree(key: ValueKey(status.state), child: mark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
