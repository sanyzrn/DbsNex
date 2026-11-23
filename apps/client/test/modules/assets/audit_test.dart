import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/assets/model.dart';
import 'package:nex_client/modules/assets/screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';
import 'fixtures.dart';

class _HeldReadStore extends NexModuleStore {
  _HeldReadStore(NexTestHarness harness) : super(harness.services, 'assets');

  final holdingSnapshotRead = Completer<void>();
  final releaseHoldingSnapshot = Completer<void>();

  @override
  Future<List<ModuleRecord>> list(String kind) async {
    final records = await super.list(kind);
    if (kind == 'holding' && !holdingSnapshotRead.isCompleted) {
      holdingSnapshotRead.complete();
      await releaseHoldingSnapshot.future;
    }
    return records;
  }
}

void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late List<bool> secure;
  const channel = MethodChannel('nex/os_capture');

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_assets_audit_');
    store = NexModuleStore(harness.services, 'assets');
    secure = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          secure.add((call.arguments as Map)['on'] as bool);
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await harness.dispose();
  });

  Future<void> show(
    WidgetTester t, {
    bool fa = false,
    bool dark = false,
    bool compact = false,
  }) async {
    t.view.physicalSize = compact ? const Size(320, 620) : const Size(390, 880);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(fa ? 'fa' : 'en'),
        theme: dark
            ? nexDarkTheme(fontFamily: 'Vazirmatn')
            : nexLightTheme(fontFamily: 'Inter'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(compact ? 2 : 1),
            disableAnimations: compact,
          ),
          child: child!,
        ),
        home: AssetsScreen(store: store),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester t) async {
    await tap(t, find.text('Reveal holdings'));
  }

  Future<void> tab(WidgetTester t, String label) async {
    await tap(t, find.text(label).first);
  }

  final today = civilDay(DateTime.now());
  final old = today.subtract(const Duration(days: 18));

  Future<void> seedBook({DateTime? quoteDay, bool prices = true}) async {
    final day = quoteDay ?? today;
    await store.put('holding', 'gold', {
      'v': 1,
      ...holdingBody(AssetMarket.gold, 5400, old, price: 75000000),
    });
    await store.put('holding', 'usd', {
      'v': 1,
      ...holdingBody(AssetMarket.usd, 45000, old, price: 600000),
    });
    if (prices) {
      await store.put('quote', 'gold1', {
        'v': 1,
        ...quoteBody(AssetMarket.gold, 95000000, day),
      });
      await store.put('quote', 'usd1', {
        'v': 1,
        ...quoteBody(AssetMarket.usd, 700000, day),
      });
    }
  }

  Future<void> seedFourKinds() async {
    const eur = AssetMarket(AssetType.currency, code: 'EUR');
    const emami = AssetMarket(AssetType.coin, code: 'emami');
    const silver = AssetMarket(AssetType.other, name: 'Silver');
    for (final (id, market, qty, price) in [
      ('gold', AssetMarket.gold, 1000, 100),
      ('coin', emami, 1, 2000),
      ('eur', eur, 100, 1000),
      ('silver', silver, 2, 500),
    ]) {
      await store.put('holding', id, {
        'v': 1,
        ...holdingBody(market, qty, old, price: price),
      });
      await store.put('quote', '$id-q', {
        'v': 1,
        ...quoteBody(
          market,
          market.type == AssetType.gold ? 100 : price,
          today,
        ),
      });
    }
  }

  testWidgets('an empty book opens with one clear way to start', (t) async {
    await show(t);
    await reveal(t);
    expect(find.textContaining('Start the book'), findsOneWidget);
    expect(find.text('Estimated value'), findsNothing);
    expect(find.text('Add holding'), findsOneWidget);
    await tap(t, find.text('Add holding'));
    expect(find.text('Asset type'), findsOneWidget);
  });

  testWidgets('a price can be recorded for a currency before it is held', (
    t,
  ) async {
    await show(t);
    await reveal(t);
    await tab(t, 'Prices');
    await tap(t, find.byType(DropdownButtonFormField<String>).first);
    await tap(t, find.text('Euro').last);
    await tap(t, find.text('Record price'));
    await t.enterText(find.byType(TextField).first, '100000');
    await tap(t, find.text('Save'));
    final quote = (await store.list('quote')).single;
    expect(quote.body['type'], 'currency');
    expect(quote.body['code'], 'EUR');
    expect(quote.body['unitRial'], 1000000);
    expect(find.text('100,000 tomans'), findsNWidgets(2));
  });

  testWidgets('a stale price is offered for refresh and the prompt leaves', (
    t,
  ) async {
    await store.put('holding', 'gold', {
      'v': 1,
      ...holdingBody(AssetMarket.gold, 5400, old, price: 75000000),
    });
    await store.put('quote', 'gold1', {
      'v': 1,
      ...quoteBody(
        AssetMarket.gold,
        95000000,
        today.subtract(const Duration(days: 10)),
      ),
    });
    await show(t);
    await reveal(t);
    expect(find.text('Refresh these prices'), findsOneWidget);
    expect(
      find.text('The last price for some holdings was recorded 10 days ago.'),
      findsOneWidget,
    );
    await tap(t, find.text('Update price').first);
    await t.enterText(find.byType(TextField).first, '10000000');
    await tap(t, find.text('Save'));
    expect(await store.list('quote'), hasLength(2));
    expect(find.text('Refresh these prices'), findsNothing);
    expect(find.text('54,000,000 tomans'), findsOneWidget);
  });

  testWidgets('an unpriced lot says so and leads straight to its price', (
    t,
  ) async {
    await seedBook(prices: false);
    await show(t);
    await reveal(t);
    expect(find.text('2 waiting for a price'), findsOneWidget);
    await tap(t, find.text('Add a price'));
    await t.enterText(find.byType(TextField).first, '90000000');
    await tap(t, find.text('Save'));
    expect(await store.list('quote'), hasLength(1));
    expect(find.text('1 waiting for a price'), findsOneWidget);
  });

  testWidgets('a store update during load refreshes the snapshot', (t) async {
    final held = _HeldReadStore(harness);
    store = held;
    await show(t);
    await t.tap(find.text('Reveal holdings'));
    await t.pump();
    await held.holdingSnapshotRead.future;

    const euro = AssetMarket(AssetType.currency, code: 'EUR');
    await store.put('holding', 'euro', {
      'v': 1,
      ...holdingBody(euro, 100, today, price: 500),
    });
    await t.pump();
    held.releaseHoldingSnapshot.complete();
    await t.pumpAndSettle();

    expect(find.text('1 waiting for a price'), findsOneWidget);
  });

  testWidgets('a future price is kept, warned about and still editable', (
    t,
  ) async {
    await seedBook();
    final future = today.add(const Duration(days: 1));
    await store.put('quote', 'future', {
      'v': 1,
      ...quoteBody(AssetMarket.gold, 100000000, future),
    });
    await show(t);
    await reveal(t);
    await tab(t, 'Prices');
    expect(
      find.text(
        'This price is dated in the future; it does not value the book.',
      ),
      findsWidgets,
    );
    expect(find.text('10,000,000 tomans'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(NexModuleHero),
        matching: find.text('9,500,000 tomans'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NexModuleHero),
        matching: find.text('10,000,000 tomans'),
      ),
      findsNothing,
    );
    await tap(t, find.byType(NexPopupMenuButton<String>).first);
    await tap(t, find.text('Edit'));
    expect(find.text('Edit price'), findsOneWidget);
  });

  testWidgets('a second price for the same day is called out, not hidden', (
    t,
  ) async {
    await seedBook();
    await show(t);
    await reveal(t);
    await tab(t, 'Prices');
    await tap(t, find.text('Record price'));
    expect(
      find.text(
        'A price for this day is already recorded. Saving this one makes it the latest for the day.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('four kinds can be filtered without leaving the book', (t) async {
    await seedFourKinds();
    await show(t);
    await reveal(t);
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('assets-filter-coin')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('assets-filter-coin')), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('assets-filter-coin')));
    expect(find.byKey(const ValueKey('assets-holding-coin')), findsOneWidget);
    expect(find.byKey(const ValueKey('assets-holding-gold')), findsNothing);
    await tap(t, find.byKey(const ValueKey('assets-filter-all')));
    expect(find.byKey(const ValueKey('assets-holding-gold')), findsOneWidget);
  });

  testWidgets('a karat preset keeps the piece and its 18k equivalent in step', (
    t,
  ) async {
    await show(t);
    await reveal(t);
    await tap(t, find.text('Add holding'));
    await t.enterText(find.byType(TextField).first, '2.5');
    await tap(t, find.byKey(const ValueKey('assets-karat-999')));
    expect(
      t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '999',
    );
    expect(find.text('Equals 3.33 g of 18k gold'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(2), '1000000');
    await tap(t, find.text('Save'));
    final row = (await store.list('holding')).single;
    expect(row.body['quantity'], 2500);
    expect(row.body['fineness'], 999);
    expect(row.body['costPerUnitRial'], 10000000);
  });

  testWidgets('the unit switch restates the same rials as tomans or rials', (
    t,
  ) async {
    await seedBook();
    await show(t);
    await reveal(t);
    expect(find.text('82,800,000 tomans'), findsOneWidget);
    await tap(t, find.text('Toman'));
    expect(find.text('828,000,000 rials'), findsOneWidget);
    expect(find.text('Toman'), findsNothing);
    expect(find.text('Rial'), findsOneWidget);
  });

  testWidgets('the book shows where the value sits and its gain percent', (
    t,
  ) async {
    await seedBook();
    await show(t);
    await reveal(t);
    expect(find.text('Where the value sits'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    expect(
      find.text('Estimated gain · 15,300,000 tomans · 22.7%'),
      findsOneWidget,
    );
  });

  testWidgets('deleting a price names what stays', (t) async {
    await seedBook();
    await show(t);
    await reveal(t);
    await tab(t, 'Prices');
    await tap(t, find.byType(NexPopupMenuButton<String>).first);
    await tap(t, find.text('Delete'));
    expect(
      find.text(
        'This price leaves the history. The holding and its cost stay.',
      ),
      findsOneWidget,
    );
    await tap(t, find.text('Cancel'));
    expect(await store.list('quote'), hasLength(2));
  });

  testWidgets(
    'Persian, dark and large text lay out every tab without an error',
    (t) async {
      await seedFourKinds();
      await store.put('goal', 'goal', {
        'v': 1,
        'title': 'طلای پس‌انداز',
        'targetMg': 10000,
      });
      await show(t, fa: true, dark: true, compact: true);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await tap(t, find.text('نمایش دارایی‌ها'));
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await tab(t, 'قیمت‌ها');
      expect(t.takeException(), isNull);
      await tab(t, 'هدف‌ها');
      expect(t.takeException(), isNull);
    },
  );
}
