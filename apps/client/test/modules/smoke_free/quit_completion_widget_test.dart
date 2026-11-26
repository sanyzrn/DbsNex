import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/craving_sheet.dart';
import 'package:nex_client/modules/smoke_free/quit_home_screen.dart';
import 'package:nex_client/modules/smoke_free/quit_insights.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import 'package:nex_client/modules/smoke_free/sos_sheet.dart';

import '../../support/nex_harness.dart';
import 'quit_details.dart';
import 'reliability_test.dart' show FaultStore;

class DraftFault extends FaultStore {
  DraftFault(super.inner) {
    failReads = false;
  }
  bool blockDrafts = true;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (kind == 'draft' && blockDrafts) throw StateError('draft unavailable');
    return super.get(kind, id);
  }
}

void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create(name: 'quit_completion_'));
  tearDown(() => h.dispose());
  NexModuleStore store() => NexModuleStore(h.services, 'smoke_free');
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await t.pumpAndSettle();
  }

  Future<void> seed(
    NexModuleStore s, {
    String habit = 'caffeine',
    String name = '',
  }) async {
    await s.put('quit', 'a', {
      'habit': habit,
      'name': name,
      'startedAt': DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String(),
      'cigarettesPerDay': 3,
      'perPack': 1,
      'why': 'Sleep better',
      'futureField': {'keep': true},
    });
  }

  Future<void> openHelp(WidgetTester t, NexModuleStore s) async {
    final a = QuitAttempt.fromBody('a', (await s.get('quit', 'a'))!);
    await t.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSosSheet(context, s, a),
              child: const Text('Help'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Help'));
    await settle(t);
  }

  testWidgets('a report without a trigger is not called a missing report', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        Scaffold(
          body: QuitInsightPanel(
            cravings: [
              Craving(
                id: 'c',
                at: DateTime.now(),
                intensity: 2,
                triggers: const [],
                coping: null,
                note: '',
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('No trigger was recorded in this window.'),
      findsOneWidget,
    );
    expect(find.textContaining('No reports in this window'), findsNothing);
  });

  testWidgets('a running pause survives switching help modes', (t) async {
    final s = store();
    await seed(s);
    await openHelp(t, s);
    await revealQuit(t, find.text('Wait'));
    await t.tap(find.text('Wait'));
    await settle(t);
    await revealQuit(t, find.byKey(const ValueKey('sos-wait-start')));
    await t.tap(find.byKey(const ValueKey('sos-wait-start')));
    await t.pump(const Duration(seconds: 30));
    await revealQuit(t, find.text('Distract'));
    await t.tap(find.text('Distract'));
    await settle(t);
    await t.pump(const Duration(seconds: 30));
    await revealQuit(t, find.text('Wait'));
    await t.tap(find.text('Wait'));
    await settle(t);
    await revealQuit(t, find.byKey(const ValueKey('sos-wait-left')));
    final text = t.widget<Text>(find.byKey(const ValueKey('sos-wait-left')));
    final parts = text.data!
        .split(' ')
        .first
        .split(':')
        .map(int.parse)
        .toList();
    // Navigation/scroll animations also advance the fake clock slightly.
    expect(parts[0] * 60 + parts[1], inInclusiveRange(535, 540));
    expect(await s.list('craving'), isEmpty);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets(
    'an expired restored pause asks for a rating without logging success',
    (t) async {
      final s = store();
      await seed(s);
      final a = QuitAttempt.fromBody('a', (await s.get('quit', 'a'))!);
      await s.put('draft', 'sos:caffeine', {
        'v': 1,
        'base': jsonEncode({
          'attempt': a.id,
          'startedAt': a.startedAt.toIso8601String(),
        }),
        'fields': {
          'mode': 'wait',
          'minutes': 2,
          'left': 120,
          'before': 3,
          'deadline': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      });
      await openHelp(t, s);
      await revealQuit(t, find.byKey(const ValueKey('sos-wait-done')));
      expect(
        find.text('Your pause is over. How strong is the urge now?'),
        findsOneWidget,
      );
      expect(await s.list('craving'), isEmpty);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  testWidgets(
    'a personal plan keeps drafts, saves and preserves unknown fields',
    (t) async {
      final s = store();
      await seed(s);
      await t.pumpWidget(app(SmokeFreeScreen(store: s, habit: 'caffeine')));
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('quit-plan-edit')));
      await t.tap(find.byKey(const ValueKey('quit-plan-edit')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('quit-plan-field')),
        'After tea, I will walk.',
      );
      await t.binding.handlePopRoute();
      await settle(t);
      await t.tap(find.byKey(const ValueKey('quit-plan-edit')));
      await settle(t);
      final field = t.widget<NexTextField>(
        find.byKey(const ValueKey('quit-plan-field')),
      );
      expect(field.controller.text, 'After tea, I will walk.');
      await revealQuit(t, find.byKey(const ValueKey('quit-plan-save')));
      await t.tap(find.byKey(const ValueKey('quit-plan-save')));
      await settle(t);
      final raw = await s.get('quit', 'a');
      expect(raw!['nextStep'], 'After tea, I will walk.');
      expect(raw['futureField'], {'keep': true});
      expect(find.text('After tea, I will walk.'), findsOneWidget);
    },
  );

  testWidgets('unfinished cravings cannot leak from one habit into another', (
    t,
  ) async {
    final s = store();
    await t.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () =>
                      showCravingSheet(context, s, habit: 'caffeine'),
                  child: const Text('Coffee'),
                ),
                TextButton(
                  onPressed: () => showCravingSheet(context, s, habit: 'sugar'),
                  child: const Text('Sugar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(t);
    await t.tap(find.text('Coffee'));
    await settle(t);
    await revealQuit(t, find.byKey(const ValueKey('craving-field-note')));
    await t.enterText(
      find.byKey(const ValueKey('craving-field-note')),
      'Only caffeine',
    );
    await t.binding.handlePopRoute();
    await settle(t);
    await t.tap(find.text('Sugar'));
    await settle(t);
    final note = t.widget<NexTextField>(
      find.byKey(const ValueKey('craving-field-note')),
    );
    expect(note.controller.text, isEmpty);
    await t.binding.handlePopRoute();
    await settle(t);
    await t.tap(find.text('Coffee'));
    await settle(t);
    expect(
      t
          .widget<NexTextField>(
            find.byKey(const ValueKey('craving-field-note')),
          )
          .controller
          .text,
      'Only caffeine',
    );
  });

  testWidgets(
    'failed draft reads block editing until retry recovers the original text',
    (t) async {
      final inner = store();
      await inner.put('draft', 'craving:caffeine:new', {
        'v': 1,
        'base': '{}',
        'fields': {'note': 'Unfinished note'},
      });
      final fault = DraftFault(inner);
      await t.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showCravingSheet(context, fault, habit: 'caffeine'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await settle(t);
      expect(find.byKey(const ValueKey('craving-field-note')), findsNothing);
      fault.blockDrafts = false;
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(
        t
            .widget<NexTextField>(
              find.byKey(const ValueKey('craving-field-note')),
            )
            .controller
            .text,
        'Unfinished note',
      );
    },
  );

  testWidgets('a planned habit has no day-one hero before it starts', (
    t,
  ) async {
    final s = store();
    await s.put('quit', 'a', {
      'habit': 'sugar',
      'startedAt': DateTime.now()
          .add(const Duration(days: 5))
          .toIso8601String(),
    });
    await t.pumpWidget(app(QuitHomeScreen(store: s)));
    await settle(t);
    expect(find.text('Planned starts'), findsOneWidget);
    expect(find.byKey(const ValueKey('quit-hero')), findsNothing);
    expect(find.text('Day one'), findsNothing);
    expect(find.byKey(const ValueKey('quit-habit-sugar')), findsOneWidget);
  });

  testWidgets(
    'a custom rename keeps cravings attached and unknown metadata intact',
    (t) async {
      final s = store();
      await seed(s, habit: 'custom', name: 'Nail biting');
      await s.put('craving', 'c', {
        'habit': 'custom:nail biting',
        'at': DateTime.now().toIso8601String(),
        'intensity': 3,
        'triggers': ['stress'],
        'note': '',
      });
      await t.pumpWidget(
        app(SmokeFreeScreen(store: s, habit: 'custom:nail biting')),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('smoke-edit-baseline')));
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('quit-field-name')));
      await t.enterText(
        find.byKey(const ValueKey('quit-field-name')),
        'My new label',
      );
      await revealQuit(t, find.byKey(const ValueKey('smoke-save')));
      await t.tap(find.byKey(const ValueKey('smoke-save')));
      await settle(t);
      final raw = await s.get('quit', 'a');
      expect(raw!['habitKey'], 'custom:nail biting');
      expect(raw['futureField'], {'keep': true});
      expect(find.text('My new label'), findsWidgets);
      await revealQuit(t, find.text('Overwhelming · Stress'));
      expect(find.text('Overwhelming · Stress'), findsOneWidget);
    },
  );

  testWidgets('an SOS log keeps the time the urge began', (t) async {
    final s = store();
    await seed(s);
    final a = QuitAttempt.fromBody('a', (await s.get('quit', 'a'))!);
    await s.put('draft', 'sos:caffeine', {
      'v': 1,
      'base': jsonEncode({
        'attempt': a.id,
        'startedAt': a.startedAt.toIso8601String(),
      }),
      'fields': {
        'at': '2020-01-02T03:04:00.000',
        'mode': 'breathe',
        'before': 2,
      },
    });
    await openHelp(t, s);
    await revealQuit(t, find.byKey(const ValueKey('sos-log')));
    await t.tap(find.byKey(const ValueKey('sos-log')));
    await settle(t);
    expect(find.byKey(const ValueKey('craving-save')), findsOneWidget);
    await revealQuit(t, find.byKey(const ValueKey('craving-save')));
    await t.tap(find.byKey(const ValueKey('craving-save')));
    await settle(t);

    final logs = await s.list('craving');
    expect(logs, hasLength(1));
    expect('${logs.single.body['at']}', startsWith('2020-01-02T03:04'));
  });

  testWidgets(
    'SOS carries explicit before and after ratings to an editable log',
    (t) async {
      final s = store();
      await seed(s);
      final a = QuitAttempt.fromBody('a', (await s.get('quit', 'a'))!);
      await t.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSosSheet(context, s, a),
                child: const Text('Help'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Help'));
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('sos-before')));
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sos-before')),
          matching: find.text('Overwhelming'),
        ),
      );
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('sos-after')));
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('sos-after')),
          matching: find.text('Light'),
        ),
      );
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('sos-log')));
      await t.tap(find.byKey(const ValueKey('sos-log')));
      await settle(t);
      expect(find.byKey(const ValueKey('craving-intensity')), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t);
      final draft = await s.get('draft', 'craving:caffeine:new');
      expect((draft!['fields'] as Map)['afterIntensity'], 1);
      expect(await s.list('craving'), isEmpty);
      await openHelp(t, s);
      await revealQuit(t, find.byKey(const ValueKey('sos-log')));
      await t.tap(find.byKey(const ValueKey('sos-log')));
      await settle(t);
      await revealQuit(t, find.byKey(const ValueKey('craving-save')));
      await t.tap(find.byKey(const ValueKey('craving-save')));
      await settle(t);
      final logs = await s.list('craving');
      expect(logs.length, 1);
      expect(logs.single.body['intensity'], 3);
      expect(logs.single.body['afterIntensity'], 1);
      expect(logs.single.body['habit'], 'caffeine');
    },
  );
}
