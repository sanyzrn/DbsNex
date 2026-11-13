import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../platform/local_ai_support.dart';
import '../platform/local_embedder.dart';
import '../platform/display_date.dart';
import '../platform/model_install_controller.dart';
import '../platform/model_store.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';

part 'local_model/local_model_parts.dart';

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
    this.model,
    this.search = false,
    this.onSearchModelChanged,
  });

  final NexPreferences preferences;

  /// The model to show first; the one in use when null.
  final ModelRelease? model;

  /// This screen about the on-device search model rather than the chat
  /// ones: the same download, licence and storage, but no picker, and the
  /// last step proves the model *embeds* instead of loading it to chat —
  /// the chat runtime would try to talk with it, and it cannot.
  final bool search;

  /// Called when the search model starts or stops being the one in use, so
  /// whoever opened this can point the library's vectors at it.
  final VoidCallback? onSearchModelChanged;

  @override
  State<LocalModelScreen> createState() => _LocalModelScreenState();
}

class _LocalModelScreenState extends State<LocalModelScreen> {
  final _install = ModelInstallController.instance;

  NexModelStore? _store;
  LocalAiSupport? _support;
  bool _accepted = false;

  /// The model this screen is about: the one in use, or the one just
  /// picked — picking one makes it the one in use.
  late ModelRelease _model =
      widget.model ??
      (widget.search ? NexModels.search.first : NexModels.standard);

  /// Why an installed search model is not in use, in the runtime's words.
  /// Null while it works, or before it has been tried.
  String? _searchError;

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
        // "Installed" means the files arrived and verified, which is not the
        // same as the model running. Warm-up records its failure and returns
        // normally, so this used to congratulate the reader on offline chat
        // in the same breath as the screen below showed why it would not
        // start — a 2.6 GB operation ending in two contradictory answers.
        if (_install.loadError == null) {
          nexBump();
          host?.show(
            message: widget.search
                ? l10n.searchModelReady
                : l10n.localModelReady,
            haptics: widget.preferences.haptics,
          );
        } else {
          // No bump: that flourish is for something that worked. The detail
          // stays on the screen below, where there is room for the runtime's
          // own words about which of the three causes it was.
          host?.show(
            message: l10n.localModelLoadFailed,
            kind: NexBannerKind.failed,
            haptics: widget.preferences.haptics,
          );
        }
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
    var support = await LocalAi.check(_model);
    NexModelStore? store;
    if (support.supported) {
      try {
        store = await NexModelStore.open();
        // Leftovers from a failed or replaced install go before anything
        // is shown, so the sizes below are what is really on the phone.
        if (!_install.isRunning) await store.sweep();
        if (!widget.search &&
            widget.model == null &&
            store.selected.id != _model.id) {
          _model = store.selected;
          support = await LocalAi.check(_model);
        }
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
      _accepted = widget.preferences.acceptedModelLicense(_model.id);
    });
    // On the phone and not in use — an install from before this screen
    // could prove it, or one whose check failed last time. Tried again
    // here, quietly: it either starts working or says why below.
    if (widget.search &&
        store != null &&
        store.isInstalled(_model) &&
        !_install.isRunning &&
        widget.preferences.searchModelPath != store.fileFor(_model).path) {
      try {
        await _activateSearch(store);
      } catch (error) {
        if (mounted) setState(() => _searchError = '$error');
      }
    }
  }

  /// Proves the search model embeds, then makes it the one every vector
  /// comes from. Throws, and changes nothing, when it does not run.
  ///
  /// Search by meaning and related notes are switched on with it: they are
  /// what it was downloaded for, and a model that finds nothing because two
  /// switches elsewhere were off would look broken.
  Future<void> _activateSearch(NexModelStore store) async {
    final path = store.fileFor(_model).path;
    await NexLocalEmbedder.check(path);
    final prefs = widget.preferences;
    await prefs.setSearchModelPath(path);
    final capabilities = prefs.aiCapabilities;
    if (!capabilities.semanticSearch || !capabilities.relatedNotes) {
      await prefs.setAiCapabilities(
        capabilities.copyWith(semanticSearch: true, relatedNotes: true),
      );
    }
    widget.onSearchModelChanged?.call();
    if (mounted) setState(() => _searchError = null);
  }

  bool _retrying = false;

  /// Tries the installed model again: the search model's check, or the chat
  /// model's load with every backend given up on tried again. Either way
  /// the outcome is said — a banner when it works, the runtime's words
  /// below when it does not.
  Future<void> _retry(NexModelStore store) async {
    if (_install.isRunning || _retrying) return;
    if (!widget.search) {
      await _install.retryLoad(store, _model);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    setState(() => _retrying = true);
    try {
      await _activateSearch(store);
      host?.show(
        message: l10n.searchModelReady,
        haptics: widget.preferences.haptics,
      );
    } catch (error) {
      if (mounted) setState(() => _searchError = '$error');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Makes [model] the one the assistant uses, and this screen about it.
  /// The runtime follows on its next question; the old weights are released
  /// before the new ones load.
  Future<void> _pick(ModelRelease model) async {
    final store = _store;
    if (store == null || model.id == _model.id || _install.isRunning) return;
    await store.select(model);
    final support = await LocalAi.check(model);
    if (!mounted) return;
    setState(() {
      _model = model;
      _support = support;
      _accepted = widget.preferences.acceptedModelLicense(model.id);
    });
  }

  Future<void> _accept() async {
    await widget.preferences.acceptModelLicense(_model.id);
    if (!mounted) return;
    nexBump();
    setState(() => _accepted = true);
  }

  void _start() {
    final store = _store;
    if (store == null) return;
    unawaited(
      _install.start(
        store,
        _model,
        noticeTitle: AppLocalizations.of(
          context,
        ).localModelNoticeTitle(_model.name),
        warmUp: widget.search ? () => _activateSearch(store) : null,
      ),
    );
  }

  Future<void> _confirmStop() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await nexShowDialog<bool>(
      context: context,
      builder: (context) => NexAlertDialog(
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
      if (store != null) await _install.discard(store, _model);
    }
  }

  Future<void> _delete() async {
    final store = _store;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    final confirmed = await nexShowDialog<bool>(
      context: context,
      builder: (context) => NexAlertDialog(
        title: Text(l10n.localModelDeleteTitle),
        content: Text(
          widget.search
              ? l10n.searchModelDeleteBody
              : l10n.localModelDeleteBody,
        ),
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
    if (widget.search) {
      // Out of use before it is off the disk: a search that ran in between
      // would otherwise ask for a model that is no longer there.
      await widget.preferences.setSearchModelPath(null);
      widget.onSearchModelChanged?.call();
      await NexLocalEmbedder.release();
    }
    await store.delete(_model);
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
      appBar: NexAppBar(
        title: Text(
          widget.search ? l10n.searchModelTitle : l10n.localModelTitle,
        ),
      ),
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
                  widget.search
                      ? l10n.searchModelExplained
                      : l10n.localModelExplained,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: NexSpacing.sm),
                // Said before the download, not after it. This model runs on
                // the phone's own processor, and a two-gigabyte download that
                // then answers a sentence a minute — or will not load at all —
                // reads as a broken app rather than as a device that cannot
                // carry it. The blockers below refuse the cases that can be
                // detected; speed is not one of them, so it is said out loud.
                // So is quality, for the chat model: a phone-sized model set
                // beside a cloud one is judged against it, and should be
                // known to be weaker before two gigabytes are spent on it.
                if (!widget.search) ...[
                  Text(
                    l10n.localModelQualityCaveat,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                ],
                Text(
                  l10n.localModelDeviceCaveat,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                if (!widget.search &&
                    store != null &&
                    NexModels.all.length > 1) ...[
                  _ModelPicker(
                    store: store,
                    selected: _model,
                    // One download at a time, and it is for the model
                    // shown: switching mid-way would show its progress
                    // under the other model's name.
                    enabled: !_install.isRunning,
                    onPick: (model) => unawaited(_pick(model)),
                  ),
                  const SizedBox(height: NexSpacing.lg),
                ],
                if (!support.supported || store == null)
                  _Blocked(
                    blocker: support.blocker ?? LocalAiBlocker.storage,
                    model: _model,
                  )
                else if (store.isInstalled(_model)) ...[
                  _Installed(
                    bytes: store.installedBytes(_model),
                    onDelete: () => unawaited(_delete()),
                    onRetry: () => unawaited(_retry(store)),
                    loading:
                        _retrying ||
                        (_install.phase == ModelInstallPhase.loading &&
                            _install.model?.id == _model.id),
                  ),
                  // The one place the runtime's own words are shown. A model
                  // that downloaded perfectly and then would not start is the
                  // failure most likely to be mistaken for the app being
                  // broken, and the three things that cause it — wrong file,
                  // no OpenCL, not enough memory — are indistinguishable
                  // without this string.
                  if ((_install.loadError ?? _searchError)
                      case final failure?) ...[
                    const SizedBox(height: NexSpacing.lg),
                    _LoadFailure(detail: failure),
                  ],
                ] else ...[
                  _License(
                    model: _model,
                    accepted: _accepted,
                    onAccept: () => unawaited(_accept()),
                  ),
                  const SizedBox(height: NexSpacing.lg),
                  _InstallControls(
                    model: _model,
                    // A paused download of the other model is not this one's
                    // to resume; its parts wait on disk until it is picked.
                    install:
                        _install.model == null ||
                            _install.model!.id == _model.id
                        ? _install
                        : null,
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
