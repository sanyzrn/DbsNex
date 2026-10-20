import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/module.dart';

import '../../support/nex_harness.dart';

/// The lent & borrowed screen in Persian right-to-left and English
/// left-to-right, light and dark, at text scale 2.0, and with animations
/// off: nothing overflows, and the money comes out in Persian digits with
/// Persian separators.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_l10n_'),
  );
  tearDown(() => harness.dispose());

  Future<void> seed() async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    await store.put('loan', 'l1', {
      'direction': 'lent',
      'person': 'علی',
      'type': 'money',
      'amount': 500000,
      'what': '',
      'issued': civilDateKey(DateTime.now()),
      'due': civilDateKey(DateTime.now().add(const Duration(days: 7))),
      'note': '',
    });
    await store.put('loan', 'l2', {
      'direction': 'borrowed',
      'person': 'سارا',
      'type': 'money',
      'amount': 200000,
      'what': '',
      'issued': civilDateKey(DateTime.now()),
      'due': null,
      'note': '',
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) async {
    final store = NexModuleStore(harness.services, 'lent_borrowed');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: LoansScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull, reason: 'no overflow anywhere');
  }

  group('Persian, right to left', () {
    testWidgets('light, with Persian digits and separators', (tester) async {
      await seed();
      await pump(tester, locale: const Locale('fa'));
      expect(
        (find.byType(Directionality).evaluate().first.widget as Directionality)
            .textDirection,
        TextDirection.rtl,
      );
      expect(find.text('قرض و طلب'), findsOneWidget);
      expect(find.text('علی'), findsOneWidget);
      expect(
        find.textContaining('۵۰۰٬۰۰۰ \u2066IRR\u2069 هنوز مانده'),
        findsOneWidget,
      );
      expect(find.text('۷ روز دیگر موعدش است'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the borrowed tab, dark, at text scale 2.0', (tester) async {
      await seed();
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
      await tester.pumpAndSettle();
      expect(find.text('سارا'), findsOneWidget);
      expect(
        find.textContaining('۲۰۰٬۰۰۰ \u2066IRR\u2069 هنوز مانده'),
        findsOneWidget,
      );
      expect(find.text('بدون موعد'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the empty state, dark and large', (tester) async {
      await pump(
        tester,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(
        find.text('چیزی را که قرض داده‌اید ثبت کنید تا برگشتش را پیگیری کنید.'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });
  });

  group('English, left to right', () {
    testWidgets('light', (tester) async {
      await seed();
      await pump(tester, locale: const Locale('en'));
      expect(
        (find.byType(Directionality).evaluate().first.widget as Directionality)
            .textDirection,
        TextDirection.ltr,
      );
      expect(find.text('Lent & borrowed'), findsOneWidget);
      expect(
        find.textContaining('500,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
      expect(find.text('Due in 7 days'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('dark, at text scale 2.0', (tester) async {
      await seed();
      await pump(
        tester,
        locale: const Locale('en'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(
        find.textContaining('500,000 \u2066IRR\u2069 still out'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('with animations off, the new-record sheet settles at once', (
      tester,
    ) async {
      await pump(tester, locale: const Locale('en'), disableAnimations: true);
      await tester.tap(find.byKey(const ValueKey('loans-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('loan-field-person')), findsOneWidget);
      final cancel = find.text('Cancel');
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
    });
  });

  testWidgets('the module’s own words are complete in both languages', (
    tester,
  ) async {
    expect(lentStrings.en.keys.toSet(), lentStrings.fa.keys.toSet());
    for (final value in lentStrings.fa.values) {
      expect(value.trim(), isNotEmpty);
    }
    expect(
      lentStrings.text(
        lookupAppLocalizations(const Locale('fa')),
        'outstanding',
        {'amount': '۵۰۰٬۰۰۰ \u2066IRR\u2069'},
      ),
      '۵۰۰٬۰۰۰ \u2066IRR\u2069 هنوز مانده',
    );
    expect(
      lentStrings.text(lookupAppLocalizations(const Locale('fa')), 'dueIn', {
        'n': 7,
      }),
      '۷ روز دیگر موعدش است',
    );
  });
}
