import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'notification_text.dart';

abstract final class NexDailyNudgeNative {
  static const channel = MethodChannel('nex/daily_nudge');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> configure(Map<String, Object?> plan) {
    List<String> formatted(Object? bodies) => [
      for (final text in bodies! as List)
        nexAndroidNotificationText(text as String),
    ];
    final days = plan['days']! as Map<String, Object?>;
    return channel.invokeMethod<void>(
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
  }

  static Future<void> cancel() async {
    if (supported) await channel.invokeMethod<void>('cancel');
  }
}
