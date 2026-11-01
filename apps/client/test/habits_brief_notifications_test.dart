import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/modules/habits/habit_detail_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';

import 'support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  late String today;
  setUp(() async {
    h = await NexTestHarness.create();
    store = NexModuleStore(h.services, 'habits');
    today = dateKeyOf(DateTime.now());
    await h.preferences.setModuleOn('habits', true);
  });
  tearDown(() => h.dispose());

  Future<void> habit(String id, {int goal = 1, bool archived = false}) =>
      store.put('habit', id, {
        'name': id == 'water' ? 'آب خوردن' : 'Walking',
        'note': 'PRIVATE DESCRIPTION MUST STAY LOCAL',
        'schedule': 'daily',
        'goal': goal,
        'unit': 'glasses',
        'archived': archived,
        'createdAt': DateTime.now()
            .subtract(const Duration(days: 14))
            .toIso8601String(),
      });

  test(
    'opt-in defaults off; only the bounded projection leaves the module',
    () async {
      await habit('water', goal: 8);
      await habit('archived', archived: true);
      await store.put('check', HabitCheck.idFor('water', today), {
        'habit': 'water',
        'date': today,
        'amount': 3,
        'at': DateTime.now().toIso8601String(),
      });
      expect(h.preferences.briefUseHabits, isFalse);
      expect((await h.services.habitsForBrief()).source, isEmpty);
      await h.preferences.setBriefUseHabits(true);
      final first = await h.services.habitsForBrief();
      expect(first.source, contains('آب خوردن'));
      expect(first.source, contains('"todayAmount":3'));
      expect(first.source, contains('"dailyGoal":8'));
      expect(first.source, isNot(contains('PRIVATE DESCRIPTION')));
      expect(first.source, isNot(contains('createdAt')));
      expect(first.source, isNot(contains('archived')));
      await store.put('check', HabitCheck.idFor('water', today), {
        'habit': 'water',
        'date': today,
        'amount': 4,
        'at': DateTime.now().toIso8601String(),
      });
      expect(
        (await h.services.habitsForBrief()).source,
        contains('"todayAmount":4'),
      );
    },
  );

  test(
    'disabling hides a mixed cache and preserves the note-only summary',
    () async {
      await habit('walk');
      await h.preferences.setAiDaySummary(
        text: 'Call the bank',
        dateKey: today,
      );
      await h.preferences.setBriefUseHabits(true);
      await h.preferences.setAiDaySummary(
        text: 'Call the bank and walk',
        dateKey: today,
        includesHabits: true,
      );
      await h.preferences.setBriefUseHabits(false);
      expect(h.preferences.aiDaySummaryText, 'Call the bank');
      expect(h.preferences.lastRecap, 'Call the bank');
      final reloaded = await NexPreferences.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.lastRecap, 'Call the bank');
      expect(await store.get('habit', 'walk'), isNotNull);
    },
  );

  test(
    'switching off during a request cannot persist the mixed answer',
    () async {
      await h.preferences.setAiDaySummary(text: 'Notes only', dateKey: today);
      await h.preferences.setBriefUseHabits(true);
      final answer = Completer<String?>();
      final request = h.services.briefRefresh.refresh(
        fingerprint: 'with habits',
        dateKey: today,
        force: true,
        includesHabits: true,
        request: () => answer.future,
      );
      await h.preferences.setBriefUseHabits(false);
      answer.complete('PRIVATE HABIT IN OLD FLIGHT');
      expect((await request).text, 'Notes only');
      expect(h.preferences.lastRecap, 'Notes only');
      expect(h.preferences.aiDaySummaryIncludesHabits, isFalse);
    },
  );

  test(
    'notification destinations encode identifiers and accept legacy module taps',
    () {
      final target = NexModuleTarget(
        'habits',
        kind: 'habit',
        id: 'one:two?x',
        key: 'habit:one:two?x',
        day: today,
      );
      final read = NexModuleTarget.parse(target.payload)!;
      expect(read.id, target.id);
      expect(read.key, target.key);
      expect(read.day, today);
      expect(NexModuleTarget.parse('nex:module:habits')!.module, 'habits');
      expect(NexModuleTarget.parse('nex:module:../secrets'), isNull);
    },
  );

  test(
    'Done is durable and idempotent even when the smart brief is off',
    () async {
      await habit('walk');
      final target = NexModuleTarget(
        'habits',
        kind: 'habit',
        id: 'walk',
        key: 'habit:walk',
        day: today,
      );
      final response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        payload: target.payload,
        actionId: NexHabitNotificationActions.done,
      );
      await NexReminderActions.handle(
        response,
        FlutterLocalNotificationsPlugin(),
      );
      await NexReminderActions.handle(
        response,
        FlutterLocalNotificationsPlugin(),
      );
      expect(await h.services.applyHabitActions(), 1);
      expect(await h.services.applyHabitActions(), 0);
      expect((await store.list('check')), hasLength(1));
      expect(h.preferences.briefUseHabits, isFalse);
    },
  );

  test(
    'old Done actions cannot complete archived or amount-based habits',
    () async {
      await habit('archived', archived: true);
      await habit('water', goal: 8);
      for (final id in ['archived', 'water']) {
        final target = NexModuleTarget(
          'habits',
          kind: 'habit',
          id: id,
          key: 'habit:$id',
          day: today,
        );
        await NexReminderActions.handle(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            payload: target.payload,
            actionId: NexHabitNotificationActions.done,
          ),
          FlutterLocalNotificationsPlugin(),
        );
      }
      expect(await h.services.applyHabitActions(), 0);
      expect(await store.list('check'), isEmpty);
    },
  );

  test(
    'amount notifications open progress; ticks complete without opening UI',
    () {
      final amount = NexHabitNotificationActions.details(
        body: '3/8',
        counted: true,
        secret: true,
      ).android!;
      final tick = NexHabitNotificationActions.details(
        body: 'Walking',
        counted: false,
        secret: false,
      ).android!;
      expect(amount.actions!.first.id, NexHabitNotificationActions.progress);
      expect(amount.actions!.first.showsUserInterface, isTrue);
      expect(tick.actions!.first.id, NexHabitNotificationActions.done);
      expect(tick.actions!.first.showsUserInterface, isFalse);
      expect(tick.actions!.last.id, NexHabitNotificationActions.snooze);
      expect(amount.visibility, NotificationVisibility.secret);
    },
  );

  testWidgets(
    'turning off preserves the card and removes cached habit content',
    (tester) async {
      await h.services.captureText('Read the draft');
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
      );
      await h.preferences.setAiDaySummary(
        text: 'Read the draft',
        dateKey: today,
      );
      await h.preferences.setBriefUseHabits(true);
      await h.preferences.setAiDaySummary(
        text: 'Read the draft and SECRET HABIT',
        dateKey: today,
        includesHabits: true,
      );
      await h.preferences.setBriefUseHabits(false);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('timeline-recap'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('SECRET HABIT'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Read the draft')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a cold notification opens its habit and its progress form', (
    tester,
  ) async {
    await habit('water', goal: 8);
    h.services.reminders.debugLaunchModule(
      NexModuleTarget(
        'habits',
        kind: 'habit',
        id: 'water',
        key: 'habit:water',
        day: today,
        progress: true,
      ),
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-amount-save')), findsOneWidget);
    expect(
      await store.list('check'),
      isEmpty,
      reason: 'opening progress must not save it',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cold habit destination waits behind the app lock', (
    tester,
  ) async {
    await habit('walk');
    await h.preferences.setAppLockEnabled(true);
    await h.preferences.setAppLockClosed(true);
    h.services.reminders.debugLaunchModule(
      NexModuleTarget(
        'habits',
        kind: 'habit',
        id: 'walk',
        key: 'habit:walk',
        day: today,
      ),
    );
    await tester.pumpWidget(
      NexApp(
        services: h.services,
        preferences: h.preferences,
        appLock: _DeniedLock(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(appLockBarrierKey), findsOneWidget);
    expect(find.byType(HabitDetailScreen), findsNothing);
    await h.preferences.setAppLockEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _DeniedLock extends AppLockService {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => false;
  @override
  Future<bool> supportsDeviceAuthentication() async => true;
}
