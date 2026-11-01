import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/habits/habit_reminder.dart';
import 'package:nex_client/platform/daily_nudge.dart';
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

  testWidgets(
    'daily notification replaces mixed cached text immediately on opt-out',
    (tester) async {
      await h.preferences.setDailyNudge(true);
      await h.preferences.setAiDaySummary(text: 'Notes only', dateKey: 'today');
      await h.preferences.setBriefUseHabits(true);
      await h.preferences.setAiDaySummary(
        text: 'SECRET HABIT',
        dateKey: 'today',
        includesHabits: true,
      );
      late BuildContext localized;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('fa')],
          home: Builder(
            builder: (context) {
              localized = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final plugin = _RecordingNotifications();
      final reminders = NexReminders(plugin: plugin);
      NexReminders.debugSupported = true;
      if (!localized.mounted) return;
      await tester.runAsync(
        () => DailyNudge.apply(
          context: localized,
          preferences: h.preferences,
          reminders: reminders,
          recap: h.preferences.lastRecap,
        ),
      );
      expect(plugin.last![#body], contains('SECRET HABIT'));
      await h.preferences.setBriefUseHabits(false);
      if (!localized.mounted) return;
      await tester.runAsync(
        () => DailyNudge.apply(
          context: localized,
          preferences: h.preferences,
          reminders: reminders,
          recap: 'SECRET HABIT',
        ),
      );
      expect(plugin.last![#body], 'Notes only');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
