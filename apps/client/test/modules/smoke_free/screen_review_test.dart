import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_smoke_free_capture_');
  });
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    testWidgets(
      'actual main screen in ${persian ? 'Persian dark' : 'English light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = NexModuleStore(harness.services, 'smoke_free');
        final now = DateTime.now();
        await store.put('quit', 'q', {
          'startedAt': DateTime(
            now.year,
            now.month,
            now.day - 14,
          ).toIso8601String(),
          'cigarettesPerDay': 10,
          'pricePerPackMinor': 650,
          'currency': 'USD',
          'currencyDecimals': 2,
          'perPack': 20,
          'endedAt': null,
        });
        await store.put('craving', 'c1', {
          'at': now.toIso8601String(),
          'intensity': 2,
          'triggers': ['coffee'],
          'coping': 'walk',
          'note': persian ? 'بعد از چای' : 'After tea',
        });
        await store.put('craving', 'c2', {
          'at': DateTime(now.year, now.month, now.day - 1).toIso8601String(),
          'intensity': 1,
          'triggers': ['coffee'],
          'coping': 'water',
          'note': '',
        });
        final boundary = GlobalKey();
        await tester.runAsync(() async {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          final inter = FontLoader('Inter')
            ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
          final vazir = FontLoader('Vazirmatn')
            ..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
          await inter.load();
          await vazir.load();
        });
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(persian ? 'fa' : 'en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: persian
                  ? nexDarkTheme(fontFamily: 'Vazirmatn')
                  : nexLightTheme(fontFamily: 'Inter'),
              home: SmokeFreeScreen(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('NEX_CAPTURE');
        if (output.isNotEmpty) {
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
              '${dir.path}/smoke_free_${persian ? 'fa_dark' : 'en_light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
