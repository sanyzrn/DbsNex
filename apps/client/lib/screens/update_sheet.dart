import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/app_update.dart';
import '../platform/update_service.dart';

/// Check, download, install — the whole update flow in one sheet.
///
/// The install step is a handoff, not something the app does itself: outside
/// an app store Android will not let a process replace its own package
/// silently. Nex downloads the APK and opens it, and the system installer asks
/// the user to confirm. That prompt is the platform's, and it is not
/// skippable — the app can only get the user to it.
///
/// When the app-wide [UpdateService] has already found and fetched a release,
/// this sheet opens straight on Install: the waiting happened quietly in the
/// background, which is the entire point of the dot on the settings icon.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, this.haptics = true, this.service});

  final bool haptics;

  /// The shared service, when there is one. Its result and its pre-downloaded
  /// installer are reused rather than repeated; without it the sheet still
  /// works on its own, which is what the tests and the desktop path use.
  final UpdateService? service;

  static Future<void> show(
    BuildContext context, {
    bool haptics = true,
    UpdateService? service,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => UpdateSheet(haptics: haptics, service: service),
      );

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

enum _Phase { checking, upToDate, available, downloading, ready, failed }

class _UpdateSheetState extends State<UpdateSheet> {
  // Only built when the sheet has to do the work itself. With a service in
  // hand, opening a second HTTP client to ask the same question would be waste.
  late final UpdateChecker? _checker =
      widget.service == null ? UpdateChecker(currentVersion: nexAppVersion) : null;
  late final _downloader = UpdateDownloader();

  _Phase _phase = _Phase.checking;
  UpdateCheck? _result;
  double? _progress;
  File? _downloaded;
  String? _error;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    final ready = service?.available;
    if (ready != null) {
      // Already found, and usually already on disk: open on the last step.
      _result = ready;
      _downloaded = service!.downloaded;
      _phase = _downloaded != null ? _Phase.ready : _Phase.available;
      return;
    }
    _check();
  }

  @override
  void dispose() {
    _checker?.close();
    _downloader.close();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    final service = widget.service;
    final UpdateCheck result;
    if (service != null) {
      // A tap on this row is an explicit ask, so it bypasses the daily
      // interval — but it still runs through the service, so the dot and the
      // pre-download stay in step with what the sheet shows.
      await service.maybeCheck(force: true);
      result = service.last ?? const UpdateCheck.unavailable();
    } else {
      result = await _checker!.check();
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _downloaded = service?.downloaded;
      _phase = switch (result.status) {
        UpdateStatus.available => _Phase.available,
        UpdateStatus.upToDate => _Phase.upToDate,
        UpdateStatus.unavailable => _Phase.failed,
      };
    });
    if (widget.haptics && result.status == UpdateStatus.available) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _download() async {
    final result = _result;
    final url = result?.downloadUrl;
    final version = result?.version;
    if (url == null || version == null) return;

    // The background fetch may already be done, or still running. Either way
    // there is no reason to pull the same bytes down a second time.
    final service = widget.service;
    if (service != null) {
      setState(() {
        _phase = _Phase.downloading;
        _progress = null;
        _error = null;
      });
      await service.prefetching;
      final prefetched = service.downloaded;
      if (!mounted) return;
      if (prefetched != null) {
        setState(() {
          _downloaded = prefetched;
          _phase = _Phase.ready;
        });
        if (widget.haptics) HapticFeedback.mediumImpact();
        await _install();
        return;
      }
    }

    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      // The cache directory, because open_filex's FileProvider already grants
      // the installer a content URI there and the OS can reclaim it later.
      final dir = await getTemporaryDirectory();
      final file = await _downloader.download(
        url: url,
        into: dir,
        filename: 'Nex-$version${Platform.isWindows ? '.exe' : '.apk'}',
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloaded = file;
        _phase = _Phase.ready;
      });
      if (widget.haptics) HapticFeedback.mediumImpact();
      await _install();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$error';
      });
    }
  }

  Future<void> _install() async {
    final file = _downloaded;
    if (file == null) return;
    final l10n = AppLocalizations.of(context);
    final result = await OpenFilex.open(
      file.path,
      type: Platform.isAndroid ? 'application/vnd.android.package-archive' : null,
    );
    if (result.type == ResultType.done) {
      // The system installer has it now. Clearing the dot here is a small lie
      // if the user backs out of that prompt, but the next daily check puts it
      // straight back — and a dot that survives a successful install is worse.
      widget.service?.acknowledge();
    }
    if (!mounted || result.type == ResultType.done) return;
    setState(() {
      _phase = _Phase.failed;
      // The most common cause on Android is the "install unknown apps"
      // permission still being off for Nex, which the system prompt handles —
      // but if the handoff never happened, say so rather than looking stuck.
      _error = l10n.installBlocked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.lg,
        right: NexSpacing.lg,
        top: NexSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.checkForUpdate, style: theme.textTheme.titleLarge),
          const SizedBox(height: NexSpacing.xs),
          Text(
            l10n.installedVersion(nexAppVersion),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.lg),
          ..._body(l10n, theme),
        ],
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n, ThemeData theme) => switch (_phase) {
        _Phase.checking => [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.checkingForUpdate, textAlign: TextAlign.center),
          ],
        _Phase.upToDate => [
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.upToDate, textAlign: TextAlign.center),
          ],
        _Phase.available => [
            Text(
              l10n.updateAvailable('${_result!.version}'),
              style: theme.textTheme.titleMedium,
            ),
            if (_result!.sizeBytes != null) ...[
              const SizedBox(height: NexSpacing.xs),
              Text(
                nexFormatBytes(_result!.sizeBytes!),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_result!.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: NexSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    _result!.notes!.trim(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            const SizedBox(height: NexSpacing.lg),
            FilledButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.downloadAndInstall),
            ),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.updateInstallNotice, style: theme.textTheme.bodySmall),
          ],
        _Phase.downloading => [
            Text(l10n.downloading, style: theme.textTheme.titleMedium),
            const SizedBox(height: NexSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _progress, minHeight: 8),
            ),
            const SizedBox(height: NexSpacing.sm),
            Text(
              _progress == null
                  ? ''
                  : '${(_progress! * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        _Phase.ready => [
            Text(l10n.readyToInstall, style: theme.textTheme.titleMedium),
            const SizedBox(height: NexSpacing.lg),
            FilledButton.icon(
              onPressed: _install,
              icon: const Icon(Icons.install_mobile_outlined),
              label: Text(l10n.install),
            ),
          ],
        _Phase.failed => [
            Icon(Icons.cloud_off_outlined, size: 40, color: theme.colorScheme.secondary),
            const SizedBox(height: NexSpacing.sm),
            Text(_error ?? l10n.updateCheckFailed, textAlign: TextAlign.center),
            const SizedBox(height: NexSpacing.lg),
            OutlinedButton(onPressed: _check, child: Text(l10n.tryAgain)),
          ],
      };
}
