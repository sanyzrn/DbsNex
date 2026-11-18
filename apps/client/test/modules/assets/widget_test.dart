import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/assets/model.dart';
import 'package:nex_client/modules/assets/screen.dart';

import '../../support/nex_harness.dart';
import 'fixtures.dart';

void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late List<bool> secure;
  late bool deny;
  const channel = MethodChannel('nex/os_capture');
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_assets_');
    store = NexModuleStore(harness.services, 'assets');
    secure = [];
    deny = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final on = (call.arguments as Map)['on'] as bool;
          secure.add(on);
          if (deny && on) throw PlatformException(code: 'test-fail');
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
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
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

  Future<void> seed({bool fa = false}) async {
    final day = civilDay(DateTime.now());
    final old = day.subtract(const Duration(days: 18));
    await store.put('holding', 'gold', {
      'v': 1,
      ...holdingBody(
        AssetMarket.gold,
        5400,
        old,
        price: 75000000,
        fineness: 750,
        location: fa ? 'محل دلخواه' : 'My storage',
      ),
    });
    await store.put('holding', 'usd', {
      'v': 1,
      ...holdingBody(AssetMarket.usd, 45000, old, price: 600000),
    });
    await store.put('quote', 'gold1', {
      'v': 1,
      ...quoteBody(AssetMarket.gold, 95000000, day),
    });
    await store.put('quote', 'gold2', {
      'v': 1,
      ...quoteBody(AssetMarket.gold, 91000000, old),
    });
    await store.put('quote', 'usd1', {
      'v': 1,
      ...quoteBody(AssetMarket.usd, 700000, day),
    });
    await store.put('goal', 'goal1', {
      'v': 1,
      'targetMg': 10000,
      'title': fa ? 'طلای پس‌انداز' : 'Gold savings',
    });
  }

  testWidgets(
    'secure surface stays acquired while masked and closes on disposal',
    (t) async {
      await seed();
      await show(t);
      expect(secure, [true]);
      expect(find.text('Estimated value'), findsNothing);
      await tap(t, find.text('Reveal holdings'));
      expect(find.text('82,800,000 tomans'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pumpAndSettle();
      expect(find.text('82,800,000 tomans'), findsNothing);
      expect(find.text('Reveal holdings'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(const SizedBox());
      expect(secure, [true, false]);
    },
  );

  testWidgets(
    'failed Android capture protection does not reveal data and can retry',
    (t) async {
      await seed();
      deny = true;
      await show(t);
      expect(find.text('Reveal holdings'), findsNothing);
      expect(secure, [true, false]);
      deny = false;
      await tap(t, find.text('Retry'));
      await tap(t, find.text('Reveal holdings'));
      expect(find.text('82,800,000 tomans'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      expect(secure, [true, false, true, false]);
    },
  );

  testWidgets(
    'editor resumes a draft and saves Persian quantities and whole rial cost',
    (t) async {
      await show(t);
      await tap(t, find.text('Reveal holdings'));
      await tap(t, find.text('Add holding'));
      await t.enterText(find.byType(TextField).first, '۲٫۵');
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pumpAndSettle();
      await tap(t, find.text('Add holding'));
      final input = t.widget<TextField>(find.byType(TextField).first);
      expect(input.controller!.text, '۲٫۵');
      await t.enterText(find.byType(TextField).at(2), '۱۲٫۳۴');
      await tap(t, find.text('Save'));
      expect(await store.list('holding'), isEmpty);
      expect(
        find.text('Check the amount and required fields.'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField).at(2), '۵۰۰۰۰');
      await tap(t, find.text('Save'));
      final row = (await store.list('holding')).single;
      expect(row.body['quantity'], 2500);
      expect(row.body['costPerUnitRial'], 500000);
      expect(await store.list('draft'), isEmpty);
    },
  );

  testWidgets(
    'adding a price keeps older observations and changing price updates value',
    (t) async {
      await seed();
      await show(t);
      await tap(t, find.text('Reveal holdings'));
      await tap(t, find.text('Prices'));
      await tap(t, find.text('Record price'));
      await t.enterText(find.byType(TextField).first, '10000000');
      await tap(t, find.text('Save'));
      final quotes = await store.list('quote');
      expect(quotes, hasLength(4));
      expect(
        quotes.where((q) => q.body['unitRial'] == 100000000),
        hasLength(1),
      );
      await tap(t, find.text('Holdings'));
      expect(find.text('85,500,000 tomans'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting the last observation falls back and Undo restores the exact body',
    (t) async {
      await seed();
      final old = (await store.get('quote', 'gold1'))!;
      final raw = {
        ...old,
        'extension': {'origin': 'future'},
      };
      await store.put('quote', 'gold1', raw);
      await show(t);
      await tap(t, find.text('Reveal holdings'));
      await tap(t, find.text('Prices'));
      await tap(t, find.byType(NexPopupMenuButton<String>).first);
      await tap(t, find.text('Delete'));
      await tap(t, find.text('Delete'));
      expect(await store.get('quote', 'gold1'), isNull);
      expect(find.text('9,100,000 tomans'), findsNWidgets(2));
      await tap(t, find.text('Undo'));
      expect(await store.get('quote', 'gold1'), raw);
      expect(find.text('9,500,000 tomans'), findsNWidgets(2));
    },
  );

  testWidgets(
    'leaving the app covers an open editor and restores it only on reveal',
    (t) async {
      await show(t);
      await tap(t, find.text('Reveal holdings'));
      await tap(t, find.text('Add holding'));
      await t.enterText(find.byType(TextField).first, '7.125');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      await tap(t, find.text('Reveal holdings').last);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '7.125',
      );
    },
  );

  testWidgets(
    'foreign holding saves its selected code and minor-unit quantity',
    (t) async {
      await show(t);
      await tap(t, find.text('Reveal holdings'));
      await tap(t, find.text('Add holding'));
      await tap(t, find.text('Gold'));
      await tap(t, find.text('Currency').last);
      await tap(t, find.text('US dollar (USD)'));
      await tap(t, find.text('Euro (EUR)').last);
      await t.enterText(find.byType(TextField).first, '25.75');
      await t.enterText(find.byType(TextField).at(1), '120000');
      await tap(t, find.text('Save'));
      final row = (await store.list('holding')).single;
      expect(row.body['currency'], 'EUR');
      expect(row.body['amount'], 2575);
      expect(row.body['costPerUnitRial'], 1200000);
    },
  );

  for (final fa in [false, true]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets('tabs and secure mask fa:$fa dark:$dark compact:$compact', (
          t,
        ) async {
          const output = String.fromEnvironment('NEX_CAPTURE');
          final capture = output.isNotEmpty && fa == dark && !compact;
          if (capture) {
            await t.runAsync(() async {
              for (final (family, font) in [
                ('Inter', 'assets/fonts/Inter-subset.ttf'),
                ('Vazirmatn', 'assets/fonts/VazirmatnVariable.ttf'),
                ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
              ]) {
                await (FontLoader(
                  family,
                )..addFont(rootBundle.load(font))).load();
              }
            });
          }
          await seed(fa: fa);
          await show(t, fa: fa, dark: dark, compact: compact);
          Future<void> image(String page) async {
            if (!capture) return;
            await t.runAsync(() async {
              final boundary = t.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              );
              final img = await boundary.toImage();
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory(output).createSync(recursive: true);
              File('$output/${fa ? 'fa_dark' : 'en_light'}_$page.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }

          await image('private');
          await tap(t, find.text(fa ? 'نمایش دارایی‌ها' : 'Reveal holdings'));
          await image('holdings');
          await tap(t, find.text(fa ? 'قیمت‌ها' : 'Prices').first);
          await image('prices');
          await tap(t, find.text(fa ? 'هدف‌ها' : 'Goals').first);
          final progress = find.text(fa ? '۵٫۴ از ۱۰ گرم' : '5.4 of 10 g');
          if (compact) {
            await t.scrollUntilVisible(progress, 160);
            await t.pumpAndSettle();
          }
          expect(progress, findsOneWidget);
          await image('goals');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
