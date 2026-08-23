import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../platform/local_ai_support.dart';
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
  NexModelStore? _store;
  LocalAiSupport? _support;
  ModelInstallProgress? _progress;
  bool _installing = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
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
        // No support directory means nowhere to put 2.6 GB. Reported as an
        // ordinary blocker rather than left as a spinner: a screen that never
        // resolves is the one failure a user cannot even describe.
        store = null;
      }
    }
    if (!mounted) {
      store?.close();
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

  Future<void> _install() async {
    final store = _store;
    if (store == null || _installing) return;
    setState(() => _installing = true);
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    try {
      await store.install(
        widget.model,
        // Rebuilding on every chunk would be a setState per network read.
        // The progress object is cheap; the frame it schedules is what costs,
        // and Flutter coalesces those — so this stays simple rather than
        // throttling something that does not need it yet.
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      nexBump();
      host?.show(
        message: l10n.localModelReady,
        haptics: widget.preferences.haptics,
      );
    } catch (_) {
      // Every failure here is recoverable and resumable — a dropped
      // connection, a bad part, a full disk. One message and the button comes
      // back, rather than an error someone has to interpret.
      host?.show(
        message: l10n.localModelFailed,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
    } finally {
      if (mounted) setState(() => _installing = false);
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
                else if (store.isInstalled(widget.model))
                  _Installed(
                    bytes: store.installedBytes(widget.model),
                    onDelete: () => unawaited(_delete()),
                  )
                else ...[
                  _License(
                    model: widget.model,
                    accepted: _accepted,
                    onAccept: () => unawaited(_accept()),
                  ),
                  const SizedBox(height: NexSpacing.lg),
                  if (_installing)
                    _Progress(progress: _progress)
                  else
                    FilledButton.icon(
                      // Disabled until the terms are accepted. That order is
                      // the licence condition, not a UX preference.
                      onPressed: _accepted ? () => unawaited(_install()) : null,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(
                        l10n.localModelDownload(
                          _gigabytes(widget.model.sizeBytes),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

String _gigabytes(int bytes) => (bytes / 1000000000).toStringAsFixed(1);

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
          // The notice text verbatim. The licence names the sentence, so it is
          // reproduced rather than paraphrased.
          Text(model.licenseNotice, style: theme.textTheme.bodySmall),
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

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final ModelInstallProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: value?.fraction, minHeight: 4),
        const SizedBox(height: NexSpacing.sm),
        Text(
          value == null
              ? l10n.localModelDownloading
              : value.joining
              // Named separately because it is the one stage that reports no
              // byte progress and moves gigabytes — a bar that sits at 100%
              // in silence reads as a hang.
              ? l10n.localModelJoining
              : l10n.localModelDownloadingPart(
                  value.partIndex + 1,
                  value.partCount,
                ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(l10n.localModelKeepOpen, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
