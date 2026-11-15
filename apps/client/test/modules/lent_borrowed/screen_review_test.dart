import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/lent_borrowed/people_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The module's screens as they render, in Persian dark and English light —
/// the two the design review is done in. Set `NEX_CAPTURE` to a folder and
/// run this file to write the PNGs; without it the test only checks that
/// every screen paints without an exception.
void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_lent_borrowed_capture_');
  });
  tearDown(() => harness.dispose());

  for (final persian in [true, false]) {
    testWidgets('the module in ${persian ? 'Persian dark' : 'English light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = NexModuleStore(harness.services, 'lent_borrowed');
      final now = DateTime.now();
      String key(int offset) {
        final day = DateTime(now.year, now.month, now.day + offset);
        return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
      }

      const p = 'سارا';
      const a = 'علی';
      await store.put('loan', 'l1', {
        'person': persian ? p : 'Sara',
        'direction': 'lent',
        'type': 'money',
        'amount': 12500000,
        'currency': 'EUR',
        'currencyDecimals': 2,
        'issued': key(-10),
        'due': key(-1),
        'note': persian ? 'بلیت قطار' : 'Train tickets',
      });
      await store.put('return', 'r1', {
        'loan': 'l1',
        'amount': 2500000,
        'date': key(-2),
      });
      await store.put('loan', 'l2', {
        'person': persian ? a : 'Ali',
        'direction': 'lent',
        'type': 'money',
        'amount': 120000001,
        'currency': 'IRR',
        'currencyDecimals': 0,
        'issued': key(-3),
        'due': key(2),
        'note': '',
      });
      await store.put('loan', 'l3', {
        'person': persian ? a : 'Ali',
        'direction': 'lent',
        'type': 'item',
        'amount': 1,
        'what': persian ? 'کوله‌پشتی آبی' : 'Blue backpack',
        'issued': key(-3),
        'due': key(2),
        'note': '',
      });
      await store.put('loan', 'l4', {
        'person': persian ? 'رضا' : 'Reza',
        'direction': 'lent',
        'type': 'money',
        'amount': 5000000,
        'currency': 'IRR',
        'currencyDecimals': 0,
        'issued': key(-20),
        'due': null,
        'note': '',
      });
      await store.put('return', 'r4', {
        'loan': 'l4',
        'amount': 5000000,
        'date': key(-1),
      });
      await store.put('loan', 'l5', {
        'person': persian ? 'مریم' : 'Maryam',
        'direction': 'borrowed',
        'type': 'money',
        'amount': 30000000,
        'currency': 'IRR',
        'currencyDecimals': 0,
        'issued': key(-5),
        'due': key(5),
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
            home: LoansScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      const output = String.fromEnvironment('NEX_CAPTURE');
      Future<void> capture(String name) async {
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

      final lang = persian ? 'fa_dark' : 'en_light';
      await capture('lent_borrowed_${lang}_1_list');

      // The editor: the amount with the same amount in words under it.
      await tester.tap(find.byKey(const ValueKey('loans-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-person')),
        persian ? 'حسین' : 'Hossein',
      );
      await tester.enterText(
        find.byKey(const ValueKey('loan-field-amount')),
        '1200000',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lent_borrowed_${lang}_2_editor');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // The detail page of an outstanding loan: words under the total, a
      // partly returned balance, the reminder and its privacy switch.
      await tester.tap(find.text(persian ? 'علی' : 'Ali').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lent_borrowed_${lang}_3_detail');

      // The message sheet: three tones, copy one tap away.
      final message = find.byKey(const ValueKey('loan-message'));
      await tester.dragUntilVisible(
        message,
        find.byKey(const ValueKey('loan-detail-body')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.tap(message);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lent_borrowed_${lang}_4_message');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // The people page, per currency and per direction.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('loans-people')));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lent_borrowed_${lang}_5_people');

      // One person's page.
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('lent_borrowed_${lang}_6_person');

      await tester.pumpWidget(const SizedBox());
      expect(LoanDetailScreen, isNotNull);
      expect(PeopleScreen, isNotNull);
    });
  }
}
