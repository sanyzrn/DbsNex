import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';

import '../../support/nex_harness.dart';
import 'quit_details.dart';

/// The smoke-free module end to end: setup, dashboard estimates, cravings
/// logged and edited and deleted with Undo, lapses that keep history, and
/// records that outlive the screen.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_smoke_'));
  tearDown(() => harness.dispose());

  Future<NexModuleStore> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final store = NexModuleStore(harness.services, 'smoke_free');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SmokeFreeScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  /// Walks the first-run setup with the given baseline.
  Future<void> setup(
    WidgetTester tester, {
    String daysAgo = '5',
    String perDay = '10',
    String price = '200000',
    String perPack = '20',
  }) async {
    await tester.tap(find.byKey(const ValueKey('smoke-start')));
    await tester.pumpAndSettle();
    await openQuitDetails(tester);
    // The sheet is taller than the test surface; bring each field in.
    await tester.enterText(
      find.byKey(const ValueKey('smoke-field-days')),
      daysAgo,
    );
    await tester.enterText(
      find.byKey(const ValueKey('smoke-field-perday')),
      perDay,
    );
    await tester.enterText(
      find.byKey(const ValueKey('smoke-field-price')),
      price,
    );
    await tester.enterText(
      find.byKey(const ValueKey('smoke-field-perpack')),
      perPack,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('smoke-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smoke-save')));
    await settle(tester);
  }

  Future<void> logCraving(
    WidgetTester tester, {
    String trigger = 'stress',
  }) async {
    await tester.tap(find.byKey(const ValueKey('smoke-log-craving')));
    await tester.pumpAndSettle();
    final chip = find.byKey(ValueKey('craving-trigger-$trigger'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('craving-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await settle(tester);
  }

  group('first run', () {
    testWidgets('an honest invitation, not a questionnaire', (tester) async {
      await pumpScreen(tester);
      expect(find.text('No attempt running.'), findsOneWidget);
      expect(find.byKey(const ValueKey('smoke-start')), findsOneWidget);
      // The setup explains itself before asking anything.
      expect(find.textContaining('only shape the estimates'), findsOneWidget);
    });

    testWidgets('setup walks to a five-day dashboard with honest estimates', (
      tester,
    ) async {
      await pumpScreen(tester);
      await setup(tester, daysAgo: '5', perDay: '10', price: '200000');

      expect(find.text('Smoke-free for 5 days'), findsOneWidget);
      expect(find.text('≈ 50 cigarettes not smoked'), findsOneWidget);
      expect(find.text('≈ 500,000 \u2066IRR\u2069 kept'), findsOneWidget);
      expect(find.textContaining('From 10 a day'), findsOneWidget);
    });

    testWidgets('quitting today reads as today, not as zero days', (
      tester,
    ) async {
      await pumpScreen(tester);
      await setup(tester, daysAgo: '0');
      expect(find.text('Smoke-free since today'), findsOneWidget);
      expect(find.text('≈ 0 cigarettes not smoked'), findsOneWidget);
    });

    testWidgets('negative or nonsense numbers are refused', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('smoke-start')));
      await tester.pumpAndSettle();
      await openQuitDetails(tester);
      await tester.enterText(
        find.byKey(const ValueKey('smoke-field-days')),
        '-3',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('smoke-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smoke-save')));
      await tester.pumpAndSettle();
      expect(find.text('Days cannot be negative'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('smoke-field-days')),
        findsOneWidget,
        reason: 'the sheet is still open',
      );
    });
  });

  group('cravings', () {
    testWidgets('logged in one open: trigger, intensity, note', (tester) async {
      final store = await pumpScreen(tester);
      await setup(tester);
      await logCraving(tester);

      expect(find.text('Strong · Stress'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(await store.list('craving'), hasLength(1));

      final body = (await store.list('craving')).first.body;
      expect(body['triggers'], ['stress']);
      expect(body['intensity'], 2);
    });

    testWidgets('two cravings with a shared trigger name the pattern', (
      tester,
    ) async {
      await pumpScreen(tester);
      await setup(tester);
      await logCraving(tester, trigger: 'stress');
      await logCraving(tester, trigger: 'stress');

      expect(find.text('Most common: Stress (2 times)'), findsOneWidget);
    });

    testWidgets('editing a craving changes its own record only', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await setup(tester);
      await logCraving(tester, trigger: 'stress');
      await logCraving(tester, trigger: 'coffee');

      // Open the newest craving (first in the list) and swap its trigger.
      await tester.tap(find.text('Strong · Coffee or tea'));
      await tester.pumpAndSettle();
      final coffee = find.byKey(const ValueKey('craving-trigger-coffee'));
      await tester.ensureVisible(coffee);
      await tester.pumpAndSettle();
      await tester.tap(coffee);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('craving-trigger-stress')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('craving-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);

      // The edit changed the newest record in place: same two ids, and
      // the newest's trigger went from coffee to stress.
      final cravings = await store.list('craving');
      expect(cravings, hasLength(2), reason: 'editing never duplicates');
      final newest = cravings.reduce(
        (a, b) => ('${a.body['at']}').compareTo('${b.body['at']}') > 0 ? a : b,
      );
      expect(newest.body['triggers'], ['stress']);
    });

    testWidgets('deleting a craving offers Undo, and Undo restores it', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await setup(tester);
      await logCraving(tester);

      final row = find.text('Strong · Stress');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      final delete = find.byKey(const ValueKey('craving-delete'));
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await settle(tester);

      expect(await store.list('craving'), isEmpty);
      expect(find.text('Craving deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(await store.list('craving'), hasLength(1));
      expect(find.text('Strong · Stress'), findsOneWidget);
    });
  });

  group('lapses and attempts', () {
    testWidgets('a lapse with restart keeps history and starts fresh', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await setup(tester, daysAgo: '5');

      await tester.tap(find.byKey(const ValueKey('smoke-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I smoked'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smoke-lapse-restart')));
      await settle(tester);

      // Nothing was erased: one ended attempt, one new one.
      final quits = await store.list('quit');
      expect(quits, hasLength(2));
      expect(quits.where((q) => q.body['endedAt'] == null), hasLength(1));
      expect(find.text('Smoke-free since today'), findsOneWidget);
      expect(find.text('Lasted 5 days'), findsOneWidget);
      expect(find.text('A new attempt started today'), findsOneWidget);
    });

    testWidgets('a lapse without restart leaves a clear start button', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await setup(tester, daysAgo: '3');

      await tester.tap(find.byKey(const ValueKey('smoke-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I smoked'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smoke-lapse-just')));
      await settle(tester);

      expect(find.text('No attempt running.'), findsOneWidget);
      expect(
        find.text('Lasted 3 days'),
        findsOneWidget,
        reason: 'history stays available after recording a lapse',
      );
      expect(await store.list('quit'), hasLength(1));

      // Starting again works from here.
      await tester.tap(find.byKey(const ValueKey('smoke-start')));
      await tester.pumpAndSettle();
      await openQuitDetails(tester);
      expect(find.byKey(const ValueKey('smoke-field-days')), findsOneWidget);
    });

    testWidgets('correcting the baseline never resets the days kept', (
      tester,
    ) async {
      final store = await pumpScreen(tester);
      await setup(tester, daysAgo: '5', price: '200000');

      await tester.tap(find.byKey(const ValueKey('smoke-edit-baseline')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('smoke-field-days')),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        '5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('smoke-field-price')),
        '400000',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('smoke-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smoke-save')));
      await settle(tester);

      expect(find.text('Smoke-free for 5 days'), findsOneWidget);
      expect(find.text('≈ 1,000,000 \u2066IRR\u2069 kept'), findsOneWidget);
      expect(await store.list('quit'), hasLength(1));
    });
  });

  group('the screen is a window, not the data', () {
    testWidgets('records survive disposing and re-opening the screen', (
      tester,
    ) async {
      await pumpScreen(tester);
      await setup(tester, daysAgo: '5');
      await logCraving(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final reopened = NexModuleStore(harness.services, 'smoke_free');
      expect(await reopened.list('quit'), hasLength(1));
      expect(await reopened.list('craving'), hasLength(1));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SmokeFreeScreen(store: reopened),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Smoke-free for 5 days'), findsOneWidget);
      expect(find.text('Strong · Stress'), findsOneWidget);
    });

    testWidgets('another module’s store cannot see these records', (
      tester,
    ) async {
      await pumpScreen(tester);
      await setup(tester);

      final stranger = NexModuleStore(harness.services, 'habits');
      expect(await stranger.list('quit'), isEmpty);
      expect(await stranger.list('craving'), isEmpty);
    });
  });

  group('a meaningful journey', () {
    testWidgets('from setup to a pattern behind the cravings', (tester) async {
      await pumpScreen(tester);
      await setup(tester, daysAgo: '2', perDay: '12', price: '150000');

      expect(find.text('Smoke-free for 2 days'), findsOneWidget);
      await logCraving(tester, trigger: 'coffee');
      await logCraving(tester, trigger: 'coffee');
      await logCraving(tester, trigger: 'stress');

      expect(find.text('Most common: Coffee or tea (2 times)'), findsOneWidget);
      expect(find.text('≈ 24 cigarettes not smoked'), findsOneWidget);
    });
  });

  testWidgets(
    'explicit restart preserves baseline, currency and prior attempt',
    (tester) async {
      final store = await pumpScreen(tester);
      await setup(tester, daysAgo: '5');
      final first = (await store.list('quit')).single;
      await tester.tap(find.byKey(const ValueKey('smoke-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start a new attempt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smoke-confirm-restart')));
      await settle(tester);
      final attempts = await store.list('quit');
      expect(attempts, hasLength(2));
      expect((await store.get('quit', first.id))?['endedWhy'], 'restart');
      expect(attempts.where((r) => r.body['endedAt'] == null), hasLength(1));
      expect(
        attempts
            .where((r) => r.body['endedAt'] == null)
            .single
            .body['currency'],
        'IRR',
      );
    },
  );

  testWidgets('USD baseline stores cents and carries currency into restart', (
    tester,
  ) async {
    final store = await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('smoke-start')));
    await tester.pumpAndSettle();
    await openQuitDetails(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('smoke-field-currency')),
    );
    await tester.tap(find.byKey(const ValueKey('smoke-field-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('smoke-field-price')),
      '6.50',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('smoke-save')));
    await tester.tap(find.byKey(const ValueKey('smoke-save')));
    await settle(tester);
    final first = (await store.list('quit')).single;
    expect(first.body['pricePerPackMinor'], 650);
    expect(first.body['currency'], 'USD');
    await tester.tap(find.byKey(const ValueKey('smoke-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new attempt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smoke-confirm-restart')));
    await settle(tester);
    final current = (await store.list(
      'quit',
    )).singleWhere((r) => r.body['endedAt'] == null);
    expect(current.body['currency'], 'USD');
    expect(current.body['pricePerPackMinor'], 650);
  });
}
