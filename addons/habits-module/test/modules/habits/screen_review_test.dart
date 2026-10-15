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
    testWidgets(
      'actual main screen in ${persian ? 'Persian dark' : 'English light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = NexModuleStore(harness.services, 'habits');
        final today = DateTime.now();
        for (final entry in [
          ('h1', persian ? 'کشش صبحگاهی' : 'Morning stretch', false, 1),
          ('h2', persian ? 'پیاده‌روی' : 'A short walk', true, 3),
          ('h3', persian ? 'مطالعه' : 'Read a few pages', false, 1),
        ]) {
          await store.put('habit', entry.$1, {
            'name': entry.$2,
            'note': '',
            'schedule': entry.$3 ? 'weekly' : 'daily',
            'target': entry.$4,
            'archived': false,
            'createdAt': today.toIso8601String(),
          });
          for (var n = entry.$1 == 'h3' ? 1 : 0; n < 3; n++) {
            final day = DateTime(today.year, today.month, today.day - n);
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            await store.put('check', '${entry.$1}:$key', {
              'habit': entry.$1,
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
              theme: persian
                  ? nexDarkTheme(fontFamily: 'Vazirmatn')
                  : nexLightTheme(fontFamily: 'Inter'),
              home: HabitsScreen(store: store),
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
              '${dir.path}/habits_${persian ? 'fa_dark' : 'en_light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
