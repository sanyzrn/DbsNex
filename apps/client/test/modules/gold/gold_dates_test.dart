import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_dates.dart';
import 'package:nex_client/modules/gold/gold_format.dart';
import 'package:nex_client/modules/gold/gold_math.dart';
import 'package:nex_client/modules/gold/gold_models.dart';
import 'package:nex_client/modules/gold/gold_quotes_page.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart'
    show nexDisplayDate, nexGregorianDate, nexPersianDate;

import '../../support/nex_harness.dart';

/// Dates on the person's own calendar. The quote day is entered as civil
/// `YYYY-MM-DD` or picked from the shared calendar — Jalali for a Persian
/// reader — and lands in the field and in storage as the same civil day;
/// every day the module shows (the detail sheet, both comparison columns,
/// the receipt breakdown, the «Saved …» line's absolute day) goes through
/// the shared module date label, so the same stored value reads as a
/// Jalali day with Persian digits or a civil day, and the retired
/// «Gregorian» apology is gone from both languages.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'gold_dates_');
  });

  tearDown(() => harness.dispose());

  Widget materialApp(Widget home, Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  // A NexModuleCalendar wrapping the MaterialApp, the way the app itself
  // provides it: above the Navigator, so pushed routes (the detail sheet)
  // read it too — wrapping `home` alone would leave the sheet without it.
  Widget host(
    Widget home, {
    Locale locale = const Locale('en'),
    bool solar = false,
  }) => solar
      ? NexModuleCalendar(solar: true, child: materialApp(home, locale))
      : materialApp(home, locale);

  Finder scrollable() => find.byType(Scrollable).first;

  Future<void> downTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 400, scrollable: scrollable());
    await tester.pumpAndSettle();
  }

  /// The reference example typed into the calculator, leaving it valid.
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

  GoldQuote quoteOf(String id) => GoldQuote(
    id: id,
    title: 'Necklace',
    shop: '',
    savedAtIso: '2026-10-13T09:00:00',
    quoteDateIso: '2026-10-13',
    notes: '',
    input: const GoldInput(
      weightMg: 3000,
      finenessPpt: 750,
      rateCentiPerG: 1000000000,
      rateRefPpt: 750,
      makingPercentBp: 1000,
    ),
    metalValueRial: 300000000,
    makingChargeRial: 30000000,
    sellerProfitRial: 23100000,
    commissionRial: 0,
    vatBaseRial: 53100000,
    vatRial: 5310000,
    extrasRial: 0,
    estimatedTotalRial: 358410000,
  );

  testWidgets('a Persian reader picks the quote day on the Jalali calendar', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await tester.pumpWidget(
      host(GoldScreen(store: store), locale: const Locale('fa')),
    );
    await tester.pumpAndSettle();
    await enterReferenceExample(tester);

    await tester.tap(find.byKey(const ValueKey('gold-save-fab')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(NexAlertDialog), findsOneWidget);

    await tester.ensureVisible(find.text('۲۰'));
    await tester.tap(find.text('۲۰'));
    await tester.pump();
    await tester.tap(find.text('تأیید'));
    await tester.pumpAndSettle();

    // The Jalali day lands in the field as the same civil day, in the
    // module's own hyphenated entry format.
    final now = nexPersianDate(DateTime.now());
    final expected = isoDay(nexGregorianDate(now.year, now.month, 20));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('gold-save-date')))
          .controller!
          .text,
      expected,
    );

    await tester.tap(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.pumpAndSettle();
    final records = await harness.services.moduleRecords('gold', 'quote');
    expect(records.single.body['quoteDate'], expected);
  });

  testWidgets('the detail sheet names the quote day on the shared label', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', 'q1', quoteOf('q1').toRecord());
    await tester.pumpWidget(
      host(GoldQuotesPage(store: store, showRials: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Necklace'));
    await tester.pumpAndSettle();

    expect(find.text('Quote date 2026/10/13'), findsOneWidget);
    // The Gregorian apology is retired in both languages.
    expect(find.text('Gregorian'), findsNothing);
  });

  testWidgets('a Persian reader reads the same day as Jalali, Persian digits', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', 'q1', quoteOf('q1').toRecord());
    await tester.pumpWidget(
      host(
        GoldQuotesPage(store: store, showRials: false),
        locale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Necklace'));
    await tester.pumpAndSettle();

    final jalali = nexDisplayDate(
      DateTime(2026, 10, 13),
      solar: true,
      persian: true,
    );
    expect(jalali.contains(RegExp('[0-9]')), isFalse);
    expect(find.text('تاریخ تخمین $jalali'), findsOneWidget);
    expect(find.text('میلادی'), findsNothing);
  });

  testWidgets('an English reader who chose the Jalali calendar sees Jalali', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', 'q1', quoteOf('q1').toRecord());
    await tester.pumpWidget(
      host(GoldQuotesPage(store: store, showRials: false), solar: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Necklace'));
    await tester.pumpAndSettle();

    // Outside a NexModuleCalendar a Persian locale falls back to Solar; this
    // page reads the chosen calendar, not the words' language.
    expect(
      find.text(
        'Quote date '
        '${nexDisplayDate(DateTime(2026, 10, 13), solar: true, persian: false)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('both columns of a comparison carry the shared day label', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', 'a', quoteOf('a').toRecord());
    await store.put('quote', 'b', quoteOf('b').toRecord());
    await tester.pumpWidget(
      host(
        GoldQuotesPage(store: store, showRials: false),
        locale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-compare-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Necklace').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Necklace').last);
    await tester.pumpAndSettle();

    final jalali = nexDisplayDate(
      DateTime(2026, 10, 13),
      solar: true,
      persian: true,
    );
    expect(find.text(jalali), findsNWidgets(2));
    expect(find.text('میلادی'), findsNothing);
  });

  testWidgets('the receipt breakdown names the quote day the same way', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    final quote = quoteOf('q1');
    await store.put('quote', 'q1', quote.toRecord());
    await tester.pumpWidget(host(GoldScreen(store: store, editing: quote)));
    await tester.pumpAndSettle();
    await downTo(
      tester,
      find.text('Quote date 2026/10/13, rate at 750 fineness.'),
    );
    expect(
      find.text('Quote date 2026/10/13, rate at 750 fineness.'),
      findsOneWidget,
    );
  });

  testWidgets('a month-old estimate names its saved day on the shared label', (
    tester,
  ) async {
    final longAgo = DateTime.now().subtract(const Duration(days: 40));
    final stored = DateTime(longAgo.year, longAgo.month, longAgo.day);
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', 'q1', {
      ...quoteOf('q1').toRecord(),
      'savedAt': stored.toIso8601String(),
    });
    await tester.pumpWidget(
      host(GoldQuotesPage(store: store, showRials: false)),
    );
    await tester.pumpAndSettle();

    // Thirty days is where a count stops reading; from there the absolute
    // day itself shows, through the shared label. The row carries more after
    // the day, so the match is on the sentence's opening.
    final day = nexDisplayDate(stored, solar: false, persian: false);
    expect(find.textContaining('Saved on $day'), findsOneWidget);
  });

  testWidgets('a stored day that is not a date shows its stored text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) =>
              Text(goldStoredDateLabel(context, 'not a date')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('not a date'), findsOneWidget);
  });
}
