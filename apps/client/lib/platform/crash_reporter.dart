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

  /// Bounds the file to a handful of the most recent crashes rather than
  /// growing forever — a device someone never restarts should not carry
  /// years of stack traces for a problem long since fixed.
  static const _maxEntries = 20;
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

  void _record(Object error, StackTrace stack, {String? context}) {
    // A logging failure must never become the crash it was trying to record.
    try {
      final entry = StringBuffer()
        ..writeln(DateTime.now().toUtc().toIso8601String())
        ..writeln('Nex $nexAppVersion on ${Platform.operatingSystem}')
        ..writeln(error.toString());
      if (context != null) entry.writeln('while: $context');
      entry.write(stack);
      _append(entry.toString());
    } catch (_) {
      // Nothing to do: the log is best-effort, not the point of the app.
    }
  }

  void _append(String entry) {
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final entries =
        existing.split(_separator).where((e) => e.trim().isNotEmpty).toList()
          ..add(entry);
    final kept = entries.length > _maxEntries
        ? entries.sublist(entries.length - _maxEntries)
        : entries;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(kept.join(_separator));
  }
}
