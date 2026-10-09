import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

import 'app_update.dart';
import 'download_notice.dart';
import 'model_store.dart';

/// Where an install has got to.
enum ModelInstallPhase {
  /// Nothing running. Either never started, stopped, or already installed.
  idle,

  downloading,

  /// Stopped by the user, with the bytes so far kept on disk.
  paused,

  /// Concatenating and checking the parts.
  joining,

  /// The file is in place and the runtime is bringing it up. Its own phase
  /// because it takes real time — gigabytes off disk and onto the GPU — and
  /// reports no progress of its own, so without this the app looks hung at
  /// exactly the moment someone first tries to use what they downloaded.
  loading,

  installed,

  failed,
}

/// One install, owned by the app rather than by a screen.
///
/// This exists because the install used to live in `LocalModelScreen`'s State:
/// leaving the screen — a back gesture, a tap on a note — disposed the widget
/// and took a two-gigabyte download with it, with no warning and nothing to
/// resume from but a `.part` file nobody mentioned. A download that expensive
/// has to be the app's business, not a screen's, and has to stop only when the
/// user says so.
///
/// Deliberately a plain [ChangeNotifier] singleton rather than anything
/// wider. There is one install at a time, of the model in [model]; the screen
/// does not let another be picked while it runs.
class ModelInstallController extends ChangeNotifier {
  ModelInstallController._();

  static final ModelInstallController instance = ModelInstallController._();

  ModelInstallPhase _phase = ModelInstallPhase.idle;
  ModelInstallProgress? _progress;
  Object? _error;

  /// Set while a download is running and cleared when it stops. Read once per
  /// chunk by the downloader, which is what makes pausing responsive without
  /// anything having to cancel an HTTP request from outside.
  bool _stopRequested = false;

  /// True when the parts should be thrown away rather than kept for a resume.
  bool _discardOnStop = false;

  ModelInstallPhase get phase => _phase;

  /// The model the current or last install was for.
  ModelRelease? get model => _model;
  ModelRelease? _model;
  ModelInstallProgress? get progress => _progress;
  Object? get error => _error;

  bool get isRunning =>
      _phase == ModelInstallPhase.downloading ||
      _phase == ModelInstallPhase.joining ||
      _phase == ModelInstallPhase.loading;

  /// Whether there are downloaded bytes worth resuming from.
  bool get canResume => _phase == ModelInstallPhase.paused;

  void _set(ModelInstallPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// Starts, or picks up where a pause left off — the same call, because to
  /// the downloader they are the same thing: ask for the file, send a Range
  /// header for whatever is already here.
  Future<void> start(
    NexModelStore store,
    ModelRelease model, {
    String? noticeTitle,

    /// What proves the model runs once it is on the phone. The chat
    /// runtime's warm-up when null; the search model passes its own, since
    /// the chat runtime would try to load it as a model that talks.
    Future<void> Function()? warmUp,
  }) async {
    if (isRunning) return;
    _model = model;
    _noticeTitle = noticeTitle;
    _noticePercent = -1;
    _stopRequested = false;
    _discardOnStop = false;
    _error = null;
    _loadError = null;
    _set(ModelInstallPhase.downloading);
    try {
      await store.install(
        model,
        isCancelled: () => _stopRequested,
        onProgress: (progress) {
          _progress = progress;
          if (progress.joining && _phase == ModelInstallPhase.downloading) {
            _phase = ModelInstallPhase.joining;
          }
          _notice(progress.fraction);
          notifyListeners();
        },
      );
      await _warmUp(warmUp);
      // Anything the install left beside the model, gone now it is in place.
      await store.sweep();
      _set(ModelInstallPhase.installed);
    } on DownloadPaused {
      // Asked for, not broken. The parts stay unless stop() was what asked.
      if (_discardOnStop) {
        await store.delete(model);
        _progress = null;
        _set(ModelInstallPhase.idle);
      } else {
        _set(ModelInstallPhase.paused);
      }
    } catch (error) {
      _error = error;
      _set(ModelInstallPhase.failed);
    } finally {
      _stopRequested = false;
      // Down in every outcome: done, paused, stopped or failed. A progress
      // bar left in the shade for a download that is not running is the
      // one thing worse than none.
      _noticePercent = -1;
      unawaited(NexDownloadNotice.hide());
    }
  }

  String? _noticeTitle;
  int _noticePercent = -1;

  /// The download's place in the notification shade — and, being a
  /// foreground service on Android, what keeps it running once Nex is left
  /// for another app. The same service the app update uses. Rewritten only
  /// when the whole percentage moves, not on every chunk.
  void _notice(double? fraction) {
    final title = _noticeTitle;
    if (title == null) return;
    final percent = ((fraction ?? 0) * 100).floor().clamp(0, 100);
    if (percent == _noticePercent) return;
    _noticePercent = percent;
    unawaited(NexDownloadNotice.show(title: title, percent: percent));
  }

  /// Brings the runtime up while the user is still looking at the screen that
  /// finished the download, rather than making the first question pay for it.
  ///
  /// Best-effort: a runtime that cannot load here will fail the same way on
  /// the first message, where there is already a place to say so. The install
  /// itself succeeded either way — the file is on disk and verified.
  Future<void> _warmUp(Future<void> Function()? own) async {
    final pending = own != null ? own() : ChatAdapterBinding.instance.warmUp();
    if (pending == null) return;
    _set(ModelInstallPhase.loading);
    try {
      await pending;
      _loadError = null;
    } catch (error) {
      // Kept and shown, not swallowed. This used to be an empty catch on the
      // reasoning that the first message would surface it anyway — but what
      // the first message surfaces is "no answer came back", which is the same
      // sentence for a wrong file, a device with no OpenCL, and a model too
      // large for the memory it was given. Those three want different actions,
      // and the runtime says which in this string.
      _loadError = '$error';
    }
  }

  /// Why the model would not load, verbatim, or null when it did.
  ///
  /// Deliberately not translated. It is the runtime's own words about a
  /// failure that is rare, technical, and only actionable by someone who can
  /// read it — a localised paraphrase would lose the one detail that matters.
  String? _loadError;
  String? get loadError => _loadError;

  /// Loads an installed model again, from a clean slate: every backend that
  /// was given up on is tried again. What "try again" on the model screen
  /// does when the model is on the phone and will not start.
  Future<void> retryLoad(NexModelStore store, ModelRelease model) async {
    if (isRunning) return;
    _model = model;
    _error = null;
    _loadError = null;
    await store.forgetFailedLoads(model);
    await _warmUp(null);
    _set(ModelInstallPhase.installed);
  }

  /// Stops and keeps what has arrived.
  void pause() {
    if (_phase != ModelInstallPhase.downloading) return;
    _discardOnStop = false;
    _stopRequested = true;
  }

  /// Stops and throws away what has arrived.
  ///
  /// Separate from [pause] because they differ in what they cost to undo:
  /// resuming after a pause is free, and starting again after a stop is the
  /// whole download. Offering one button for both would make that difference
  /// invisible at the moment it matters.
  void stop() {
    if (_phase != ModelInstallPhase.downloading) return;
    _discardOnStop = true;
    _stopRequested = true;
  }

  /// Throws away a paused or failed install.
  ///
  /// [stop] covers the running case by asking the download to end; this is the
  /// same intent once it already has.
  Future<void> discard(NexModelStore store, ModelRelease model) async {
    if (isRunning) return;
    await store.delete(model);
    _progress = null;
    _error = null;
    _set(ModelInstallPhase.idle);
  }

  /// Forgets a finished or failed run so the screen can offer to start again.
  void reset() {
    if (isRunning) return;
    _progress = null;
    _error = null;
    _set(ModelInstallPhase.idle);
  }
}
