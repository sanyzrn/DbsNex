import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';

/// What Nex measures about itself, when the person has asked it to (W3.4).
///
/// Nex's promises are about speed — a capture in under three seconds, a note
/// found instantly — and until this nothing measured them on a real phone.
/// These are the numbers that say whether the promises hold, kept the way
/// everything else about the person is kept:
///
/// - **off until switched on**, in Settings → About → Speed and reliability;
/// - **on the phone only**, in one small file beside the crash log, never
///   sent anywhere, never in a backup;
/// - **attached to feedback only when the person ticks the box**, as plain
///   text they can read first;
/// - **about the app, never the content**: durations and counts, no note
///   text, no search words, no ids. Switching it off deletes the file.
enum NexMetric {
  /// A cold start, from Nex's code starting to the library being open.
  launch,

  /// A cold start, from Nex's code starting to the timeline showing notes.
  /// Includes the opening animation, which has a floor of its own.
  timeline,

  /// From opening capture to the note being saved — the three-second promise.
  capture,

  /// From starting a search to opening a note it found.
  searchToOpen,
}

/// The middle and the slow end of one metric's recent samples.
class NexMetricStats {
  const NexMetricStats({
    required this.count,
    required this.median,
    required this.p90,
  });

  final int count;
  final Duration median;
  final Duration p90;
}

/// Sessions (app launches) in which something was captured, and how many of
/// those ran without an error Nex caught.
///
/// Only errors that reach Dart are seen: a launch the system killed outright
/// cannot report itself, so this is an upper bound on how clean capture is.
class NexSessionStats {
  const NexSessionStats({required this.withCapture, required this.clean});

  final int withCapture;
  final int clean;
}

class NexMetrics {
  NexMetrics(this.file, {this.enabled = false, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// A store that is off and has nowhere to write: what everything sees until
  /// bootstrap opens the real one, and what tests see unless they set one.
  NexMetrics.off() : this(null);

  final File? file;
  final DateTime Function() _now;

  /// Whether anything is recorded. Changing it does not delete anything;
  /// [setEnabled] is what the switch calls.
  bool enabled;

  static NexMetrics shared = NexMetrics.off();

  /// Recent samples kept per metric, and recent sessions kept.
  static const keep = 100;

  final Map<NexMetric, List<({DateTime at, int ms})>> _samples = {
    for (final metric in NexMetric.values) metric: [],
  };
  final List<({DateTime at, bool captured, bool errored})> _sessions = [];
  bool _sessionOpen = false;
  Timer? _writeSoon;

  /// Started when Nex's Dart code starts, so a cold start can be timed.
  /// Null in tests and anywhere [markLaunched] was not called.
  static Stopwatch? _launch;
  static bool _timelineRecorded = false;

  static void markLaunched() => _launch ??= Stopwatch()..start();

  static Future<NexMetrics> open({required bool enabled}) async {
    final dir = await getApplicationSupportDirectory();
    final metrics = NexMetrics(
      File(p.join(dir.path, 'metrics.json')),
      enabled: enabled,
    );
    if (enabled) metrics._read();
    return metrics;
  }

  /// Switches measuring on or off. Off deletes what was kept: a person who
  /// turns this off has said they do not want it, not that they want it
  /// paused.
  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (value) {
      _read();
      beginSession();
    } else {
      _writeSoon?.cancel();
      for (final list in _samples.values) {
        list.clear();
      }
      _sessions.clear();
      _sessionOpen = false;
      final f = file;
      if (f != null && f.existsSync()) await f.delete();
    }
  }

  void record(NexMetric metric, Duration took) {
    if (!enabled || took.isNegative) return;
    final list = _samples[metric]!..add((at: _now(), ms: took.inMilliseconds));
    if (list.length > keep) list.removeRange(0, list.length - keep);
    _scheduleWrite();
  }

  /// The library is open; records [NexMetric.launch] once per cold start.
  void recordLaunchReady() {
    final watch = _launch;
    if (watch == null) return;
    record(NexMetric.launch, watch.elapsed);
  }

  /// The timeline has drawn notes; records [NexMetric.timeline] once per cold
  /// start, and only for the first time it happens.
  void recordTimelineShown() {
    final watch = _launch;
    if (watch == null || _timelineRecorded) return;
    _timelineRecorded = true;
    record(NexMetric.timeline, watch.elapsed);
    watch.stop();
  }

  /// This launch opens behind the app lock: the timeline appears only after
  /// the person unlocks, and how long that took is theirs, not Nex's.
  void skipTimeline() => _timelineRecorded = true;

  /// A launch that counts as a session. Called once the library is open.
  void beginSession() {
    if (!enabled || _sessionOpen) return;
    _sessionOpen = true;
    _sessions.add((at: _now(), captured: false, errored: false));
    if (_sessions.length > keep) {
      _sessions.removeRange(0, _sessions.length - keep);
    }
    _scheduleWrite();
  }

  void markCapture() => _markSession(captured: true);

  /// An error reached one of Flutter's global handlers. Written at once,
  /// because the process may not live to write it later.
  void markError() => _markSession(errored: true, now: true);

  void _markSession({bool? captured, bool? errored, bool now = false}) {
    if (!enabled || !_sessionOpen || _sessions.isEmpty) return;
    final last = _sessions.last;
    final next = (
      at: last.at,
      captured: captured ?? last.captured,
      errored: errored ?? last.errored,
    );
    if (next == last) return;
    _sessions[_sessions.length - 1] = next;
    now ? _writeNow() : _scheduleWrite();
  }

  /// Chains onto Flutter's two global error surfaces, after the crash log,
  /// so an error also marks this session as not clean.
  void installErrorHook() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      markError();
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousPlatform = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      markError();
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  NexMetricStats? stats(NexMetric metric) {
    final values = [for (final s in _samples[metric]!) s.ms]..sort();
    if (values.isEmpty) return null;
    int at(double q) =>
        values[math.min(values.length - 1, (values.length * q).floor())];
    return NexMetricStats(
      count: values.length,
      median: Duration(milliseconds: at(.5)),
      p90: Duration(milliseconds: at(.9)),
    );
  }

  NexSessionStats get sessions {
    final captured = _sessions.where((s) => s.captured).toList();
    return NexSessionStats(
      withCapture: captured.length,
      clean: captured.where((s) => !s.errored).length,
    );
  }

  bool get isEmpty =>
      _samples.values.every((l) => l.isEmpty) && sessions.withCapture == 0;

  /// The plain text a person can attach to feedback — read on screen before
  /// it is sent, and nothing in it they have not seen.
  String report({String platform = ''}) {
    String line(String label, NexMetric metric) {
      final s = stats(metric);
      if (s == null) return '$label: no data';
      return '$label: median ${formatDuration(s.median)}, '
          'slowest 10% ${formatDuration(s.p90)} (${s.count})';
    }

    final sessionStats = sessions;
    return [
      'Nex measurements (on this device, attached by choice)',
      'Nex $nexAppVersion${platform.isEmpty ? '' : ' on $platform'}',
      line('Cold start to library open', NexMetric.launch),
      line('Cold start to timeline', NexMetric.timeline),
      line('Capture, open to saved', NexMetric.capture),
      line('Search to opening a note', NexMetric.searchToOpen),
      'Sessions with a capture: ${sessionStats.withCapture}, '
          'without an error: ${sessionStats.clean}',
    ].join('\n');
  }

  static String formatDuration(Duration d) => d.inMilliseconds < 1000
      ? '${d.inMilliseconds} ms'
      : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

  void _scheduleWrite() {
    _writeSoon?.cancel();
    _writeSoon = Timer(const Duration(seconds: 2), _writeNow);
  }

  /// Writes what is kept now. Tests call it rather than waiting on a timer.
  @visibleForTesting
  void flush() => _writeNow();

  void _writeNow() {
    _writeSoon?.cancel();
    final f = file;
    if (f == null || !enabled) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'samples': {
            for (final e in _samples.entries)
              e.key.name: [
                for (final s in e.value) [s.at.millisecondsSinceEpoch, s.ms],
              ],
          },
          'sessions': [
            for (final s in _sessions)
              [s.at.millisecondsSinceEpoch, s.captured, s.errored],
          ],
        }),
      );
    } catch (_) {
      // A measurement that cannot be written is not worth an error of its
      // own — least of all one that would mark this session as not clean.
    }
  }

  void _read() {
    final f = file;
    if (f == null || !f.existsSync()) return;
    try {
      final value = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final samples = value['samples'] as Map<String, dynamic>;
      for (final metric in NexMetric.values) {
        final list = _samples[metric]!..clear();
        for (final raw in (samples[metric.name] as List?) ?? const []) {
          final pair = raw as List;
          list.add((
            at: DateTime.fromMillisecondsSinceEpoch(pair[0] as int),
            ms: pair[1] as int,
          ));
        }
      }
      _sessions
        ..clear()
        ..addAll([
          for (final raw in value['sessions'] as List)
            (
              at: DateTime.fromMillisecondsSinceEpoch((raw as List)[0] as int),
              captured: raw[1] as bool,
              errored: raw[2] as bool,
            ),
        ]);
    } catch (_) {
      // A file this version cannot read is started over, not trusted.
      for (final list in _samples.values) {
        list.clear();
      }
      _sessions.clear();
    }
  }
}
