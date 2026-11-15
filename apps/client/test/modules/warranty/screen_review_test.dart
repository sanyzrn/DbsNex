import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_detail.dart';
import 'package:nex_client/modules/warranty/warranty_editor.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';

import '../../support/nex_harness.dart';

/// Renders the module's three screens with realistic Persian and English
/// data, and — when `--dart-define=NEX_CAPTURE=<dir>` is given — writes
/// them out for a visual review at the pull-request stage. Without the
/// define it is an ordinary layout test: nothing overflows and nothing
/// throws.
void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_warranty_capture_');
  });
  tearDown(() => harness.dispose());

  Future<void> loadFonts(WidgetTester tester) => tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
    final vazir = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await inter.load();
    await vazir.load();
  });

  /// Three purchases and one claim: one comfortable, one ending in five
  /// days, one ended, plus the company, card and registry a service desk
  /// asks about.
  Future<ModuleRecord> seed({required bool persian}) async {
    final store = NexModuleStore(harness.services, 'warranty');
    final now = DateTime.now();
    for (final entry in [
      ('w1', persian ? 'گوشی سامسونگ' : 'Samsung phone', 365),
      ('w2', persian ? 'هدفون' : 'Headphones', 5),
      ('w3', persian ? 'کیبورد' : 'Keyboard', -12),
    ]) {
      await store.put('warranty', entry.$1, {
        'v': 2,
        'product': entry.$2,
        'brand': persian ? 'برند نمونه' : 'Example brand',
        'company': persian ? 'همراه طلایی' : 'Hamrah Talaei',
        'supportPhone': '021-91001234',
        'cardNumber': 'C-7788',
        'coverKind': 'company',
        'registryOwner': 'mine',
        'merchant': persian ? 'فروشگاه رضایی' : 'Rezaei store',
        'receiptRef': 'INV-1403-8821',
        'purchasedAt': now
            .subtract(Duration(days: 365 - entry.$3))
            .toIso8601String(),
        'coverageEnd': now.add(Duration(days: entry.$3)).toIso8601String(),
        'durationMonths': 18,
        'amountRials': 320000000,
      });
    }
    await store.put('claim', 'c1', {
      'v': 1,
      'warrantyId': 'w1',
      'kind': 'claim',
      'note': persian
          ? 'صفحه نمایش خط افتاده؛ به نمایندگی زنگ زدم.'
          : 'Screen has a line; called the service centre.',
      'at': now.subtract(const Duration(days: 40)).toUtc().toIso8601String(),
    });
    return (await store.list('warranty')).first;
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    const output = String.fromEnvironment('NEX_CAPTURE');
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(output)..createSync(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Widget app(
    Widget home, {
    required bool persian,
    double scale = 1,
    bool animations = true,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(persian ? 'fa' : 'en'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: !animations,
      ),
      child: child!,
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: persian
        ? nexDarkTheme(fontFamily: 'Vazirmatn')
        : nexLightTheme(fontFamily: 'Inter'),
    home: home,
  );

  for (final persian in [true, false]) {
    for (final compact in [false, true]) {
      testWidgets(
        'the list in ${persian ? 'Persian dark' : 'English light'}, compact:$compact',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(320, 480)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadFonts(tester);
          await seed(persian: persian);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: app(
                WarrantyScreen(
                  store: NexModuleStore(harness.services, 'warranty'),
                ),
                persian: persian,
                scale: compact ? 2 : 1,
                animations: !compact,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (!compact) {
            await capture(
              tester,
              boundary,
              'list_${persian ? 'fa_dark' : 'en_light'}',
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('the purchase page in ${persian ? 'Persian' : 'English'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadFonts(tester);
      final record = await seed(persian: persian);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: app(
            WarrantyDetailPage(
              store: NexModuleStore(harness.services, 'warranty'),
              record: record,
            ),
            persian: persian,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        boundary,
        'detail_${persian ? 'fa_dark' : 'en_light'}',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the editor in ${persian ? 'Persian' : 'English'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadFonts(tester);
      await seed(persian: persian);
      final record = (await NexModuleStore(
        harness.services,
        'warranty',
      ).list('warranty')).first;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: app(
            Scaffold(
              body: WarrantyEditorSheet(
                store: NexModuleStore(harness.services, 'warranty'),
                existing: record,
              ),
            ),
            persian: persian,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        boundary,
        'editor_${persian ? 'fa_dark' : 'en_light'}',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
