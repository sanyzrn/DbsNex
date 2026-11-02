import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/screens/tools/pinned_module_summary.dart';
import 'package:nex_client/screens/tools/pinned_tools.dart';
import 'package:nex_client/widgets/nex_shelf.dart';
import 'package:nex_core/nex_core.dart';
import 'support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late AppLocalizations l;
  final now = DateTime(2026, 11, 2, 12);
  setUp(() async {
    h = await NexTestHarness.create();
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });
  tearDown(() => h.dispose());
  Future<NexPinnedSummary?> load(String id) => nexPinnedModuleSummary(
    id: id,
    services: h.services,
    preferences: h.preferences,
    l10n: l,
    now: now,
  );
  Future<void> habit(String id, {bool archived = false, int goal = 1}) =>
      NexModuleStore(h.services, 'habits').put('habit', id, {
        'name': id,
        'schedule': 'daily',
        'goal': goal,
        'archived': archived,
        'createdAt': now.subtract(const Duration(days: 10)).toIso8601String(),
      });

  test('inactive modules have no summary', () async {
    expect(await load('habits'), isNull);
    expect(await load('words'), isNull);
    expect(await load('cycle'), isNull);
  });
  test(
    'habits count completed goals, remaining items and archived data correctly',
    () async {
      await h.preferences.setModuleOn('habits', true);
      await habit('water', goal: 8);
      await habit('walk');
      await habit('archived', archived: true);
      final store = NexModuleStore(h.services, 'habits');
      await store.put('check', HabitCheck.idFor('water', dateKeyOf(now)), {
        'habit': 'water',
        'date': dateKeyOf(now),
        'amount': 8,
        'at': now.toIso8601String(),
      });
      final summary = (await load('habits'))!;
      expect(summary.primary, l.pinHabitsProgress(1, 2));
      expect(summary.secondary, l.pinHabitsLeft(1));
      expect(h.preferences.briefUseHabits, isFalse);
    },
  );
  test(
    'word counts respect paused cards and the daily introduction allowance',
    () async {
      await h.preferences.setModuleOn('words', true);
      final store = NexModuleStore(h.services, 'words');
      await store.put('settings', WordsSettings.recordId, {'newPerDay': 2});
      Future<void> put(
        String id, {
        bool fresh = false,
        bool paused = false,
        bool introduced = false,
      }) => store.put(
        'card',
        id,
        WordCard(
          id: id,
          headword: id,
          language: 'en',
          createdAtIso: '2026-10-01',
          reps: fresh ? 0 : 1,
          due: introduced ? '2026-11-10' : '2026-11-01',
          introducedOn: fresh
              ? ''
              : introduced
              ? '2026-11-02'
              : '2026-10-01',
          paused: paused,
        ).toRecord(),
      );
      await put('due-a');
      await put('due-b');
      await put('paused', paused: true);
      await put('fresh-a', fresh: true);
      await put('fresh-b', fresh: true);
      await put('introduced-today', introduced: true);
      final summary = (await load('words'))!;
      expect(summary.primary, l.pinWordsDue(2));
      expect(summary.secondary, l.pinWordsNew(1));
    },
  );
  test('occasions use their own calendar and skip archived dates', () async {
    await h.preferences.setModuleOn('occasions', true);
    final store = NexModuleStore(h.services, 'occasions');
    final solar = nexPersianDate(now);
    await store.put('occasion', 'today', {
      'title': 'Jalali birthday',
      'kind': 'birthday',
      'calendar': 'jalali',
      'month': solar.month,
      'day': solar.day,
    });
    await store.put('occasion', 'archived', {
      'title': 'Hidden',
      'kind': 'birthday',
      'calendar': 'gregorian',
      'month': now.month,
      'day': now.day,
      'archived': true,
    });
    final summary = (await load('occasions'))!;
    expect(summary.primary, 'Jalali birthday');
    expect(summary.secondary, l.cycleDayToday);
  });
  test(
    'breathing duration follows the selected pattern without starting a session',
    () async {
      await h.preferences.setModuleOn('pause', true);
      expect((await load('pause'))!.primary, l.pinPauseDuration('1:50'));
      await h.preferences.setPauseMode('focus');
      final focus = (await load('pause'))!;
      expect(focus.primary, l.pinPauseDuration('1:36'));
      expect(focus.secondary, l.pauseModeFocus);
    },
  );
  test(
    'Cycle handles setup and pregnancy without predicting a period',
    () async {
      await h.preferences.setCycleEnabled(true);
      expect((await load('cycle'))!.primary, l.pinCycleSetup);
      await h.preferences.setCycleSetUp(true);
      await h.preferences.setCycleMode(CycleMode.pregnant);
      await h.preferences.setCyclePregnancyStart(CycleDate.parse('2026-09-01'));
      final summary = (await load('cycle'))!;
      expect(summary.primary, l.cyclePregnancyWeek('8', '6'));
      expect(summary.secondary, l.cycleModePregnant);
      await h.preferences.setCycleMode(CycleMode.breastfeeding);
      expect((await load('cycle'))!.primary, l.pinCycleLog);
    },
  );

  for (final locale in ['en', 'fa']) {
    testWidgets(
      '$locale: facts update locally, keep the compact height and still unpin',
      (tester) async {
        l = await AppLocalizations.delegate.load(Locale(locale));
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await h.preferences.setModuleOn('habits', true);
        final today = DateTime.now();
        final store = NexModuleStore(h.services, 'habits');
        await store.put('habit', 'walk', {
          'name': 'Walking',
          'schedule': 'daily',
          'createdAt': today
              .subtract(const Duration(days: 10))
              .toIso8601String(),
        });
        await h.preferences.togglePinnedTool('module.habits');
        await h.preferences.togglePinnedTool('generator');
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PinnedTools(
                services: h.services,
                preferences: h.preferences,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.pinHabitsProgress(0, 1)), findsOneWidget);
        final module = find.byKey(const ValueKey('pinned-tool-module.habits'));
        final generator = find.byKey(const ValueKey('pinned-tool-generator'));
        Finder tile(Finder parent) =>
            find.descendant(of: parent, matching: find.byType(NexShelfTile));
        expect(
          tester.getSize(tile(module)).height,
          tester.getSize(tile(generator)).height,
        );
        await store.put('check', HabitCheck.idFor('walk', dateKeyOf(today)), {
          'habit': 'walk',
          'date': dateKeyOf(today),
          'amount': 1,
          'at': today.toIso8601String(),
        });
        await tester.pumpAndSettle();
        expect(find.text(l.pinHabitsProgress(1, 1)), findsOneWidget);
        expect(find.text(l.pinHabitsProgress(0, 1)), findsNothing);
        expect(tester.takeException(), isNull);
        final element = tester.element(find.byType(PinnedTools));
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: app.localizationsDelegates,
            supportedLocales: app.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(body: element.widget),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.longPress(module);
        await tester.pumpAndSettle();
        expect(module, findsNothing);
        expect(h.preferences.pinnedTools, isNot(contains('module.habits')));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
