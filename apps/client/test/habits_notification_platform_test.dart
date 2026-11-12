import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/habits/habit_reminder.dart';
import 'package:nex_client/platform/daily_nudge.dart';
import 'package:nex_client/platform/daily_nudge_native.dart';
import 'package:nex_client/platform/reminders.dart';

import 'support/nex_harness.dart';

class _RecordingNotifications implements FlutterLocalNotificationsPlugin {
  Map<Symbol, dynamic>? last;
  var attempts = 0;
  bool failExact = false;
  bool failAll = false;
  final cancelled = <int>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #getNotificationAppLaunchDetails:
        return Future<NotificationAppLaunchDetails?>.value();
      case #resolvePlatformSpecificImplementation:
        return null;
      case #zonedSchedule:
        attempts++;
        if (failAll ||
            (failExact &&
                invocation.namedArguments[#androidScheduleMode] ==
                    AndroidScheduleMode.exactAllowWhileIdle)) {
          return Future<void>.error(StateError('scheduling unavailable'));
        }
        last = invocation.namedArguments;
        return Future<void>.value();
      case #cancel:
        cancelled.add(invocation.namedArguments[#id] as int);
        return Future<void>.value();
      case #pendingNotificationRequests:
        return Future<List<PendingNotificationRequest>>.value([]);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexTestHarness h;
  setUp(() async {
    h = await NexTestHarness.create();
    await h.preferences.setModuleOn('habits', true);
  });
  tearDown(() async {
    NexReminders.debugSupported = null;
    await h.dispose();
  });

  test('summary opt-out leaves each habit reminder setting intact', () async {
    final store = NexModuleStore(h.services, 'habits');
    await store.put(habitRemindKind, 'walk', {'on': true, 'minutes': 1200});
    await h.preferences.setBriefUseHabits(true);
    await h.preferences.setBriefUseHabits(false);
    expect((await habitReadReminder(store, 'walk')).on, isTrue);
  });

  for (final fails in [false, true]) {
    test(
      'snooze preserves destination and keeps the original on failure=$fails',
      () async {
        const target = NexModuleTarget(
          'habits',
          kind: 'habit',
          id: 'walk',
          key: 'habit:walk',
          day: '2026-11-01',
        );
        await NexHabitNotificationActions.remember(
          target.payload,
          title: 'Habits',
          body: 'Walking',
          counted: false,
          secret: true,
        );
        final plugin = _RecordingNotifications()
          ..failExact = true
          ..failAll = fails;
        final before = DateTime.now().toUtc();
        final result = await NexHabitNotificationActions.handle(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            id: 7,
            payload: target.payload,
            actionId: NexHabitNotificationActions.snooze,
          ),
          plugin,
        );
        expect(plugin.attempts, 2);
        if (fails) {
          expect(result, isNull);
          expect(plugin.cancelled, isEmpty);
        } else {
          expect(result, target.payload);
          expect(plugin.last![#payload], target.payload);
          expect(
            (plugin.last![#scheduledDate] as DateTime)
                .difference(before)
                .inMinutes,
            60,
          );
          expect(plugin.cancelled, [7]);
        }
      },
    );
  }

  test(
    'daily plan drops mixed cached text immediately on habit opt-out',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      NexReminders.debugSupported = true;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final plans = <Map<String, dynamic>>[];
      const pluginChannel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      messenger.setMockMethodCallHandler(
        pluginChannel,
        (call) async => switch (call.method) {
          'initialize' => true,
          'pendingNotificationRequests' => <Object>[],
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(NexDailyNudgeNative.channel, (
        call,
      ) async {
        if (call.method == 'configure') {
          plans.add(
            jsonDecode(call.arguments as String) as Map<String, dynamic>,
          );
          // A healthy phone: the alarm is taken. This test is about habit
          // consent in the text, not about a refused alarm.
          return true;
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(pluginChannel, null);
        messenger.setMockMethodCallHandler(NexDailyNudgeNative.channel, null);
      });
      final now = DateTime.now();
      final next = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + 2,
      );
      await h.preferences.setDailyNudgeMinutes(next.hour * 60 + next.minute);
      await h.preferences.setDailyNudge(true);
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiDaySummary(text: 'Notes only', dateKey: 'today');
      await h.preferences.setBriefUseHabits(true);
      await h.preferences.setAiDaySummary(
        text: 'SECRET HABIT',
        dateKey: 'today',
        includesHabits: true,
        at: next.subtract(const Duration(seconds: 1)),
      );
      await DailyNudge.apply(
        services: h.services,
        freshlyGeneratedSummary: true,
      );
      Map<String, dynamic> forNextDay() =>
          (plans.last['days'] as Map<String, dynamic>).values.first
              as Map<String, dynamic>;
      expect(forNextDay()['ai'], isTrue);
      expect((forNextDay()['bodies'] as List).join(), contains('SECRET HABIT'));
      await h.preferences.setBriefUseHabits(false);
      await DailyNudge.apply(services: h.services);
      expect(plans, hasLength(2));
      expect(forNextDay()['ai'], isFalse);
      expect(
        (forNextDay()['bodies'] as List).join(),
        isNot(contains('SECRET HABIT')),
      );
      expect(
        (forNextDay()['bodies'] as List).join(),
        isNot(contains('Notes only')),
        reason:
            'opt-out uses the local engine, not an unrelated cached summary',
      );
    },
  );
}
