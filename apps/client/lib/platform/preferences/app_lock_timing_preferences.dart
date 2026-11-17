part of '../nex_preferences.dart';

/// When the app lock puts itself back on.
///
/// The lock used to re-arm the instant the app left the screen, which is the
/// safe default and, for someone switching to a browser to copy a link and
/// coming straight back, five fingerprints a minute. These are the three
/// answers that actually differ: at once, after a while, or never on its own.
enum AppLockTiming { immediately, after, manual }

extension AppLockTimingWire on AppLockTiming {
  String get wireName => name;

  static AppLockTiming fromWire(String? value) =>
      AppLockTiming.values.firstWhere(
        (timing) => timing.name == value,
        // The behaviour that shipped, for a device that has never seen this
        // setting: a lock nobody configured should be the strict one.
        orElse: () => AppLockTiming.immediately,
      );
}
