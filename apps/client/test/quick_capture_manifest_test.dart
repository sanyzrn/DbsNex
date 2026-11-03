import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Quick Settings tile and the quick-capture notification live in the
/// Android project, where nothing in this suite runs them. What can be held
/// here is the wiring Android reads before any of that code runs.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('quick capture and widget PendingIntent identities do not collide', () {
    String source(String name) => File(
      'android/app/src/main/kotlin/com/sanyzrn/nex/$name.kt',
    ).readAsStringSync();
    final notification = source('NexQuickCapture');
    final widget = source('NexWidgetActions');
    final notificationIds = RegExp(r'const val RC_\w+ = (0x[\dA-Fa-f]+)')
        .allMatches(notification)
        .map((match) => int.parse(match.group(1)!.substring(2), radix: 16))
        .toList();
    final widgetIds = RegExp(r'0x[\dA-Fa-f]+')
        .allMatches(widget)
        .map((match) => int.parse(match[0]!.substring(2), radix: 16))
        .toSet();
    expect(notificationIds, hasLength(4));
    expect(notificationIds.toSet(), hasLength(4));
    expect(widgetIds, isNotEmpty);
    expect(
      notificationIds.toSet().intersection(widgetIds),
      isEmpty,
      reason:
          'Android excludes capture_mode extras from PendingIntent identity',
    );
  });

  test('the tile is declared the way Android requires', () {
    final service = RegExp(
      r'<service\s+android:name="\.NexCaptureTileService"[\s\S]*?</service>',
    ).firstMatch(manifest)?.group(0);
    expect(service, isNotNull);
    expect(service, contains('android:exported="true"'));
    expect(
      service,
      contains('android.permission.BIND_QUICK_SETTINGS_TILE'),
      reason: 'without it any app could bind the tile',
    );
    expect(service, contains('android.service.quicksettings.action.QS_TILE'));
  });

  test('the notification comes back after a reboot, privately', () {
    final receiver = RegExp(
      r'<receiver\s+android:name="\.NexQuickCaptureRestore"[\s\S]*?</receiver>',
    ).firstMatch(manifest)?.group(0);
    expect(receiver, isNotNull);
    expect(receiver, contains('android:exported="false"'));
    expect(receiver, contains('android.intent.action.BOOT_COMPLETED'));
  });

  test(
    'every word the tile and notification show exists in both languages',
    () {
      final kotlin = ['NexCaptureTileService.kt', 'NexQuickCapture.kt']
          .map(
            (name) => File(
              'android/app/src/main/kotlin/com/sanyzrn/nex/$name',
            ).readAsStringSync(),
          )
          .join();
      final used = {
        for (final match in RegExp(r'R\.string\.(\w+)').allMatches(kotlin))
          match.group(1)!,
        'tile_capture_label',
      };
      for (final locale in ['values', 'values-fa']) {
        final strings = File(
          'android/app/src/main/res/$locale/strings.xml',
        ).readAsStringSync();
        for (final name in used) {
          expect(strings, contains('name="$name"'), reason: '$locale: $name');
        }
      }
    },
  );
}
