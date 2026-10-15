import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import 'package:nex_client/modules/smoke_free/module.dart';

import '../../support/nex_harness.dart';

/// The smoke-free screen in Persian right-to-left and English left-to-right,
/// light and dark, at text scale 2.0, and with animations off: nothing
/// overflows, numbers come out in the locale's digits, and the money reads
/// with Persian separators.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_smoke_l10n_'),
  );
  tearDown(() => harness.dispose());

  Future<NexModuleStore> seed() async {
    final store = NexModuleStore(harness.services, 'smoke_free');
    await store.put('quit', 'q1', {
      'startedAt': DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String(),
      'cigarettesPerDay': 10,
      'pricePerPackRials': 200000,
      'perPack': 20,
      'endedAt': null,
      'endedWhy': null,
    });
    return store;
  }

  Future<void> pump(
    WidgetTester tester, {
    required NexModuleStore store,
    required Locale locale,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) async {
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
        home: SmokeFreeScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull, reason: 'no overflow anywhere');
  }

  group('Persian, right to left', () {
    testWidgets('light, with Persian digits and separators', (tester) async {
      final store = await seed();
      await pump(tester, store: store, locale: const Locale('fa'));
      expect(
        (find.byType(Directionality).evaluate().single.widget as Directionality)
            .textDirection,
        TextDirection.rtl,
      );
      expect(find.text('۵ روز بدون سیگار'), findsOneWidget);
      expect(find.text('حدود ۵۰ سیگار نکشیده شده'), findsOneWidget);
      expect(
        find.text('حدود ۵۰۰٬۰۰۰ \u2066IRR\u2069 صرفه‌جویی'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('dark, at text scale 2.0', (tester) async {
      final store = await seed();
      await pump(
        tester,
        store: store,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(find.text('۵ روز بدون سیگار'), findsOneWidget);
      expect(
        find.text('حدود ۵۰۰٬۰۰۰ \u2066IRR\u2069 صرفه‌جویی'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('the empty state, dark and large', (tester) async {
      final store = NexModuleStore(harness.services, 'smoke_free');
      await pump(
        tester,
        store: store,
        locale: const Locale('fa'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(find.text('تلاشی در جریان نیست.'), findsOneWidget);
      expect(find.text('شروعِ بدون سیگار'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('English, left to right', () {
    testWidgets('light', (tester) async {
      final store = await seed();
      await pump(tester, store: store, locale: const Locale('en'));
      expect(
        (find.byType(Directionality).evaluate().single.widget as Directionality)
            .textDirection,
        TextDirection.ltr,
      );
      expect(find.text('Smoke-free for 5 days'), findsOneWidget);
      expect(find.text('≈ 500,000 \u2066IRR\u2069 kept'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('dark, at text scale 2.0', (tester) async {
      final store = await seed();
      await pump(
        tester,
        store: store,
        locale: const Locale('en'),
        brightness: Brightness.dark,
        textScale: 2.0,
      );
      expect(find.text('Smoke-free for 5 days'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('with animations off, everything settles at once', (
      tester,
    ) async {
      final store = await seed();
      await pump(
        tester,
        store: store,
        locale: const Locale('en'),
        disableAnimations: true,
      );
      await tester.tap(find.byKey(const ValueKey('smoke-log-craving')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('craving-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save, findsOneWidget);
      // Cancelled the way a person would: the sheet's own cancel button.
      final cancel = find.text('Cancel');
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('craving-save')), findsNothing);
      expectNoOverflow(tester);
    });
  });

  testWidgets('the module’s own words are complete in both languages', (
    tester,
  ) async {
    expect(smokeFreeStrings.en.keys.toSet(), smokeFreeStrings.fa.keys.toSet());
    for (final value in smokeFreeStrings.fa.values) {
      expect(value.trim(), isNotEmpty);
    }
    expect(
      smokeFreeStrings.text(
        lookupAppLocalizations(const Locale('fa')),
        'smokeFreeFor',
        {'days': 5},
      ),
      '۵ روز بدون سیگار',
    );
  });
}
