import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_lent_borrowed_capture_');
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
        final store = NexModuleStore(harness.services, 'lent_borrowed');
        final now = DateTime.now();
        String key(int offset) {
          final day = DateTime(now.year, now.month, now.day + offset);
          return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        }

        await store.put('loan', 'l1', {
          'person': persian ? 'سارا' : 'Sara',
          'direction': 'lent',
          'type': 'money',
          'amount': 12500,
          'currency': 'USD',
          'currencyDecimals': 2,
          'issued': key(-10),
          'due': key(-1),
          'note': '',
        });
        await store.put('return', 'r1', {
          'loan': 'l1',
          'amount': 2500,
          'date': key(-2),
        });
        await store.put('loan', 'l2', {
          'person': persian ? 'علی' : 'Ali',
          'direction': 'lent',
          'type': 'item',
          'amount': 1,
          'what': persian ? 'کوله‌پشتی آبی' : 'Blue backpack',
          'issued': key(-3),
          'due': key(2),
          'note': '',
        });
        await store.put('loan', 'l3', {
          'person': persian ? 'رضا' : 'Reza',
          'direction': 'lent',
          'type': 'money',
          'amount': 500000,
          'issued': key(-20),
          'due': null,
          'note': '',
        });
        await store.put('return', 'r3', {
          'loan': 'l3',
          'amount': 500000,
          'date': key(-1),
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
              home: LoansScreen(store: store),
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
              '${dir.path}/lent_borrowed_${persian ? 'fa_dark' : 'en_light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
