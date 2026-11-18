import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/controller.dart';
import 'package:nex_client/modules/price_lens/option_editor.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/product_actions.dart';
import 'package:nex_client/modules/price_lens/products.dart';
import 'package:nex_client/modules/price_lens/privacy.dart';
import 'package:nex_client/modules/price_lens/rational.dart';

import 'lens_test_store.dart';
import 'products_test.dart' show observation;
import 'screen_test.dart' as flows;
import '../../support/nex_harness.dart';

class _DraftFaultStore extends LensFaultStore {
  _DraftFaultStore(super.services);
  bool draftReadFails = false;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) =>
      kind == 'draft' && draftReadFails
      ? Future.error(StateError('draft read'))
      : super.get(kind, id);
}

void main() {
  late NexTestHarness h;
  late _DraftFaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'lens_product_ui_');
    store = _DraftFaultStore(h.services);
    flows.store = store;
  });
  tearDown(() => h.dispose());
  Future<void> seed() async {
    await store.put('memory', 'a', {
      ...observation('a', 1, 90000, 1000).toBody(),
      'person': {'name': 'Own shop'},
    });
    await store.put('memory', 'b', observation('b', 15, 90000, 750).toBody());
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'product history shows shrinkage, own shop and masked share text',
    (tester) async {
      await seed();
      await flows.pumpScreen(tester);
      await tester.tap(find.text('My products'));
      await tester.pumpAndSettle();
      expect(find.text('+33.3% per kg over 14 days'), findsOneWidget);
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      expect(
        find.text('Bundle quantity changed from 1 kg to 0.75 kg.'),
        findsOneWidget,
      );
      expect(find.text('Own shop'), findsOneWidget);
      final c = PriceLensController(store);
      await c.load();
      addTearDown(c.dispose);
      String? shared;
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LensPrivacy(
            child: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(actions: const [LensPrivacyButton()]),
                body: TextButton(
                  onPressed: () {
                    shared = productShareText(
                      context,
                      productHistory(c.memories).single,
                    );
                  },
                  child: const Text('Export'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      expect(shared, contains('90,000 rials'));
      expect(shared, contains('Own shop'));
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      expect(shared, contains('••••'));
      expect(shared, isNot(contains('90,000')));
      expect(shared, isNot(contains('ibans')));
    },
  );
  testWidgets(
    'new product price saves actual date and shop, never repeats the last shop',
    (tester) async {
      await seed();
      await flows.pumpScreen(tester);
      await tester.tap(find.text('My products'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-add-price')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(flows.priceField()).controller!.text, '');
      await tester.enterText(flows.priceField(), '۱۲۰۰۰۰');
      await tester.pump();
      await flows.openDetails(tester);
      final shop = find.descendant(
        of: find.byKey(const ValueKey('lens-shop')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(shop).controller!.text, '');
      await tester.enterText(shop, 'My new shop');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      await drain(tester);
      final rows = await store.list('memory');
      expect(rows, hasLength(3));
      final added = rows.firstWhere((r) => r.id != 'a' && r.id != 'b');
      expect(added.body['priceRial'], 120000);
      expect(added.body['person'], {'name': 'My new shop'});
      expect(find.text('My new shop'), findsOneWidget);
    },
  );
  testWidgets('shopping checkboxes persist and adjust the estimate', (
    tester,
  ) async {
    await seed();
    await flows.pumpScreen(tester);
    await tester.tap(find.text('Shopping list'));
    await tester.pumpAndSettle();
    expect(find.text('90,000 rials'), findsNWidgets(2));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await drain(tester);
    expect((await store.list('shopping')).single.body['bought'], isTrue);
    expect(find.text('0 items still needed'), findsOneWidget);
    expect(find.text('Estimated basket'), findsNothing);
    await tester.tap(find.text('My products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping list'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
  testWidgets(
    'calculator offers and unfinished editor survive Back and reopening',
    (tester) async {
      await flows.pumpScreen(tester);
      await flows.addOption(tester);
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lens-label')),
        'Unfinished',
      );
      await tester.pump();
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pumpAndSettle();
      await drain(tester);
      expect(await store.list('memory'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('lens-add')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lens-label')))
            .controller!
            .text,
        'Unfinished',
      );
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pumpAndSettle();
      await drain(tester);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await flows.pumpScreen(tester);
      expect(find.text('Rice'), findsOneWidget);
      expect(await store.list('comparison'), isEmpty);
    },
  );
  testWidgets(
    'draft checkpoints the new family after changing a chosen common unit',
    (tester) async {
      await flows.pumpScreen(tester);
      await flows.addOption(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('lens-common-g')));
      await tester.tap(find.byKey(const ValueKey('lens-common-g')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rice'));
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('lens-unit-l')));
      await tester.tap(find.byKey(const ValueKey('lens-unit-l')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await drain(tester);
      final checkpoint = (await store.get('draft', 'workspace'))!;
      expect((checkpoint['fields'] as Map)['commonUnit'], 'l');
    },
  );
  testWidgets('failed draft reads keep snapshots safe and expose Retry', (
    tester,
  ) async {
    final raw = {
      'v': 1,
      'base': jsonEncode({'workspace': 1}),
      'fields': {'workspaceVersion': 1, 'offers': <Object?>[], 'tab': 0},
    };
    await store.put('draft', 'workspace', raw);
    store.draftReadFails = true;
    await flows.pumpScreen(tester);
    expect(find.byKey(const ValueKey('lens-add')), findsNothing);
    expect(
      find.text('Could not read your draft. Retry to keep it safe.'),
      findsOneWidget,
    );
    store.draftReadFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lens-add')), findsOneWidget);
    expect(await store.get('draft', 'workspace'), raw);
  });
  testWidgets(
    'old sub-rial offers preserve price, discount and shipping when edited',
    (tester) async {
      PriceOption? saved;
      final old = PriceOption(
        id: 'old',
        label: 'Rice',
        priceMinor: 12345,
        currency: 'IRR',
        quantity: const Fraction(1),
        unitKey: 'kg',
        discount: DiscountKind.fixed,
        discountMinor: 125,
        shippingMinor: 25,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showOptionEditor(
                  context,
                  existing: old,
                  onSave: (o) => saved = o,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(flows.priceField()).controller!.text,
        '123.45',
      );
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(saved!.priceMinor, 12345);
      expect(saved!.discountMinor, 125);
      expect(saved!.shippingMinor, 25);
    },
  );
  testWidgets(
    'Persian dates are Jalali even when the global calendar is civil',
    (tester) async {
      await seed();
      await flows.pumpScreen(tester, locale: const Locale('fa'));
      await tester.tap(find.text('کالاهای من'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      expect(find.textContaining('۲۰۲۶'), findsNothing);
      expect(find.textContaining('۱۴۰۵'), findsAtLeast(1));
    },
  );
  testWidgets('comparison Share reaches the system sheet and masks money', (
    tester,
  ) async {
    String? text;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      text = (call.arguments as Map)['text'] as String?;
      return 'success';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await flows.pumpScreen(tester);
    await flows.addOption(
      tester,
      label: 'Small',
      price: '90',
      quantity: '750',
      unitKey: 'g',
    );
    await flows.addOption(tester, label: 'Large', price: '115');
    await tester.ensureVisible(find.text('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(text, contains('Small · 120 rials per kg'));
    await tester.tap(find.byTooltip('Hide amounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(text, contains('••••'));
    expect(text, isNot(contains('120')));
    expect(text, isNot(contains('%')));
  });
}
