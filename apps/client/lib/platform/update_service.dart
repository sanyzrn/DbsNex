import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import 'app_update.dart';
import 'nex_preferences.dart';

/// Knows whether a newer release exists, and holds it ready.
///
/// Checking is quiet by design: no notification, no dialog, no interruption —
/// only a dot on the settings icon, which is the one place a person goes
/// looking for this. That keeps the automatic check inside the promise the
/// product makes about never demanding attention.
///
/// The download runs as soon as an update is found, so tapping Install is
/// instant rather than the start of a wait.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.preferences,
    UpdateChecker? checker,
    UpdateDownloader? downloader,
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  })  : _checker = checker ?? UpdateChecker(currentVersion: nexAppVersion),
        _downloader = downloader ?? UpdateDownloader(),
        _directory = directory ?? getTemporaryDirectory,
        _now = now ?? DateTime.now;

  /// How stale a check may get before the app looks again.
  ///
  /// Once a day, and only while the app is open. A release is not urgent
  /// enough to justify a background job, and a shorter interval would mean
  /// pinging GitHub every time the app came back to the foreground.
  static const checkInterval = Duration(hours: 24);

  final NexPreferences preferences;
  final UpdateChecker _checker;
  final UpdateDownloader _downloader;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  UpdateCheck? _found;
  File? _downloaded;
  bool _busy = false;
  bool _disposed = false;

  /// Notifies unless this service is gone.
  ///
  /// The download now outlives the screen that started it, and on app teardown
  /// it can outlive the service too — a transfer in flight finishes into a
  /// disposed ChangeNotifier, which throws. Nothing is listening by then, so
  /// the right answer is to fall silent rather than to cancel the fetch.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void>? _prefetching;
  double? _progress;
  bool _announced = true;

  /// The background download, while it is running.
  ///
  /// Awaiting it is how the update sheet joins a fetch that is already in
  /// flight instead of starting a second one.
  Future<void>? get prefetching => _prefetching;

  /// How far along the download is, or null for a download with no known size.
  double? get downloadProgress => _progress;

  bool get isDownloading => _prefetching != null;

  /// Whether a download finished that nobody has been told about yet.
  ///
  /// The app watches this so it can raise a toast when the installer lands
  /// while the user is somewhere else entirely — which is now the normal case,
  /// because leaving the update screen no longer cancels the fetch.
  bool get hasUnannouncedDownload => !_announced && _downloaded != null;

  /// Marks the finished download as reported, so the toast shows once.
  void markAnnounced() {
    if (_announced) return;
    _announced = true;
    _notify();
  }

  /// Starts the download, or hands back the one already running.
  ///
  /// This is the whole of the fix for a download that died on a back gesture:
  /// the transfer belongs to the service, which lives as long as the app, and
  /// not to a screen, which does not. The screen only watches.
  Future<void> ensureDownloaded() {
    final running = _prefetching;
    if (running != null) return running;
    if (_downloaded != null) return Future<void>.value();
    final update = available;
    if (update == null) return Future<void>.value();
    final started = _prefetch(update);
    _prefetching = started;
    return started;
  }

  /// The last completed check, whatever it said — including a failure.
  ///
  /// [available] deliberately hides everything but a real update; this is for
  /// the sheet, which has to tell "you are current" apart from "we could not
  /// reach GitHub".
  UpdateCheck? get last => _found;

  /// The update waiting to be installed, if any.
  UpdateCheck? get available =>
      _found?.status == UpdateStatus.available ? _found : null;

  /// The installer already on disk, ready to hand to the system.
  File? get downloaded => _downloaded;

  bool get isChecking => _busy;

  /// What the settings icon's dot is for: something is genuinely waiting.
  bool get hasUpdate => available != null;

  /// Runs a check if one is due, or if [force] is set.
  ///
  /// Returns without touching the network when the last check is recent, so
  /// this is safe to call on every launch and every resume.
  Future<void> maybeCheck({bool force = false}) async {
    if (_busy) return;
    if (!force) {
      if (!preferences.autoUpdateCheck) return;
      final last = preferences.lastUpdateCheck;
      if (last != null && _now().difference(last) < checkInterval) return;
    }
    await check();
  }

  Future<UpdateCheck> check() async {
    _busy = true;
    _notify();
    try {
      final result = await _checker.check();
      _found = result;
      // Only a completed check counts as "checked": recording the time after a
      // failure would suppress the next 24 hours of attempts over one flaky
      // moment on a train.
      if (result.status != UpdateStatus.unavailable) {
        await preferences.setLastUpdateCheck(_now());
      }
      if (result.status == UpdateStatus.available) {
        _prefetching = _prefetch(result);
        unawaited(_prefetching);
      }
      return result;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Fetches the installer in the background, ignoring failure.
  ///
  /// A download that does not finish is not worth interrupting anyone over:
  /// the sheet will simply offer it again when they next look.
  Future<void> _prefetch(UpdateCheck update) async {
    final url = update.downloadUrl;
    final version = update.version;
    if (url == null || version == null) return;
    final name = 'Nex-$version${Platform.isWindows ? '.exe' : '.apk'}';
    try {
      final dir = await _directory();
      final existing = File('${dir.path}${Platform.pathSeparator}$name');
      if (existing.existsSync() &&
          (update.sizeBytes == null ||
              existing.lengthSync() == update.sizeBytes)) {
        // Already fetched on an earlier run — no reason to fetch it twice, and
        // no reason to announce something that was there before this launch.
        _downloaded = existing;
        _notify();
        return;
      }
      _announced = false;
      _downloaded = await _downloader.download(
        url: url,
        into: dir,
        filename: name,
        onProgress: (value) {
          _progress = value;
          _notify();
        },
      );
      _notify();
    } catch (_) {
      _downloaded = null;
      _announced = true;
    } finally {
      _prefetching = null;
      _progress = null;
      _notify();
    }
  }

  /// Called by the update sheet once the user has installed, so the dot clears.
  void acknowledge() {
    _found = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _checker.close();
    _downloader.close();
    super.dispose();
  }
}
