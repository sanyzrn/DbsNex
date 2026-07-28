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
  Future<void>? _prefetching;

  /// The background download, while it is running.
  ///
  /// Awaiting it is how the update sheet joins a fetch that is already in
  /// flight instead of starting a second one.
  Future<void>? get prefetching => _prefetching;

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
    notifyListeners();
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
      notifyListeners();
    }
  }

  /// Fetches the installer in the background, ignoring failure.
  ///
  /// A download that does not finish is not worth reporting: the user did not
  /// ask for it yet, and the sheet will simply download it when they do.
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
        // Already fetched on an earlier run — no reason to fetch it twice.
        _downloaded = existing;
        notifyListeners();
        return;
      }
      _downloaded = await _downloader.download(
        url: url,
        into: dir,
        filename: name,
      );
      notifyListeners();
    } catch (_) {
      _downloaded = null;
    }
  }

  /// Called by the update sheet once the user has installed, so the dot clears.
  void acknowledge() {
    _found = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _checker.close();
    _downloader.close();
    super.dispose();
  }
}
