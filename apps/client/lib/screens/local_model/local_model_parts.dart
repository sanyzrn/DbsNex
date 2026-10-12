part of '../local_model_screen.dart';

// The pieces of the on-device model page. Split out of
// local_model_screen.dart (REL-10).

/// Everything to do with starting, pausing and finishing an install.
class _InstallControls extends StatelessWidget {
  const _InstallControls({
    required this.model,
    required this.install,
    required this.enabled,
    required this.onStart,
    required this.onPause,
    required this.onStop,
  });

  final ModelRelease model;

  /// Null when the install in flight, or paused, is another model's:
  /// this one is then simply not started.
  final ModelInstallController? install;

  /// False until the licence is accepted. That order is the licence
  /// condition, not a UX preference — and it gates the file picker too, since
  /// installing from a file is the same distribution by another route.
  final bool enabled;

  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phase = install?.phase ?? ModelInstallPhase.idle;
    final progress = install?.progress;
    final total = progress?.totalBytes ?? model.sizeBytes;

    return switch (phase) {
      ModelInstallPhase.downloading ||
      ModelInstallPhase.joining ||
      ModelInstallPhase.loading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            // Indeterminate while loading: the runtime reports nothing, and a
            // bar frozen at 100% reads as a hang, which is the exact
            // impression this phase exists to prevent.
            value: phase == ModelInstallPhase.loading
                ? null
                : progress?.fraction,
            minHeight: 4,
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(switch (phase) {
            ModelInstallPhase.loading => l10n.localModelLoading,
            ModelInstallPhase.joining => l10n.localModelJoining,
            _ when progress == null => l10n.localModelDownloading,
            _ when model.parts.length > 1 => l10n.localModelDownloadingPart(
              progress.partIndex + 1,
              progress.partCount,
            ),
            _ => l10n.localModelDownloading,
          }, style: theme.textTheme.bodySmall),
          if (progress != null && phase == ModelInstallPhase.downloading)
            Text(
              l10n.localModelBytes(
                _size(context, progress.receivedBytes),
                _size(context, total),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: NexSpacing.md),
          if (phase == ModelInstallPhase.downloading)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause),
                    label: Text(l10n.localModelPause),
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.localModelStop),
                  ),
                ),
              ],
            ),
          const SizedBox(height: NexSpacing.sm),
          Text(l10n.localModelKeepOpen, style: theme.textTheme.bodySmall),
        ],
      ),
      ModelInstallPhase.paused => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: progress?.fraction, minHeight: 4),
          const SizedBox(height: NexSpacing.sm),
          Text(
            l10n.localModelPaused(
              _size(context, progress?.receivedBytes ?? 0),
              _size(context, total),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.localModelResume),
                ),
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.close),
                  label: Text(l10n.localModelStop),
                ),
              ),
            ],
          ),
        ],
      ),
      _ => FilledButton.icon(
        onPressed: enabled ? onStart : null,
        icon: const Icon(Icons.download_outlined),
        label: Text(
          l10n.localModelDownload(_gigabytes(context, model.sizeBytes)),
        ),
      ),
    };
  }
}

String _gigabytes(BuildContext context, int bytes) => nexDigits(
  (bytes / 1000000000).toStringAsFixed(1),
  persian: Localizations.localeOf(context).languageCode == 'fa',
);

/// Bytes as someone reads them on a data plan.
String _size(BuildContext context, int bytes) => nexDigits(
  _rawSize(bytes),
  persian: Localizations.localeOf(context).languageCode == 'fa',
);

String _rawSize(int bytes) {
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(0)} MB';
  return '${(bytes / 1000).toStringAsFixed(0)} KB';
}

/// A model that is on the phone and will not start.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.localModelLoadFailed,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            l10n.localModelLoadFailedDetail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          // Selectable so it can be copied into a bug report. An error nobody
          // can quote is an error nobody can fix.
          SelectableText(
            detail,
            contextMenuBuilder: nexReadingMenu,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the device cannot have this, said plainly.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.blocker, required this.model});

  final LocalAiBlocker blocker;
  final ModelRelease model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: theme.colorScheme.secondary),
        const SizedBox(width: NexSpacing.sm),
        Expanded(
          child: Text(switch (blocker) {
            LocalAiBlocker.platform => l10n.localModelBlockedPlatform,
            LocalAiBlocker.architecture => l10n.localModelBlockedArchitecture,
            LocalAiBlocker.storage => l10n.localModelBlockedStorage(
              _gigabytes(context, model.sizeBytes * 2),
            ),
            LocalAiBlocker.notPublished => l10n.localModelBlockedUnpublished,
          }, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Installed extends StatelessWidget {
  const _Installed({
    required this.bytes,
    required this.onDelete,
    required this.onRetry,
    required this.loading,
  });

  final int bytes;
  final VoidCallback onDelete;

  /// Loads the model again from a clean slate — every backend given up on
  /// is tried again. The way back from "would not start" that does not cost
  /// another download.
  final VoidCallback onRetry;

  /// True while that load is running.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                l10n.localModelInstalled(_gigabytes(context, bytes)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.lg),
        if (loading) ...[
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: NexSpacing.sm),
          Text(l10n.localModelLoading, style: theme.textTheme.bodySmall),
        ] else
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.localModelRetry),
          ),
        const SizedBox(height: NexSpacing.sm),
        OutlinedButton.icon(
          onPressed: loading ? null : onDelete,
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.localModelDelete),
        ),
      ],
    );
  }
}

/// The terms, and the button that is the licence condition.
class _License extends StatelessWidget {
  const _License({
    required this.model,
    required this.accepted,
    required this.onAccept,
  });

  final ModelRelease model;
  final bool accepted;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.localModelLicenseTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: NexSpacing.sm),
          // The notice text verbatim, in English, and left-to-right whatever
          // the interface is set to. Gemma's terms name this exact sentence
          // as the notice that must be reproduced, so translating it would be
          // paraphrasing a legal requirement — and in a Persian interface it
          // was also being laid out right-to-left, which is the wrong shape
          // for an English sentence ending in a URL.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                model.licenseNotice,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          // What it says, in the interface's own language. The notice above
          // has to stay as Google wrote it; nothing stops Nex from also
          // saying what it means.
          Text(
            l10n.localModelLicenseGloss,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse(model.licenseUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l10n.localModelLicenseRead),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            // One-way on purpose: this records that the terms were shown and
            // agreed to. Un-ticking it would not un-show them, and the model
            // can be deleted, which is the action that actually undoes this.
            onChanged: accepted ? null : (_) => onAccept(),
            title: Text(
              l10n.localModelLicenseAccept,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The models on offer, the one in use selected. Picking one makes it the
/// one the assistant answers with; each keeps its own download.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.store,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });

  final NexModelStore store;
  final ModelRelease selected;
  final bool enabled;
  final ValueChanged<ModelRelease> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.localModelChoose, style: theme.textTheme.titleSmall),
        const SizedBox(height: NexSpacing.xs),
        RadioGroup<String>(
          groupValue: selected.id,
          onChanged: (id) {
            final model = NexModels.byId(id);
            if (enabled && model != null) onPick(model);
          },
          child: Column(
            children: [
              for (final model in NexModels.all)
                RadioListTile<String>(
                  key: ValueKey('local-model-${model.id}'),
                  value: model.id,
                  enabled: enabled,
                  contentPadding: EdgeInsets.zero,
                  title: Text(model.name),
                  subtitle: Text(
                    [
                      _gigabytes(context, model.sizeBytes),
                      if (store.isInstalled(model))
                        l10n.localModelOnPhone
                      else if (store.partialBytes(model) > 0)
                        l10n.localModelPartial(
                          _size(context, store.partialBytes(model)),
                        ),
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
