import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_form.dart';
import 'package:nex_client/modules/gold/gold_market_page.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'gold_market_'),
  );
  tearDown(() => harness.dispose());
  NexModuleStore store() => NexModuleStore(harness.services, 'gold');
  Widget host(
    Widget child, {
    bool fa = false,
    bool dark = false,
    double scale = 1,
  }) => MaterialApp(
    locale: Locale(fa ? 'fa' : 'en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: dark ? nexSoftDarkTheme() : nexSoftLightTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: child,
  );
  Future<void> reveal(WidgetTester t, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    for (final delta in [300.0, -300.0]) {
      for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
        final position = t.state<ScrollableState>(scrollable).position;
        final before = position.pixels;
        await t.drag(scrollable, Offset(0, -delta));
        await t.pumpAndSettle();
        if (position.pixels == before) break;
      }
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, String key, String value) async {
    final field = find.byKey(ValueKey('gold-$key'));
    await reveal(t, field);
    await t.enterText(field, value);
    await t.pumpAndSettle();
  }

  testWidgets('Buy, Sell and Melted switch in place: no page, nothing '
      'lost (2.8.2)', (t) async {
    await t.pumpWidget(host(GoldScreen(store: store())));
    await t.pumpAndSettle();
    await fill(t, 'weight', '3');
    final route = ModalRoute.of(t.element(find.byType(GoldScreen)));

    await reveal(t, find.text('Sell'));
    await t.tap(find.text('Sell'));
    await t.pumpAndSettle();
    // The same screen: selling is a tab of it, not a page over it.
    expect(ModalRoute.of(t.element(find.byType(GoldScreen))), route);
    expect(route!.isCurrent, isTrue);
    expect(find.byType(GoldMarketPage), findsNothing);
    expect(find.byType(GoldMarketPanel), findsOneWidget);
    await fill(t, 'sellWeight', '2.5');

    await reveal(t, find.text('Melted gold'));
    await t.tap(find.text('Melted gold'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Buy'));
    await t.tap(find.text('Buy'));
    await t.pumpAndSettle();
    // What was typed in Buy is still there, without a reload.
    expect(
      t
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('gold-weight')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '3',
    );
    await reveal(t, find.text('Sell'));
    await t.tap(find.text('Sell'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('gold-sellWeight')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '2.5',
    );
    // No save button where there is nothing to save.
    expect(find.byKey(const ValueKey('gold-save-fab')), findsNothing);
  });

  testWidgets(
    'purchase requires explicit making, with market defaults already filled',
    (t) async {
      await t.pumpWidget(host(GoldScreen(store: store())));
      await t.pumpAndSettle();
      await fill(t, 'weight', '3');
      await fill(t, 'rate', '10000000');
      final form = t.state<GoldFormState>(find.byType(GoldForm));
      expect(
        form.buildInput(),
        isNull,
      ); // Empty is not a silently free making charge.
      await fill(t, 'making-percent', '0');
      expect(form.buildInput()!.profitBp, 700);
      expect(form.buildInput()!.vatBp, 1000);
      expect(form.buildInput()!.makingPercentBp, 0);
      expect(find.byKey(const ValueKey('gold-profit')), findsNothing);
      await reveal(t, find.byKey(const ValueKey('gold-purchase-details')));
      await t.tap(find.byKey(const ValueKey('gold-purchase-details')));
      await t.pumpAndSettle();
      await fill(t, 'profit', '5');
      expect(form.buildInput()!.profitBp, 500);
    },
  );

  testWidgets('a tiny converted rate shows an error on the Melted gold tab', (
    t,
  ) async {
    await t.pumpWidget(host(GoldScreen(store: store())));
    await t.pumpAndSettle();
    await t.tap(find.text('Melted gold'));
    await t.pumpAndSettle();
    await fill(t, 'meltWeight', '3');
    await fill(t, 'meltQuote', '0.01');

    expect(
      find.text('Enter a higher rate. The converted rate rounds to zero.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gold-market-result')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('purchase details stay in place while the estimate changes', (
    t,
  ) async {
    await t.pumpWidget(host(GoldScreen(store: store()), fa: true));
    await t.pumpAndSettle();
    await fill(t, 'weight', '3');
    await fill(t, 'rate', '10000000');
    await fill(t, 'making-percent', '10');

    final details = find.byKey(const ValueKey('gold-purchase-details'));
    await reveal(t, details);
    await t.tap(details);
    await t.pumpAndSettle();

    final gross = find.byKey(const ValueKey('gold-gross'));
    await reveal(t, gross);
    await t.showKeyboard(gross);
    t.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(t.view.resetViewInsets);
    await reveal(t, gross);
    final y = t.getTopLeft(gross).dy;
    await t.enterText(gross, '1');
    await t.pumpAndSettle();

    expect(find.text('وزن کل نباید از وزن خالص کمتر باشد.'), findsOneWidget);
    expect(t.getTopLeft(gross).dy, closeTo(y, 1));
    expect(find.byKey(const ValueKey('gold-hero')), findsNothing);

    await t.enterText(gross, '17');
    await t.pumpAndSettle();
    expect(t.getTopLeft(gross).dy, closeTo(y, 1));
    expect(find.byKey(const ValueKey('gold-hero')), findsOneWidget);

    await reveal(t, details);
    await t.tap(details);
    await t.pumpAndSettle();
    expect(gross, findsNothing);
  });

  testWidgets(
    'leaving Sell waits for the draft and can retry a write failure',
    (t) async {
      final moduleStore = _MarketWriteStore(harness.services);
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoldScreen(store: moduleStore),
                  ),
                ),
                child: const Text('Open gold'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open gold'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sell'));
      await t.pumpAndSettle();
      await fill(t, 'sellWeight', '2.5');

      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(GoldScreen), findsOneWidget);
      expect(find.textContaining('Could not save your draft'), findsOneWidget);

      moduleStore.fail = false;
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Open gold'), findsOneWidget);
      final draft = await moduleStore.get('draft', 'market:tools');
      expect((draft?['fields'] as Map?)?['sellWeight'], '2.5');
    },
  );

  testWidgets(
    'sale uses explicit deductions and shows break-even, copy and invalid state',
    (t) async {
      await t.pumpWidget(host(GoldMarketPage(store: store(), mode: 1)));
      await t.pumpAndSettle();
      await fill(t, 'sellWeight', '3');
      await fill(t, 'sellRate', '10000000');
      await reveal(t, find.byKey(const ValueKey('gold-market-result')));
      expect(find.text('30,000,000'), findsOneWidget);
      await reveal(t, find.byKey(const ValueKey('gold-sale-details')));
      await t.tap(find.byKey(const ValueKey('gold-sale-details')));
      await t.pumpAndSettle();
      await fill(t, 'cost', '35841000');
      await reveal(t, find.text('Break-even 750 rate'));
      expect(find.text('Break-even 750 rate'), findsOneWidget);
      expect(find.byKey(const ValueKey('gold-market-copy')), findsOneWidget);
      await fill(t, 'deduction', '100.01');
      expect(find.byKey(const ValueKey('gold-market-result')), findsNothing);
      await fill(t, 'deduction', '1');
      await fill(t, 'fee', '40000000');
      expect(
        find.text(
          'Check the values: deductions must not exceed the gold value.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'melted quote conversion and independent inputs survive route leave and reopen',
    (t) async {
      final moduleStore = store();
      await t.pumpWidget(host(GoldMarketPage(store: moduleStore, mode: 2)));
      await t.pumpAndSettle();
      await fill(t, 'meltQuote', '43318020');
      await fill(t, 'meltWeight', '3');
      await reveal(t, find.byKey(const ValueKey('gold-market-result')));
      expect(find.text('30,000,000'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpWidget(host(GoldMarketPage(store: moduleStore, mode: 2)));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('gold-meltQuote')))
            .controller!
            .text,
        '43,318,020',
      );
      await reveal(t, find.byKey(const ValueKey('gold-market-result')));
      expect(find.text('30,000,000'), findsOneWidget);
      expect(await moduleStore.list('quote'), isEmpty);
    },
  );

  testWidgets(
    'malformed draft choices safely fall back and raw invalid input remains editable',
    (t) async {
      final moduleStore = store();
      await moduleStore.put('draft', 'market:tools', {
        'v': 1,
        'base': '{}',
        'fields': {
          'settlement': -1,
          'fineness': 'bad',
          'mithqal': true,
          'meltQuote': 'not a price',
          'meltWeight': '۳',
        },
      });
      await t.pumpWidget(host(GoldMarketPage(store: moduleStore, mode: 2)));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('gold-meltQuote')))
            .controller!
            .text,
        'not a price',
      );
      expect(find.byKey(const ValueKey('gold-market-result')), findsNothing);
      await fill(t, 'meltQuote', '۴۳۳۱۸۰۲۰');
      await reveal(t, find.byKey(const ValueKey('gold-market-result')));
      expect(find.text('30,000,000'), findsOneWidget);
    },
  );

  for (final fa in [false, true]) {
    for (final dark in [false, true]) {
      for (final mode in [1, 2]) {
        testWidgets(
          'market mode $mode, fa:$fa, dark:$dark at 320dp and 2x text',
          (t) async {
            t.view.physicalSize = const Size(320, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            await t.pumpWidget(
              host(
                GoldMarketPage(store: store(), mode: mode),
                fa: fa,
                dark: dark,
                scale: 2,
              ),
            );
            await t.pumpAndSettle();
            await fill(t, mode == 1 ? 'sellWeight' : 'meltWeight', '۳');
            await fill(
              t,
              mode == 1 ? 'sellRate' : 'meltQuote',
              mode == 1 ? '۱۰۰۰۰۰۰۰' : '۴۳۳۱۸۰۲۰',
            );
            await reveal(t, find.byKey(const ValueKey('gold-market-copy')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('gold-market-result')),
              findsOneWidget,
            );
          },
        );
      }
    }
  }
}

class _MarketWriteStore extends NexModuleStore {
  _MarketWriteStore(NexServices services) : super(services, 'gold');

  bool fail = true;

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) {
    if (fail && kind == 'draft' && id == 'market:tools') {
      return Future.error(StateError('draft write failed'));
    }
    return super.put(kind, id, body);
  }
}
