import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

import 'app_update.dart';
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
/// wider. There is exactly one model and one install of it; a registry keyed by
/// model id would be scaffolding for a second model that does not exist.
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
  Future<void> start(NexModelStore store, ModelRelease model) async {
    if (isRunning) return;
    _stopRequested = false;
    _discardOnStop = false;
    _error = null;
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
          notifyListeners();
        },
      );
      await _warmUp();
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
    }
  }

  /// Brings the runtime up while the user is still looking at the screen that
  /// finished the download, rather than making the first question pay for it.
  ///
  /// Best-effort: a runtime that cannot load here will fail the same way on
  /// the first message, where there is already a place to say so. The install
  /// itself succeeded either way — the file is on disk and verified.
  Future<void> _warmUp() async {
    final pending = ChatAdapterBinding.instance.warmUp();
    if (pending == null) return;
    _set(ModelInstallPhase.loading);
    try {
      await pending;
    } catch (_) {}
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

  /// Installs from a file the user picked instead of downloading one.
  ///
  /// Goes through the same phases as a download so the screen has one thing to
  /// render: verifying two gigabytes off local storage is not instant, and a
  /// button that appears to do nothing for a minute is the same bug as a
  /// download with no bar.
  Future<void> installFrom(
    NexModelStore store,
    ModelRelease model,
    File source,
  ) async {
    if (isRunning) return;
    _error = null;
    _set(ModelInstallPhase.joining);
    try {
      await store.installFromFile(
        model,
        source,
        onProgress: (progress) {
          _progress = progress;
          notifyListeners();
        },
      );
      await _warmUp();
      _set(ModelInstallPhase.installed);
    } catch (error) {
      _error = error;
      _set(ModelInstallPhase.failed);
    }
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
