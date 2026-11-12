import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_client/platform/daily_nudge_native.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

class _NoCalls implements AIAdapter {
  int calls = 0;
  @override
  Future<Summary>? summarize(Note note) {
    calls++;
    return null;
  }

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) {
    calls++;
    return null;
  }

  @override
  Future<Vector>? embed(String text) {
    calls++;
    return null;
  }

  @override
  Future<OCRText>? ocr(ImageRef image) {
    calls++;
    return null;
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    calls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NexTestHarness h;
  late _NoCalls ai;
  late List<Map<String, dynamic>> plans;
  late int cancellations;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    NexReminders.debugSupported = true;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    plans = [];
    cancellations = 0;
    messenger.setMockMethodCallHandler(NexDailyNudgeNative.channel, (
      call,
    ) async {
      if (call.method == 'configure') {
        plans.add(jsonDecode(call.arguments as String) as Map<String, dynamic>);
        return true;
      }
      if (call.method == 'cancel') cancellations++;
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        return switch (call.method) {
          'initialize' => true,
          'pendingNotificationRequests' => <Object>[],
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          'canScheduleExactNotifications' => false,
          _ => null,
        };
      },
    );
    ai = _NoCalls();
    h = await NexTestHarness.create(adapter: ai);
  });
  tearDown(() async {
    await h.dispose();
    messenger.setMockMethodCallHandler(NexDailyNudgeNative.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
    NexReminders.debugSupported = null;
  });

  test(
    'off cancels daily alarms without building a plan or calling AI',
    () async {
      expect(await h.services.updateDailyNudge(), isNull);
      expect(cancellations, greaterThan(0));
      expect(plans, isEmpty);
      expect(ai.calls, 0);
    },
  );

  test(
    'privacy and selected time rebuild the same native daily plan',
    () async {
      await h.preferences.setDailyNudge(true);
      await h.services.updateDailyNudge();
      expect(plans.last['secret'], isFalse);
      await h.preferences.setAppLockEnabled(true);
      await h.preferences.setDailyNudgeMinutes(21 * 60 + 15);
      await h.services.updateDailyNudge();
      expect(plans, hasLength(2));
      expect(plans.last['secret'], isTrue);
      expect(plans.last['minutes'], 21 * 60 + 15);
      expect(ai.calls, 0);
    },
  );

  test(
    'an alarm the OS refuses is reported and retried, not memorised',
    () async {
      var armed = false;
      messenger.setMockMethodCallHandler(NexDailyNudgeNative.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'configure':
            plans.add(
              jsonDecode(call.arguments as String) as Map<String, dynamic>,
            );
            return armed;
          case 'cancel':
            cancellations++;
            return null;
          default:
            return null;
        }
      });
      await h.preferences.setDailyNudge(true);
      // A switch left on above a phone that kept no alarm is the failure this
      // replaces, so the caller is told rather than given a quiet null.
      expect(await h.services.updateDailyNudge(), NexDailyNudgeNative.notArmed);
      expect(plans, hasLength(1));
      expect(h.services.reminders.lastError, NexDailyNudgeNative.notArmed);
      armed = true;
      expect(await h.services.updateDailyNudge(), isNull);
      expect(
        plans,
        hasLength(2),
        reason: 'a refused alarm is retried, not remembered as the plan',
      );
    },
  );

  test('every planned day carries its own local delivery window', () async {
    await h.preferences.setDailyNudge(true);
    await h.services.updateDailyNudge();
    final days = plans.last['days'] as Map<Object?, Object?>;
    expect(days, isNotEmpty);
    for (final day in days.values.cast<Map<Object?, Object?>>()) {
      expect(day['localExpires'], isA<int>());
      expect(
        (day['expires'] as int) <= (day['localExpires'] as int),
        isTrue,
        reason: 'a recap never outlives the day it describes',
      );
    }
  });

  test('completing a checklist rebuilds the nudge while its detail stays open', () async {
    final note = (await h.services.captureChecklist([
      const ChecklistItem(text: 'open-task', done: false),
    ]))!;
    await h.preferences.setDailyNudge(true);
    await h.services.updateDailyNudge();
    expect(plans, hasLength(1));
    expect(jsonEncode(plans.last['days']), contains('open-task'));
    await h.services.toggleChecklistItem(note.id, 0);
    // No timeline refresh or navigation: the data mutation itself schedules it.
    for (var i = 0; i < 60 && plans.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(plans, hasLength(2));
    expect(jsonEncode(plans.last['days']), isNot(contains('open-task')));
    expect(ai.calls, 0);
  });

  for (final master in [false, true]) {
    test(
      'AI=$master and summary off uses local facts, updates and cancels',
      () async {
        await h.preferences.setAiEnabled(master);
        await h.preferences.setShowDaySummary(false);
        await h.preferences.setAiDaySummary(
          text: 'DO NOT REUSE THIS CACHE',
          dateKey: '2026-11-03',
        );
        final note = (await h.db.captureText('urgent-plan'))!;
        await h.db.setUrgent(note.id, true);
        await h.preferences.setDailyNudge(true);
        expect(await h.services.updateDailyNudge(), isNull);
        expect(plans, hasLength(1));
        final days = plans.last['days'] as Map<Object?, Object?>;
        for (final day in days.values.cast<Map<Object?, Object?>>()) {
          expect(day['ai'], isFalse);
          expect((day['bodies'] as List).join(), contains('urgent-plan'));
          expect(
            (day['bodies'] as List).join(),
            isNot(contains('DO NOT REUSE')),
          );
        }
        await h.services.updateDailyNudge();
        expect(
          plans,
          hasLength(1),
          reason: 'unchanged input does not reschedule',
        );
        await h.services.setUrgent(note.id, false);
        await h.services.updateDailyNudge();
        expect(plans, hasLength(2));
        expect(
          (plans.last['fallback'] as List).join(),
          isNot(contains('first note')),
        );
        final before = plans.length;
        await h.preferences.setDailyNudge(false);
        await h.services.updateDailyNudge();
        expect(plans, hasLength(before));
        expect(cancellations, greaterThan(1));
        expect(ai.calls, 0);
      },
    );
  }
}
