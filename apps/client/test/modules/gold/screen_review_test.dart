import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/modules/gold/gold_models.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_gold_capture_');
  });
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    for (final compact in [false, true]) {
      testWidgets(
        'actual main screen in ${persian ? 'Persian dark' : 'English light'}, compact:$compact',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(320, 480)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = NexModuleStore(harness.services, 'gold');
          final fixture = GoldQuote.fromRecord('fixture', {
            'schema': 2,
            'title': persian ? 'گردنبند ساده' : 'Simple necklace',
            'shop': persian ? 'فروشگاه نمونه' : 'Example shop',
            'weightMg': 2350,
            'grossWeightMg': 2700,
            'finenessPpt': 750,
            'rateCentiPerG': 850000000,
            'rateRefPpt': 750,
            'makingPercentBp': 1200,
            'profitBp': 700,
            'vatBp': 1000,
            'quoteDate': '2026-10-13',
          });
          final boundary = GlobalKey();
          await tester.runAsync(() async {
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
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(persian ? 'fa' : 'en'),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(compact ? 2 : 1),
                    disableAnimations: compact,
                  ),
                  child: child!,
                ),

                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: persian
                    ? nexDarkTheme(fontFamily: 'Vazirmatn')
                    : nexLightTheme(fontFamily: 'Inter'),
                home: GoldScreen(store: store, editing: fixture),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          const output = String.fromEnvironment('NEX_CAPTURE');
          if (output.isNotEmpty && !compact) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(output)..createSync(recursive: true);
              await File(
                '${dir.path}/gold_${persian ? 'fa_dark' : 'en_light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
