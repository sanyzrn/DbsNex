part of '../ai_provider_screen.dart';

/// The two actions, always reachable, whatever the list is doing above them.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.testing,
    required this.canSave,
    required this.showTest,
    required this.onTest,
    required this.onSave,
  });

  final bool testing;
  final bool canSave;
  final bool showTest;
  final VoidCallback onTest;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        NexSpacing.lg,
        NexSpacing.md,
        NexSpacing.lg,
        NexSpacing.md + nexBottomInset(context),
      ),
      child: Row(
        children: [
          if (showTest) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: testing ? null : onTest,
                icon: testing
                    ? const NexInlineSpinner()
                    : const Icon(Icons.wifi_tethering),
                label: Text(l10n.testConnection),
              ),
            ),
            const SizedBox(width: NexSpacing.md),
          ],
          // Save is always here, including for "no provider": that is a choice
          // like any other, and it used to be unstorable because the only
          // button that could store it was hidden along with the key fields.
          OutlinedButton(
            onPressed: canSave ? onSave : null,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

/// One provider, shown as a row you can see without opening anything.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.name,
    required this.selected,
    required this.subtitle,
    required this.onTap,
  });

  final AiProvider provider;

  /// [provider]'s name in the reader's language — see `nexProviderName`.
  final String name;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: AnimatedContainer(
          duration: NexMotion.standard,
          curve: NexMotion.curve,
          constraints: const BoxConstraints(minHeight: nexMinTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NexRadius.md),
            color: selected
                ? accent.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest,
          ),
          // Laid out left-to-right whatever the interface language is. Every
          // name and model id in this list is a Latin identifier, and
          // mirroring the row put "gpt-4o-mini" at the right edge reading
          // outward from the wrong end. Only the row turns — the Persian prose
          // above and below it keeps the direction the language gives it.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Icon(
                  provider == AiProvider.none
                      ? Icons.phone_android_outlined
                      : Icons.cloud_outlined,
                  size: 20,
                  color: selected ? accent : theme.colorScheme.secondary,
                ),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        textDirection: nexDirectionOf(name),
                        textAlign: TextAlign.left,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: selected
                              ? accent
                              : theme.colorScheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall,
                          // The one subtitle that is prose rather than a model
                          // id is translated, so it shapes in its own
                          // direction — while still starting at the same edge
                          // as the name above it, which is what keeps the row
                          // reading as one block.
                          textDirection: nexDirectionOf(subtitle),
                          textAlign: TextAlign.left,
                        ),
                    ],
                  ),
                ),
                // A check that occupies its slot either way, so the rows do
                // not shift sideways as the selection moves down the list.
                Opacity(
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle, size: 20, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final AiTestResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = result.success
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.success ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Builder(
              builder: (context) {
                final message = result.success
                    ? l10n.connectionOk(result.detail)
                    : result.detail;
                return Text(
                  message,
                  style: theme.textTheme.bodyMedium,
                  // A failure detail is usually the provider's own English
                  // error, which does not belong right-aligned under a
                  // Persian UI.
                  textDirection: nexDirectionOf(message),
                  textAlign: TextAlign.start,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The way into downloading, replacing or removing the on-device model.
class _ManageModelRow extends StatelessWidget {
  const _ManageModelRow({required this.installed, required this.onTap});

  final bool installed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Row(
            children: [
              Icon(
                installed ? Icons.check_circle_outline : Icons.memory_outlined,
                color: installed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.localModelTitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      // Not "On-device only" repeated back. What someone needs
                      // here is whether the phone actually has the model, which
                      // is the difference between this option working and not.
                      installed
                          ? l10n.localModelManageInstalled
                          : l10n.localModelManageMissing,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
