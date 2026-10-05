import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';

/// A local-only crash log: no network call, no third-party SDK, ever.
///
/// A ring buffer of the last few crashes in one small text file the person
/// can look at or hand over themselves — see AboutScreen's "Share
/// diagnostics" — rather than a service silently deciding a stack trace
/// belongs on someone else's server. Nothing here runs unless [install] is
/// called, and nothing it writes ever leaves the device on its own.
class NexCrashLog {
  const NexCrashLog(this.file);

  final File file;

  /// Bounds on what the file keeps, so it never grows forever.
  ///
  /// Crashes and the plain notes the app writes alongside them are kept
  /// apart. When one shared limit of twenty held both, a reminder
  /// rescheduled on every launch filled it with twenty copies of the same
  /// line and pushed every real crash out (1.93.5).
  static const maxCrashes = 100;
  static const maxNotes = 50;

  /// The whole file, in characters. Oldest notes go first, then the oldest
  /// crashes.
  static const maxChars = 256 * 1024;

  /// What one diagnostics report attached to feedback may carry: the newest
  /// entries that fit.
  static const maxShareChars = 16 * 1024;

  static const _separator = '\n\x1e\n';

  static Future<NexCrashLog> open() async {
    final dir = await getApplicationSupportDirectory();
    return NexCrashLog(File(p.join(dir.path, 'crash_log.txt')));
  }

  /// Wires both of Flutter's global error surfaces into this log.
  ///
  /// [FlutterError.onError] catches build/layout/paint errors the framework
  /// reports on its own; [PlatformDispatcher.onError] catches everything
  /// else — a throw outside a widget build, in a microtask, in a platform
  /// channel callback. Neither existed before this: an uncaught error simply
  /// vanished unless a debugger happened to be attached at the time.
  ///
  /// Chains onto whatever handler was already installed rather than
  /// replacing it, so `FlutterError.presentError`'s red screen in debug
  /// builds keeps working exactly as before.
  void install() {
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(
        details.exception,
        details.stack ?? StackTrace.current,
        context: details.context?.toString(),
      );
      previousFlutterOnError?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformOnError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      _record(error, stack);
      // Preserves whatever happened before this existed: nothing was
      // registered, so the engine's own default handling — printing to the
      // console — still runs. This only ever adds a side effect, never
      // removes one.
      return previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  /// Records something that is not a crash.
  ///
  /// The same file, because it is the file "Share diagnostics" sends: a fact
  /// that only matters when something has already gone wrong belongs where
  /// someone will actually find it. Best-effort and capped like everything
  /// else here.
  void note(String message) {
    try {
      _append('${DateTime.now().toUtc().toIso8601String()}\n$message');
    } catch (_) {
      // A log that cannot be written is not worth an exception.
    }
  }

  void _record(Object error, StackTrace stack, {String? context}) {
    // A logging failure must never become the crash it was trying to record.
    try {
      final entry = StringBuffer()
        ..writeln(DateTime.now().toUtc().toIso8601String())
        ..writeln('Nex $nexAppVersion on ${Platform.operatingSystem}')
        // Exception text can carry SQL values, note text or provider replies.
        // Published builds retain the exception type and stack only.
        ..writeln(
          kReleaseMode ? error.runtimeType.toString() : error.toString(),
        );
      if (!kReleaseMode && context != null) entry.writeln('while: $context');
      entry.write(stack);
      _append(entry.toString());
    } catch (_) {
      // Nothing to do: the log is best-effort, not the point of the app.
    }
  }

  void _append(String entry) {
    final entries = _entries()..add(entry);
    _dedupeNote(entries);
    final kept = _bounded(entries);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(kept.map(redact).join(_separator));
  }

  List<String> _entries() {
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    return existing
        .split(_separator)
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  /// A crash names the app version on its second line; anything else is a
  /// note.
  static bool isCrash(String entry) {
    final lines = entry.split('\n');
    return lines.length > 1 && lines[1].startsWith('Nex ');
  }

  static final _repeat = RegExp(r'^(\S+) · ×(\d+) since (\S+)$');

  /// A note identical to an earlier one replaces it, counted, at the end:
  /// "the same thing happened again" is one line, not one line per launch.
  static void _dedupeNote(List<String> entries) {
    final latest = entries.last;
    if (isCrash(latest)) return;
    final split = latest.indexOf('\n');
    if (split < 0) return;
    final stamp = latest.substring(0, split);
    final body = latest.substring(split + 1);
    for (var i = entries.length - 2; i >= 0; i--) {
      final old = entries[i];
      if (isCrash(old)) continue;
      final at = old.indexOf('\n');
      if (at < 0 || old.substring(at + 1) != body) continue;
      final head = old.substring(0, at);
      final match = _repeat.firstMatch(head);
      final count = match == null ? 2 : int.parse(match.group(2)!) + 1;
      final first = match == null ? head : match.group(3)!;
      entries
        ..removeAt(i)
        ..removeLast()
        ..add('$stamp · ×$count since $first\n$body');
      return;
    }
  }

  static List<String> _bounded(List<String> entries) {
    var crashes = entries.where(isCrash).length;
    var notes = entries.length - crashes;
    final kept = <String>[];
    // Oldest first: drop from the front until each kind is within its limit.
    for (final entry in entries) {
      if (isCrash(entry) ? crashes > maxCrashes : notes > maxNotes) {
        if (isCrash(entry)) {
          crashes--;
        } else {
          notes--;
        }
        continue;
      }
      kept.add(entry);
    }
    var size = kept.fold<int>(0, (n, e) => n + e.length + _separator.length);
    for (final crashPass in [false, true]) {
      for (var i = 0; i < kept.length && size > maxChars;) {
        if (isCrash(kept[i]) == crashPass) {
          size -= kept[i].length + _separator.length;
          kept.removeAt(i);
        } else {
          i++;
        }
      }
    }
    return kept;
  }

  /// The newest entries, redacted, up to [maxShareChars]: what "Attach the
  /// diagnostics report" in the feedback sheet shows and sends. Null when
  /// there is nothing to attach.
  String? shareable() {
    final entries = _entries();
    if (entries.isEmpty) return null;
    final picked = <String>[];
    var size = 0;
    for (final entry in entries.reversed) {
      final clean = redact(entry);
      if (size + clean.length > maxShareChars) break;
      picked.insert(0, clean);
      size += clean.length + 2;
    }
    if (picked.isEmpty) {
      final newest = redact(entries.last);
      return newest.substring(newest.length - maxShareChars);
    }
    return picked.join('\n\n');
  }

  static String redact(String text) => text
      .replaceAll(RegExp(r'https?://[^\s<>]+', caseSensitive: false), '[url]')
      .replaceAll(
        RegExp(r'(?:Bearer\s+|\bsk-)[A-Za-z0-9_.\-]+', caseSensitive: false),
        '[credential]',
      )
      .replaceAllMapped(
        RegExp(
          r'(api[_-]?key|token|authorization|password)\s*[:=]\s*[^\s,;]+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}=[redacted]',
      );
}
