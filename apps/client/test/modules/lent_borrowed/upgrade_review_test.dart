import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/cards_screen.dart';
import 'package:nex_client/modules/lent_borrowed/split_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/splits_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The upgrade's screens — splits, their settle-up, and the card book — in
/// Persian dark and English light. Set `NEX_CAPTURE` to a folder to write the
/// PNGs; otherwise the test only checks that each screen paints cleanly.
void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_lent_upgrade_capture_');
  });
  tearDown(() => harness.dispose());

  for (final persian in [true, false]) {
    testWidgets(
      'the upgrade in ${persian ? 'Persian dark' : 'English light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = NexModuleStore(harness.services, 'lent_borrowed');
        final ali = persian ? 'علی' : 'Ali';
        final sara = persian ? 'سارا' : 'Sara';
        final reza = persian ? 'رضا' : 'Reza';
        await store.put('split', 's1', {
          'v': 1,
          'title': persian ? 'سفر آخر هفته' : 'The weekend trip',
          'date': '2026-11-01',
          'me': ali,
          'people': [ali, sara, reza],
          'costs': [
            {
              'id': 'c1',
              'title': persian ? 'شام' : 'Dinner',
              'amount': 9000000,
              'payer': sara,
              'mode': 'equal',
              'parts': {ali: 0, sara: 0, reza: 0},
            },
            {
              'id': 'c2',
              'title': persian ? 'تاکسی' : 'Taxi',
              'amount': 3000000,
              'payer': ali,
              'mode': 'shares',
              'parts': {ali: 1, sara: 2, reza: 1},
            },
          ],
        });
        await store.put('split', 's2', {
          'v': 1,
          'title': persian ? 'ماه مشترک' : 'Shared month',
          'date': '2026-10-01',
          'me': ali,
          'people': [ali, sara],
          'costs': [
            {
              'id': 'c3',
              'title': persian ? 'اینترنت' : 'Internet',
              'amount': 4000000,
              'payer': ali,
              'mode': 'equal',
              'parts': {ali: 0, sara: 0},
            },
          ],
        });
        await store.put('card', 'sara', {
          'v': 1,
          'person': sara,
          'holder': persian ? 'سارا احمدی' : 'Sara Ahmadi',
          'card': '6037991234567893',
          'iban': 'IR820540102680020817909002',
        });

        final boundary = GlobalKey();
        await tester.runAsync(() async {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          final inter = FontLoader('Inter')
            ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
          final vazir = FontLoader('Vazirmatn')
            ..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
          await icons.load();
          await inter.load();
          await vazir.load();
        });
        const output = String.fromEnvironment('NEX_CAPTURE');
        Future<void> capture(String name) async {
          if (output.isEmpty) return;
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

        Future<void> show(Widget home) async {
          // A fresh tree each time: a MaterialApp kept across pumps would keep
          // its Navigator, and a pushed screen would still be on top when the
          // next "home" is captured.
          await tester.pumpWidget(const SizedBox());
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
                home: home,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        final lang = persian ? 'fa_dark' : 'en_light';
        await show(SplitsScreen(store: store));
        await capture('lent_upgrade_${lang}_1_splits');

        await tester.tap(find.byKey(const ValueKey('split-s1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('lent_upgrade_${lang}_2_split_detail');

        await show(CardsScreen(store: store));
        await capture('lent_upgrade_${lang}_3_cards');

        await tester.pumpWidget(const SizedBox());
        expect(SplitDetailScreen, isNotNull);
      },
    );
  }
}
