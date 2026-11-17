import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/medicine_today_page.dart';

import '../../support/nex_harness.dart';

/// The upgraded screens, rendered with the app's real fonts and themes so
/// the review folder shows what a person actually reads. Captures are
/// written only when the capture path is passed in; the same test is a
/// plain render check every other run.
void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_medicine_upgrade_');
  });
  tearDown(() => harness.dispose());

  Future<void> loadFonts() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
    final vazir = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await inter.load();
    await vazir.load();
  }

  Future<void> capture(
    WidgetTester tester,
    Widget home, {
    required bool persian,
    required String name,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.runAsync(loadFonts);
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
    const output = String.fromEnvironment('NEX_CAPTURE');
    if (output.isNotEmpty) {
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
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> seed(NexModuleStore store, {required bool persian}) async {
    await store.put('medicine', 'm1', {
      'v': 3,
      'name': persian ? 'داروی نمونه الف' : 'Example item A',
      'strength': persian ? 'طبق نوشته روی بسته' : 'As written on the pack',
      'package': persian ? 'عدد' : 'units',
      'person': persian ? 'سارا' : 'Sara',
      'quantity': 24,
      'doseUnits': 1,
      'times': ['08:00', '20:00'],
      'weekdays': [1, 3, 5],
      'warnDays': 5,
      'refillThreshold': 4,
      'hardToFind': true,
      'expiresAt': DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day + 3,
      ).toIso8601String(),
      'instructions': persian
          ? 'دستور نوشته‌شده توسط کاربر'
          : 'Instructions entered by the user',
    });
    await store.put('box', 'b1', {
      'v': 1,
      'medicineId': 'm1',
      'expiresAt': MedicineModels.dayText(
        DateTime.now().add(const Duration(days: 20)),
      ),
      'units': 12,
    });
    await store.put('source', 's1', {
      'v': 1,
      'medicineId': 'm1',
      'place': persian ? 'داروخانهٔ سر خیابان' : 'Corner pharmacy',
      'price': 125000,
      'at': MedicineModels.dayText(DateTime.now()),
    });
  }

  for (final persian in [true, false]) {
    testWidgets(
      'detail sheet in ${persian ? 'Persian dark' : 'English light'}',
      (tester) async {
        final store = NexModuleStore(harness.services, 'medicine');
        await seed(store, persian: persian);
        final record = ModuleRecord(
          module: 'medicine',
          kind: 'medicine',
          id: 'm1',
          body: (await store.get('medicine', 'm1'))!,
          updatedAt: DateTime.now(),
        );
        await capture(
          tester,
          Scaffold(
            body: MedicineDetailSheet(store: store, record: record),
          ),
          persian: persian,
          name: 'medicine_detail_${persian ? 'fa_dark' : 'en_light'}',
        );
      },
    );

    testWidgets('today in ${persian ? 'Persian dark' : 'English light'}', (
      tester,
    ) async {
      final store = NexModuleStore(harness.services, 'medicine');
      await seed(store, persian: persian);
      await capture(
        tester,
        MedicineTodayPage(store: store),
        persian: persian,
        name: 'medicine_today_${persian ? 'fa_dark' : 'en_light'}',
      );
    });
  }
}
