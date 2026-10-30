import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_habits_capture_');
  });
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    for (final dark in [true, false]) {
    testWidgets(
      'habit flows ${persian ? 'fa' : 'en'} ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = NexModuleStore(harness.services, 'habits');
        final today = DateTime.now();
        for (final entry in [
          ('h1', persian ? 'آب خوردن' : 'Drink water', false, 1),
          ('h2', persian ? 'پیاده‌روی' : 'A short walk', true, 3),
          ('h3', persian ? 'مطالعه' : 'Read a few pages', false, 1),
        ]) {
          await store.put('habit', entry.$1, {
            'name': entry.$2,
            'note': '',
            'schedule': entry.$3 ? 'weekly' : 'daily',
            'target': entry.$4,
            'archived': false,
            'goal': entry.$1 == 'h1' ? 8 : 1,
            'unit': entry.$1 == 'h1' ? (persian ? 'لیوان' : 'glasses') : '',
            'icon': entry.$1 == 'h1' ? 'water' : 'book',
            'hue': entry.$1 == 'h1' ? 5 : 1,
            'createdAt': today.toIso8601String(),
          });
          for (var n = entry.$1 == 'h3' ? 1 : 0; n < 3; n++) {
            final day = DateTime(today.year, today.month, today.day - n);
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            await store.put('check', '${entry.$1}:$key', {
              'habit': entry.$1,
              if (entry.$1 == 'h1') 'amount': n == 0 ? 5 : 8,
              'date': key,
              'at': day.toIso8601String(),
            });
          }
        }
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
              theme: dark
                  ? nexDarkTheme(fontFamily: persian ? 'Vazirmatn' : 'Inter')
                  : nexLightTheme(fontFamily: persian ? 'Vazirmatn' : 'Inter'),
              home: HabitsScreen(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Future<void> capture(String scene) async {
          expect(tester.takeException(), isNull, reason: scene);
          const output = String.fromEnvironment('NEX_CAPTURE');
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary).toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory(output)..createSync(recursive: true);
            await File('${dir.path}/habits_${persian ? 'fa' : 'en'}_${dark ? 'dark' : 'light'}_$scene.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await capture('today');
        final open = find.byKey(const ValueKey('habit-open-h1'));
        await tester.scrollUntilVisible(open, 150, scrollable: find.byType(Scrollable).first);
        await tester.tap(open);
        await tester.pumpAndSettle();
        await capture('detail');
        final amount = find.byKey(const ValueKey('habit-toggle-h1'));
        await tester.ensureVisible(amount);
        await tester.tap(amount);
        await tester.pumpAndSettle();
        await capture('amount');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        final calendar = find.byKey(const ValueKey('habit-month-title'));
        await tester.scrollUntilVisible(calendar, 200, scrollable: find.byType(Scrollable).first);
        await capture('calendar');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('habits-new')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('habit-template-water')));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await capture('editor');
        await tester.pumpWidget(const SizedBox());
      },
    );
    }
  }
}

