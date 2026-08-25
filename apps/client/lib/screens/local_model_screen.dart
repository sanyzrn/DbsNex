import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../platform/local_ai_support.dart';
import '../platform/model_install_controller.dart';
import '../platform/model_store.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_banner.dart';

/// Downloading, keeping and removing the on-device model.
///
/// The licence step here is not chrome. Gemma may be redistributed, and Nex
/// hosts these weights, which makes Nex the distributor — the terms have to
/// reach every recipient and the use restrictions have to carry forward
/// (09-ai.md). So acceptance is a gate before the first byte, not a link in a
/// corner someone may never open.
///
/// The install itself belongs to [ModelInstallController], not to this widget.
/// It used to live here, which meant a back gesture cancelled two gigabytes
/// with no warning; this screen now watches something that keeps running when
/// it is gone.
class LocalModelScreen extends StatefulWidget {
  const LocalModelScreen({
    super.key,
    required this.preferences,
    this.model = NexModels.gemma4E2B,
  });

  final NexPreferences preferences;
  final ModelRelease model;

  @override
  State<LocalModelScreen> createState() => _LocalModelScreenState();
}

class _LocalModelScreenState extends State<LocalModelScreen> {
  final _install = ModelInstallController.instance;

  NexModelStore? _store;
  LocalAiSupport? _support;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _install.addListener(_onInstallChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _install.removeListener(_onInstallChanged);
    // The store is not closed here any more. The controller may still be
    // downloading through it after this screen is gone, which is the whole
    // point of moving the install out.
    super.dispose();
  }

  void _onInstallChanged() {
    if (!mounted) return;
    setState(() {});
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    switch (_install.phase) {
      case ModelInstallPhase.installed:
        nexBump();
        host?.show(
          message: l10n.localModelReady,
          haptics: widget.preferences.haptics,
        );
        _install.reset();
      case ModelInstallPhase.failed:
        host?.show(
          message: l10n.localModelFailed,
          kind: NexBannerKind.failed,
          haptics: widget.preferences.haptics,
        );
        _install.reset();
      case _:
        break;
    }
  }

  Future<void> _load() async {
    // Support first, storage second. A device that cannot run this has no
    // reason to have a models directory created on it — and checking in this
    // order means the unsupported case never touches a platform channel,
    // which is what stopped this screen from resolving at all under test.
    final support = await LocalAi.check(widget.model);
    NexModelStore? store;
    if (support.supported) {
      try {
        store = await NexModelStore.open();
      } catch (_) {
        // No support directory means nowhere to put 2 GB. Reported as an
        // ordinary blocker rather than left as a spinner: a screen that never
        // resolves is the one failure a user cannot even describe.
        store = null;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _store = store;
      _support = store == null && support.supported
          ? const LocalAiSupport(
              blocker: LocalAiBlocker.storage,
              freeBytes: null,
            )
          : support;
      _accepted = widget.preferences.acceptedModelLicense(widget.model.id);
    });
  }

  Future<void> _accept() async {
    await widget.preferences.acceptModelLicense(widget.model.id);
    if (!mounted) return;
    nexBump();
    setState(() => _accepted = true);
  }

  void _start() {
    final store = _store;
    if (store == null) return;
    unawaited(_install.start(store, widget.model));
  }

  Future<void> _confirmStop() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.localModelStopTitle),
        content: Text(l10n.localModelStopBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.localModelStop),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_install.phase == ModelInstallPhase.downloading) {
      _install.stop();
    } else {
      final store = _store;
      if (store != null) await _install.discard(store, widget.model);
    }
  }

  Future<void> _delete() async {
    final store = _store;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.localModelDeleteTitle),
        content: Text(l10n.localModelDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.delete(widget.model);
    if (!mounted) return;
    nexBump();
    setState(() {});
    host?.show(
      message: l10n.localModelDeleted,
      haptics: widget.preferences.haptics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final store = _store;
    final support = _support;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.localModelTitle)),
      // Only the genuinely-unresolved state spins. Once [_load] has answered,
      // an unsupported device renders its reason with no store at all.
      body: support == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.md,
                NexSpacing.lg,
                NexSpacing.lg,
              ),
              children: [
                Text(
                  l10n.localModelExplained,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: NexSpacing.lg),
                if (!support.supported || store == null)
                  _Blocked(
                    blocker: support.blocker ?? LocalAiBlocker.storage,
                    model: widget.model,
                  )
                else if (store.isInstalled(widget.model)) ...[
                  _Installed(
                    bytes: store.installedBytes(widget.model),
                    onDelete: () => unawaited(_delete()),
                  ),
                  // The one place the runtime's own words are shown. A model
                  // that downloaded perfectly and then would not start is the
                  // failure most likely to be mistaken for the app being
                  // broken, and the three things that cause it — wrong file,
                  // no OpenCL, not enough memory — are indistinguishable
                  // without this string.
                  if (_install.loadError case final failure?) ...[
                    const SizedBox(height: NexSpacing.lg),
                    _LoadFailure(detail: failure),
                  ],
                ] else ...[
                  _License(
                    model: widget.model,
                    accepted: _accepted,
                    onAccept: () => unawaited(_accept()),
                  ),
                  const SizedBox(height: NexSpacing.lg),
                  _InstallControls(
                    model: widget.model,
                    install: _install,
                    enabled: _accepted,
                    onStart: _start,
                    onPause: _install.pause,
                    onStop: () => unawaited(_confirmStop()),
                  ),
                ],
              ],
            ),
    );
  }
}

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
  final ModelInstallController install;

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
    final progress = install.progress;
    final total = progress?.totalBytes ?? model.sizeBytes;

    return switch (install.phase) {
      ModelInstallPhase.downloading ||
      ModelInstallPhase.joining ||
      ModelInstallPhase.loading => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            // Indeterminate while loading: the runtime reports nothing, and a
            // bar frozen at 100% reads as a hang, which is the exact
            // impression this phase exists to prevent.
            value: install.phase == ModelInstallPhase.loading
                ? null
                : progress?.fraction,
            minHeight: 4,
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(switch (install.phase) {
            ModelInstallPhase.loading => l10n.localModelLoading,
            ModelInstallPhase.joining => l10n.localModelJoining,
            _ when progress == null => l10n.localModelDownloading,
            _ when model.parts.length > 1 => l10n.localModelDownloadingPart(
              progress.partIndex + 1,
              progress.partCount,
            ),
            _ => l10n.localModelDownloading,
          }, style: theme.textTheme.bodySmall),
          if (progress != null &&
              install.phase == ModelInstallPhase.downloading)
            Text(
              l10n.localModelBytes(_size(progress.receivedBytes), _size(total)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: NexSpacing.md),
          if (install.phase == ModelInstallPhase.downloading)
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
              _size(progress?.receivedBytes ?? 0),
              _size(total),
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
        label: Text(l10n.localModelDownload(_gigabytes(model.sizeBytes))),
      ),
    };
  }
}

String _gigabytes(int bytes) => (bytes / 1000000000).toStringAsFixed(1);

/// Bytes as someone reads them on a data plan.
String _size(int bytes) {
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
              _gigabytes(model.sizeBytes * 2),
            ),
            LocalAiBlocker.notPublished => l10n.localModelBlockedUnpublished,
          }, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Installed extends StatelessWidget {
  const _Installed({required this.bytes, required this.onDelete});

  final int bytes;
  final VoidCallback onDelete;

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
                l10n.localModelInstalled(_gigabytes(bytes)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.lg),
        OutlinedButton.icon(
          onPressed: onDelete,
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
