import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

import 'notification_text.dart';

abstract final class NexDailyNudgeNative {
  static const channel = MethodChannel('nex/daily_nudge');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// What the caller is told when the plan was stored but no alarm was taken.
  ///
  /// The same sentence a note reminder uses when the queue does not hold its
  /// alarm (`NexReminders._verify`), because it is the same failure: the OS
  /// accepted a request and kept nothing.
  static const notArmed = 'the system did not keep the daily alarm';

  /// Hands the plan over and answers whether an alarm was actually taken.
  ///
  /// The native side can refuse both `setExactAndAllowWhileIdle` and
  /// `setAndAllowWhileIdle` — a phone with the exact-alarm permission revoked
  /// and a ROM that rejects the inexact path as well. Returning `false` is
  /// what turns that into a sentence in settings instead of a switch that
  /// claims something the phone will never do.
  static Future<bool> configure(Map<String, Object?> plan) async {
    List<String> formatted(Object? bodies) => [
      for (final text in bodies! as List)
        nexAndroidNotificationText(text as String),
    ];
    final days = plan['days']! as Map<String, Object?>;
    final armed = await channel.invokeMethod<bool>(
      'configure',
      jsonEncode({
        ...plan,
        'title': nexAndroidNotificationText(plan['title']! as String),
        'fallback': formatted(plan['fallback']),
        'days': {
          for (final entry in days.entries)
            entry.key: {
              ...entry.value! as Map,
              'bodies': formatted((entry.value! as Map)['bodies']),
              'localBodies': formatted((entry.value! as Map)['localBodies']),
            },
        },
      }),
    );
    return armed ?? false;
  }

  /// The last alarm or delivery failure the receiver recorded, if any.
  ///
  /// Read once per rebuild into the shared diagnostics log. A failure that
  /// happened while the app was closed has no other way to reach a person:
  /// the boot broadcast cannot show a banner.
  static Future<String?> lastError() async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<String>('status');
    } catch (_) {
      // A diagnostic read never fails the thing it is diagnosing.
      return null;
    }
  }

  static Future<void> cancel() async {
    if (supported) await channel.invokeMethod<void>('cancel');
  }
}
