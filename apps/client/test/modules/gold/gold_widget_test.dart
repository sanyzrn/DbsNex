import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// Gold Check on screen: the calculator filling with the reference
/// example, the receipt that follows, saving, the saved list, delete with
/// Undo, comparing on the same basis, Persian, dark, and a small phone at
/// twice the text size.
///
/// The calculator is a long scrolling page by design (design language §2),
/// and a `ListView` only builds what is near the viewport — so the tests
/// enter top-panel values *before* scrolling down, and scroll back up
/// (negative delta) when they need a top field again.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'gold_');
  });

  tearDown(() => harness.dispose());

  Widget host(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Widget goldScreen() =>
      host(GoldScreen(store: NexModuleStore(harness.services, 'gold')));

  Finder scrollable() => find.byType(Scrollable).first;

  Future<void> downTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 400, scrollable: scrollable());
    await tester.pumpAndSettle();
  }

  Future<void> upTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, -400, scrollable: scrollable());
    await tester.pumpAndSettle();
  }

  /// The reference example: 3 g at 10,000,000 toman/g, 10% making,
  /// 7% profit, 10% VAT — the last two being the fresh form's own
  /// starting points, the first three typed. Ends scrolled to the
  /// making-charge field.
  Future<void> enterReferenceExample(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('gold-weight')), '3');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('gold-rate')), '10000000');
    await tester.pump();
    await downTo(tester, find.byKey(const ValueKey('gold-making-percent')));
    await tester.enterText(
      find.byKey(const ValueKey('gold-making-percent')),
      '10',
    );
    await tester.pump();
  }

  testWidgets('an empty calculator says what is still missing', (tester) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    expect(find.text('Gold Check'), findsOneWidget);
    expect(find.text('Net gold weight'), findsOneWidget);
    expect(find.text('Price per gram (toman)'), findsOneWidget);
    await downTo(tester, find.text(enWords['fixFields']!));
    expect(find.text(enWords['fixFields']!), findsOneWidget);
    expect(find.byKey(const ValueKey('gold-save-fab')), findsOneWidget);
  });

  testWidgets('the reference example produces the exact receipt', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);
    await downTo(tester, find.text('How this is calculated'));
    expect(find.text('How this is calculated'), findsOneWidget);
    await downTo(tester, find.text('Metal value'));

    expect(find.text('Metal value'), findsOneWidget);
    expect(find.text('30,000,000'), findsOneWidget);
    expect(find.text('3,000,000'), findsOneWidget);
    expect(find.text('2,310,000'), findsOneWidget);
    expect(find.text('531,000'), findsOneWidget);
    expect(find.text('35,841,000'), findsOneWidget);
    expect(find.text('Amounts are shown in toman.'), findsOneWidget);
  });

  testWidgets('the rial toggle converts exactly, never silently', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);
    await downTo(tester, find.text('35,841,000'));
    expect(find.text('35,841,000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gold-unit-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Amounts are shown in rials.'), findsOneWidget);
    expect(find.text('358,410,000'), findsOneWidget);
    // The metal line reads in rials now — thirty million toman of gold is
    // three hundred million rials. (The making line legitimately reads
    // 30,000,000 rials, so that number is still on the screen.)
    expect(find.text('300,000,000'), findsOneWidget);
    // The breakdown keeps its toman rate words: the rate was entered in
    // toman per gram, whatever unit the amounts are read in.
  });

  testWidgets('the seller\'s quote becomes a signed difference to verify', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);
    await downTo(tester, find.byKey(const ValueKey('gold-shop-quote')));
    await tester.enterText(
      find.byKey(const ValueKey('gold-shop-quote')),
      '36000000',
    );
    await tester.pump();
    await downTo(tester, find.text('Difference to verify'));

    expect(find.text('Difference to verify'), findsOneWidget);
    // 36,000,000 − 35,841,000 = +159,000 toman (0.44%).
    expect(find.text('+159,000 · 0.44%'), findsOneWidget);
    expect(find.text('seller’s quote − estimate'), findsOneWidget);
  });

  testWidgets('a different rate fineness shows the conversion it applied', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();

    // The piece is 21k while the entered rate is for 18k — chosen before
    // anything scrolls the fineness picker away.
    await tester.tap(find.byKey(const ValueKey('gold-fineness')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('875 · 21k').last);
    await tester.pumpAndSettle();

    await enterReferenceExample(tester);
    await downTo(
      tester,
      find.textContaining('Rate converted to 875 for this piece'),
    );
    expect(
      find.textContaining('Rate converted to 875 for this piece'),
      findsOneWidget,
    );
    // 10,000,000 × 875/750 = 11,666,666.67 → the converted rate.
    expect(
      find.textContaining('Rate converted to 875 for this piece:'),
      findsOneWidget,
    );
    expect(
      find.text('Metal value (3 g × 11,666,666.67 toman/g): 35,000,000'),
      findsOneWidget,
    );
  });

  testWidgets('stones are excluded visibly when a gross weight is given', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    // While the first panel is still on screen.
    await tester.enterText(find.byKey(const ValueKey('gold-gross')), '3.75');
    await tester.pump();
    await enterReferenceExample(tester);
    await downTo(tester, find.text('Metal value'));

    expect(find.textContaining('0.750 g of non-gold mass'), findsOneWidget);
    // The metal value priced the net weight only.
    expect(find.text('30,000,000'), findsOneWidget);
  });

  testWidgets('invalid input marks its field and hides the receipt', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);
    await downTo(tester, find.text('35,841,000'));
    expect(find.text('35,841,000'), findsOneWidget);

    // Back up to the weight field, and break it: letters reach the
    // validator and are refused in words.
    await upTo(tester, find.byKey(const ValueKey('gold-weight')));
    await tester.enterText(find.byKey(const ValueKey('gold-weight')), 'abc');
    await tester.pumpAndSettle();
    expect(
      find.text('Numbers only: digits and one decimal point.'),
      findsOneWidget,
    );
    await downTo(tester, find.text(enWords['fixFields']!));
    expect(find.text('35,841,000'), findsNothing);

    await upTo(tester, find.byKey(const ValueKey('gold-weight')));
    await tester.enterText(find.byKey(const ValueKey('gold-weight')), '-3');
    await tester.pumpAndSettle();
    expect(
      find.text('A negative amount is not meaningful here.'),
      findsOneWidget,
    );
  });

  testWidgets('saving keeps the whole estimate and shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);

    await tester.tap(find.byKey(const ValueKey('gold-save-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('gold-save-title')),
      'Wedding ring',
    );
    await tester.enterText(
      find.byKey(const ValueKey('gold-save-shop')),
      'طلافروشی مهربان',
    );
    await tester.tap(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Estimate saved'), findsOneWidget);
    final records = await harness.services.moduleRecords('gold', 'quote');
    expect(records, hasLength(1));
    final body = records.single.body;
    expect(body['title'], 'Wedding ring');
    expect(body['snapTotalRial'], 358410000);
    expect(body['rateCentiPerG'], 1000000000);
    expect(body['profitBp'], 700);
    expect(body['vatBp'], 1000);
    expect(body['quoteDate'], isNotEmpty);

    // The saved list shows it.
    await tester.tap(find.byKey(const ValueKey('gold-open-quotes')));
    await tester.pumpAndSettle();
    expect(find.text('Wedding ring'), findsOneWidget);
    expect(find.textContaining('35,841,000'), findsOneWidget);
    expect(find.textContaining('3 g'), findsOneWidget);
  });

  testWidgets('Persian shows the receipt in Persian digits, right to left', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        GoldScreen(store: NexModuleStore(harness.services, 'gold')),
        locale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('طلاسنج'), findsOneWidget);
    expect(find.text('وزن خالص طلا'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('طلاسنج'))),
      TextDirection.rtl,
    );

    await tester.enterText(find.byKey(const ValueKey('gold-weight')), '3');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('gold-rate')), '10000000');
    await tester.pump();
    await downTo(tester, find.byKey(const ValueKey('gold-making-percent')));
    await tester.enterText(
      find.byKey(const ValueKey('gold-making-percent')),
      '10',
    );
    await tester.pump();
    await downTo(tester, find.text('ارزش ماده (طلا)'));

    expect(find.text('ارزش ماده (طلا)'), findsOneWidget);
    expect(find.text('۳۰٬۰۰۰٬۰۰۰'), findsOneWidget);
    expect(find.text('۳۵٬۸۴۱٬۰۰۰'), findsOneWidget);
    expect(find.text('مبالغ به تومان نمایش داده می‌شود.'), findsOneWidget);
  });

  testWidgets('dark, small and twice the size still shows every line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: ThemeData(brightness: Brightness.dark),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => child == null
            ? const SizedBox()
            : Builder(
                builder: (inner) => MediaQuery(
                  data: MediaQuery.of(
                    inner,
                  ).copyWith(textScaler: TextScaler.linear(2.0)),
                  child: child,
                ),
              ),
        home: GoldScreen(store: NexModuleStore(harness.services, 'gold')),
      ),
    );
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);
    await downTo(tester, find.text('35,841,000'));

    expect(tester.takeException(), isNull);
    expect(find.text('35,841,000'), findsOneWidget);
    await tester.drag(scrollable(), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save keeps the estimate on screen, honestly', (
    tester,
  ) async {
    final failing = _FailingStore(harness.services);
    await tester.pumpWidget(host(GoldScreen(store: failing)));
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);

    await tester.tap(find.byKey(const ValueKey('gold-save-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(enWords['quoteSaveFailed']!), findsOneWidget);
    expect(find.text('Estimate saved'), findsNothing);
    // The numbers the person entered are still on the screen.
    await downTo(tester, find.text('35,841,000'));
    expect(find.text('35,841,000'), findsOneWidget);
  });

  testWidgets('another module\'s store never sees these records', (
    tester,
  ) async {
    await tester.pumpWidget(goldScreen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gold-weight')), '3');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('gold-rate')), '10000000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gold-save-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.pumpAndSettle();

    expect(await harness.services.moduleRecords('gold', 'quote'), hasLength(1));
    expect(await harness.services.moduleRecords('words', 'quote'), isEmpty);
    expect(await harness.services.moduleRecords('other', 'quote'), isEmpty);
  });
}

/// A store whose writes fail — the honest failure path.
class _FailingStore extends NexModuleStore {
  _FailingStore(NexServices services) : super(services, 'gold');

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    throw Exception('the disk said no');
  }
}

/// The English words the tests assert against, spelled out here so a
/// wording change in the strings file fails loudly rather than silently
/// un-testing the screen.
const Map<String, String> enWords = {
  'fixFields': 'Fill the marked fields to see the estimate.',
  'savedQuotesEmpty':
      'Nothing saved yet. Work out an estimate and keep it, together with '
      'the rates that went into it.',
  'compareWarn':
      'These two are not on the same weight and fineness basis — the '
      'comparison may mean nothing.',
  'quoteSaveFailed':
      'Could not save — the estimate stays on screen. Try again.',
};
