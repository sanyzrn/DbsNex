import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/setup_sheet.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';

import '../../support/nex_harness.dart';
import 'quit_completion_widget_test.dart' show DraftFault;
import 'quit_details.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  late DateTime future;
  setUp(() async {
    h = await NexTestHarness.create(name: 'quit_setup_');
    store = NexModuleStore(h.services, 'smoke_free');
    future = DateTime.now().add(const Duration(days: 4));
    await store.put('quit', 'q', {
      'habit': 'caffeine',
      'startedAt': future.toIso8601String(),
      'why': 'Old reason',
      'goalMinor': 500,
      'minutesPerUnit': 5,
      'nextStep': 'Take a walk',
      'futureField': true,
    });
  });
  tearDown(() => h.dispose());
  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, {NexModuleStore? source}) async {
    final a = QuitAttempt.fromBody('q', (await store.get('quit', 'q'))!);
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSetupSheet(context, source ?? store, editing: a),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Edit'));
    await settle(t);
  }

  Future<void> save(WidgetTester t) async {
    await revealQuit(t, find.byKey(const ValueKey('smoke-save')));
    await t.tap(find.byKey(const ValueKey('smoke-save')));
    await settle(t);
  }

  testWidgets(
    'clearing optional baselines preserves a planned start and unknown metadata',
    (t) async {
      await open(t);
      for (final key in ['why', 'goal', 'minutes']) {
        final field = find.byKey(ValueKey('quit-field-$key'));
        await revealQuit(t, field);
        await t.enterText(field, '');
      }
      await save(t);
      final raw = (await store.get('quit', 'q'))!;
      final a = QuitAttempt.fromBody('q', raw);
      expect(a.startedAt, future);
      expect(a.why, isEmpty);
      expect(a.goalMinor, 0);
      expect(a.minutesPerUnit, 0);
      expect(a.nextStep, 'Take a walk');
      expect(raw['futureField'], true);
    },
  );

  testWidgets('a planned habit can be changed to already started today', (
    t,
  ) async {
    await open(t);
    await revealQuit(t, find.text('Already started'));
    await t.tap(find.text('Already started'));
    await settle(t);
    await save(t);
    final a = QuitAttempt.fromBody('q', (await store.get('quit', 'q'))!);
    expect(a.startedAt.isAfter(DateTime.now()), isFalse);
    expect(a.startedAt.day, DateTime.now().day);
  });

  testWidgets('setup never replaces an unread draft and retries safely', (
    t,
  ) async {
    final fault = DraftFault(store);
    await open(t, source: fault);
    expect(find.byKey(const ValueKey('quit-field-why')), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(await store.list('draft'), isEmpty);
    fault.blockDrafts = false;
    await t.tap(find.text('Try again'));
    await settle(t);
    await revealQuit(t, find.byKey(const ValueKey('quit-field-why')));
    expect(find.text('Old reason'), findsOneWidget);
  });

  testWidgets(
    'resuming a renamed ended habit keeps its identity, plan and baselines',
    (t) async {
      final now = DateTime.now();
      await store.put('quit', 'q', {
        'habit': 'custom',
        'name': 'My new label',
        'habitKey': 'custom:old label',
        'startedAt': now.subtract(const Duration(days: 8)).toIso8601String(),
        'endedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'endedWhy': 'lapse',
        'currency': 'USD',
        'pricePerPackMinor': 250,
        'cigarettesPerDay': 3,
        'perPack': 1,
        'why': 'My reason',
        'nextStep': 'Take a walk',
      });
      await store.put('draft', 'quit:new', {
        'v': 1,
        'base': '{}',
        'fields': {'why': 'Another habit'},
      });
      await store.put('craving', 'c', {
        'habit': 'custom:old label',
        'at': now.toIso8601String(),
        'intensity': 2,
        'triggers': ['stress'],
      });
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SmokeFreeScreen(store: store, habit: 'custom:old label'),
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('smoke-start')));
      await settle(t);
      await save(t);
      final attempts = (await store.list('quit')).map(QuitAttempt.fromRecord);
      final active = attempts.singleWhere((a) => a.isActive);
      expect(active.key, 'custom:old label');
      expect(active.name, 'My new label');
      expect(active.currency, 'USD');
      expect(active.pricePerPackMinor, 250);
      expect(active.cigarettesPerDay, 3);
      expect(active.why, 'My reason');
      expect(active.nextStep, 'Take a walk');
      expect(find.text('My new label'), findsWidgets);
      await revealQuit(t, find.text('Strong · Stress'));
      expect(find.text('Strong · Stress'), findsOneWidget);
    },
  );
}
