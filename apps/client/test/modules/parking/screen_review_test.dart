import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_parking_capture_');
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
          final store = NexModuleStore(harness.services, 'parking');
          final now = DateTime.now();
          await store.put('session', 's1', {
            'v': 1,
            'vehicle': persian ? 'خودرو' : 'Car',
            'place': persian ? 'پارکینگ صبا' : 'Saba parking',
            'floor': '−1',
            'spot': 'B12',
            'landmark': persian ? 'کنار آسانسور' : 'By the elevator',
            'startedAt': now
                .subtract(const Duration(minutes: 42))
                .toUtc()
                .toIso8601String(),
            'expiresAt': now
                .add(const Duration(minutes: 78))
                .toUtc()
                .toIso8601String(),
          });
          await store.put('place', 'p1', {
            'v': 1,
            'place': persian ? 'پارکینگ صبا' : 'Saba parking',
            'floor': '−1',
            'spot': 'B12',
            'useCount': 4,
          });
          await store.put('session', 's2', {
            'v': 1,
            'vehicle': persian ? 'خودرو' : 'Car',
            'place': persian ? 'کتابخانه' : 'Library',
            'startedAt': now
                .subtract(const Duration(days: 1, hours: 2))
                .toUtc()
                .toIso8601String(),
            'foundAt': now
                .subtract(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
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
                home: ParkingScreen(store: store),
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
                '${dir.path}/parking_${persian ? 'fa_dark' : 'en_light'}.png',
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
