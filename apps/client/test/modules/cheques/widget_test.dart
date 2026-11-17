import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/home.dart';
import 'package:nex_client/modules/cheques/editor.dart';
import 'package:nex_client/modules/cheques/event_editor.dart';
import 'package:nex_client/modules/cheques/repository.dart';
import 'package:nex_client/modules/cheques/model.dart';

import '../../support/nex_harness.dart';
import 'repository_test.dart' show ChequeFaultStore;
import 'fixtures.dart';

Future<void> settleCheque(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
}

Future<void> reachCheque(WidgetTester t, Finder f) async {
  for (final delta in [-350.0, 350.0]) {
    for (var i = 0; i < 15 && f.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).first, Offset(0, delta));
      await t.pumpAndSettle();
    }
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  late NexTestHarness h;
  late ChequeFaultStore store;
  late ChequeRepository repo;
  setUp(() async {
    h = await NexTestHarness.create(name: 'cheque_ui_');
    store = ChequeFaultStore(h);
    repo = ChequeRepository(store);
  });
  tearDown(() => h.dispose());
  Widget app(Widget page) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  );
  Future<void> home(WidgetTester t) async {
    await t.pumpWidget(app(ChequeHome(store: store)));
    await settleCheque(t);
  }

  Future<void> newForm(WidgetTester t) async {
    await home(t);
    await t.tap(find.byKey(const ValueKey('cheque-add')));
    await settleCheque(t);
    await t.enterText(find.byKey(const ValueKey('cheque-party')), 'Customer');
    await t.enterText(find.byKey(const ValueKey('cheque-amount')), '۲٬۵۰۰');
    final date = find.byKey(const ValueKey('cheque-date'));
    await reachCheque(t, date);
    await t.tap(date);
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    final f = find.byKey(const ValueKey('cheque-save'));
    await reachCheque(t, f);
    await t.tap(f);
    await settleCheque(t);
  }

  Future<void> confirm(WidgetTester t, String label) async {
    final f = find.descendant(
      of: find.byType(NexAlertDialog),
      matching: find.text(label),
    );
    await t.tap(f);
    await settleCheque(t);
  }

  Future<void> settlement(WidgetTester t, {String amount = '40'}) async {
    await home(t);
    await t.tap(find.text('Sample party').first);
    await settleCheque(t);
    final settle = find.byKey(const ValueKey('cheque-settle'));
    await reachCheque(t, settle);
    await t.tap(settle);
    await settleCheque(t);
    await t.enterText(
      find.byKey(const ValueKey('cheque-event-amount')),
      amount,
    );
  }

  Future<void> saveEvent(WidgetTester t) async {
    final f = find.byKey(const ValueKey('cheque-event-save'));
    await reachCheque(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
    await confirm(t, 'Record action');
  }

  testWidgets(
    'amount conversion follows typing and locale without a build error',
    (t) async {
      Widget editor(String locale) => MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChequeEditor(repo: repo),
      );
      await t.pumpWidget(editor('en'));
      await settleCheque(t);
      final amount = find.byKey(const ValueKey('cheque-amount'));
      await t.enterText(amount, '25');
      await t.pumpAndSettle();
      expect(find.text('Equivalent: 250 Rial'), findsOneWidget);
      await t.enterText(amount, '75');
      await t.pumpAndSettle();
      expect(find.text('Equivalent: 750 Rial'), findsOneWidget);
      expect(find.text('Equivalent: 250 Rial'), findsNothing);
      await t.pumpWidget(editor('fa'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settleCheque(t);
    },
  );

  testWidgets(
    'status choices stay readable on wide screens in both languages',
    (t) async {
      t.view.physicalSize = const Size(800, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final locale in ['en', 'fa']) {
        await t.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChequeEventEditor(
              repo: repo,
              cheque: Cheque('c', chequeRaw(direction: 'incoming')),
              payment: false,
            ),
          ),
        );
        await settleCheque(t);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await settleCheque(t);
      }
    },
  );

  testWidgets(
    'manual registration picks a date and stores exact Toman money once',
    (t) async {
      await newForm(t);
      await save(t);
      final rows = await store.list('cheque');
      expect(rows.length, 1);
      expect(rows.single.body['amountRial'], 25000);
      expect(rows.single.body['unit'], 'toman');
      expect(rows.single.body['remind'], isFalse);
      expect(await store.list('draft'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Back checkpoints unfinished registration; failed draft read blocks editing and Retry restores it',
    (t) async {
      await home(t);
      await t.tap(find.byKey(const ValueKey('cheque-add')));
      await settleCheque(t);
      await t.enterText(
        find.byKey(const ValueKey('cheque-party')),
        'Draft party',
      );
      await t.binding.handlePopRoute();
      await settleCheque(t);
      expect(await store.get('draft', 'cheque:new'), isNotNull);
      store.failDraftRead = true;
      await t.tap(find.byKey(const ValueKey('cheque-add')));
      await settleCheque(t);
      expect(find.byKey(const ValueKey('cheque-party')), findsNothing);
      store.failDraftRead = false;
      await t.tap(find.text('Try again'));
      await settleCheque(t);
      expect(
        t
            .widget<NexTextField>(find.byKey(const ValueKey('cheque-party')))
            .controller
            .text,
        'Draft party',
      );
    },
  );
  testWidgets(
    'failed cheque write retains complete input and Retry saves once',
    (t) async {
      await newForm(t);
      store.failWrite = true;
      await save(t);
      expect(await store.list('cheque'), isEmpty);
      final field = find.byKey(const ValueKey('cheque-party'));
      await reachCheque(t, field);
      expect(t.widget<NexTextField>(field).controller.text, 'Customer');
      store.failWrite = false;
      await save(t);
      expect((await store.list('cheque')).length, 1);
    },
  );
  testWidgets(
    'partial settlement and reversal preserve the history and precise balance',
    (t) async {
      await t.runAsync(() => repo.save('a', null, chequeRaw()));
      await settlement(t);
      await saveEvent(t);
      var c = Cheque('a', (await store.get('cheque', 'a'))!);
      expect(c.remaining, BigInt.from(960));
      final reverse = find.text('Reverse latest action');
      await reachCheque(t, reverse);
      await t.tap(reverse);
      await t.pumpAndSettle();
      await confirm(t, 'Reverse latest action');
      c = Cheque('a', (await store.get('cheque', 'a'))!);
      expect(c.remaining, BigInt.from(1000));
      expect(c.events.single['voided'], isTrue);
    },
  );
  testWidgets('failed event cleanup cannot duplicate a committed settlement', (
    t,
  ) async {
    await t.runAsync(() => repo.save('a', null, chequeRaw()));
    await settlement(t);
    store.failCleanup = true;
    await saveEvent(t);
    expect(
      Cheque('a', (await store.get('cheque', 'a'))!).paid,
      BigInt.from(40),
    );
    store.failCleanup = false;
    final retry = find.byKey(const ValueKey('cheque-event-save'));
    await reachCheque(t, retry);
    await t.tap(retry);
    await settleCheque(t);
    final c = Cheque('a', (await store.get('cheque', 'a'))!);
    expect(c.events.length, 1);
    expect(c.paid, BigInt.from(40));
  });
  testWidgets(
    'fresh-record checks reject stale editing without destroying typed input',
    (t) async {
      final c = (await t.runAsync(() => repo.save('a', null, chequeRaw())))!;
      await t.pumpWidget(app(ChequeEditor(repo: repo, cheque: c)));
      await settleCheque(t);
      await t.enterText(find.byKey(const ValueKey('cheque-party')), 'My edit');
      await t.runAsync(
        () => store.put('cheque', 'a', {...c.raw, 'party': 'External edit'}),
      );
      await save(t);
      expect((await store.get('cheque', 'a'))!['party'], 'External edit');
      final field = find.byKey(const ValueKey('cheque-party'));
      await reachCheque(t, field);
      expect(t.widget<NexTextField>(field).controller.text, 'My edit');
    },
  );
  testWidgets(
    'delete from a detail route preserves working Undo on the home overlay',
    (t) async {
      final c = (await t.runAsync(
        () => repo.save('a', null, chequeRaw()..['future'] = 'kept'),
      ))!;
      await home(t);
      await t.tap(find.text('Sample party').first);
      await settleCheque(t);
      await t.tap(find.byTooltip('Delete cheque'));
      await t.pumpAndSettle();
      await confirm(t, 'Delete cheque');
      expect(await store.get('cheque', 'a'), isNull);
      expect(find.text('Undo'), findsOneWidget);
      await t.tap(find.text('Undo'));
      await settleCheque(t);
      expect(await store.get('cheque', 'a'), c.raw);
    },
  );
  testWidgets(
    'tabs preserve query, controller, scroll and have no shared FAB hero',
    (t) async {
      await t.runAsync(() async {
        for (var i = 0; i < 24; i++) {
          await repo.save('c$i', null, chequeRaw(party: 'Party $i'));
        }
      });
      await home(t);
      await t.tap(find.text('All cheques'));
      await t.pumpAndSettle();
      final search = find.byKey(const ValueKey('cheque-search'));
      await t.enterText(search, 'Sample');
      await t.pumpAndSettle();
      final key = find.byKey(const PageStorageKey('cheque-all'));
      final controller = t.widget<ListView>(key).controller!;
      await t.drag(key, const Offset(0, -600));
      await t.pumpAndSettle();
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      await t.tap(find.text('Outlook'));
      await t.pumpAndSettle();
      await t.tap(find.text('All cheques'));
      await t.pumpAndSettle();
      expect(t.widget<ListView>(key).controller, same(controller));
      expect(controller.offset, closeTo(offset, 1));
      await reachCheque(t, search);
      final text = t
          .widget<NexSearchField>(find.byType(NexSearchField))
          .controller;
      expect(text.text, 'Sample');
      expect(
        t
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .heroTag,
        isNull,
      );
      expect(t.takeException(), isNull);
    },
  );
}
