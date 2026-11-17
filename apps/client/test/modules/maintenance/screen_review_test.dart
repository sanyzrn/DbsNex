import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/maintenance_screen.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_maintenance_capture_');
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
          final store = NexModuleStore(harness.services, 'maintenance');
          final now = DateTime.now();
          await store.put('asset', 'car', {
            'nickname': persian ? 'خودروی روزانه' : 'Daily car',
            'type': 'car',
            'meterKind': 'distance',
            'distanceUnit': 'km',
            'insuranceExpiresAt': now
                .add(const Duration(days: 23))
                .toIso8601String(),
            'inspectionExpiresAt': now
                .add(const Duration(days: 5))
                .toIso8601String(),
            'archived': false,
          });
          await store.put('fuel_rate', 'quota', {
            'assetId': 'car',
            'name': persian ? 'سهمیه' : 'Quota',
            'quota': 60000,
          });
          await store.put('fuel_rate', 'free', {
            'assetId': 'car',
            'name': persian ? 'آزاد' : 'Free',
            'quota': 0,
          });
          await store.put('fuel', 'fill', {
            'assetId': 'car',
            'date': now.toIso8601String(),
            'litres': 42500,
            'priceRial': 1275000,
            'rate': persian ? 'سهمیه' : 'Quota',
          });
          await store.put('event', 'oil', {
            'assetId': 'car',
            'task': persian ? 'تعویض روغن' : 'Oil change',
            'date': now.subtract(const Duration(days: 70)).toIso8601String(),
            'meter': 45000,
            'meterUnit': 'km',
            'cost': 8500,
            'currency': 'USD',
          });
          await store.put('rule', 'oil-rule', {
            'assetId': 'car',
            'task': persian ? 'تعویض روغن' : 'Oil change',
            'months': 6,
            'meters': 5000,
            'meterUnit': 'km',
          });
          await store.put('reading', 'current', {
            'assetId': 'car',
            'value': 50125500,
            'scale': 1000,
            'meterKind': 'distance',
            'unit': 'km',
            'at': now.toUtc().toIso8601String(),
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
                home: MaintenanceScreen(store: store),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          const output = String.fromEnvironment('NEX_CAPTURE');
          Future<void> capture(String name) async {
            if (output.isEmpty || compact) return;
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(output)..createSync(recursive: true);
              await File('${dir.path}/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          final lang = persian ? 'fa_dark' : 'en_light';
          await capture('maintenance_$lang');
          if (!compact &&
              find
                  .text(persian ? 'خودروی روزانه' : 'Daily car')
                  .evaluate()
                  .isNotEmpty) {
            await tester.tap(
              find.text(persian ? 'خودروی روزانه' : 'Daily car'),
            );
            await tester.pumpAndSettle();
            await capture('maintenance_${lang}_car');
            // The fuel section is below the car and interval panels.
            final page = find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.drag(page, const Offset(0, -600));
            await tester.pumpAndSettle();
            await capture('maintenance_${lang}_car_fuel');
            final add = find.byKey(const ValueKey('maintenance-fuel-add'));
            if (add.evaluate().isNotEmpty) {
              await tester.tap(add);
              await tester.pumpAndSettle();
              await capture('maintenance_${lang}_fuel_sheet');
            }
          }
          if (compact) {
            await tester.tap(
              find.byKey(const ValueKey('maintenance-add-asset')),
            );
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const ValueKey('maintenance-nickname')),
              persian ? '۱۲٫۵' : '12.5',
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
