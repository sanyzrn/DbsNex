import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/expenses_screen.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The review images: the real home and the real payment editor, rendered in
/// Persian dark and English light (and at 320×480 with 2× text for the
/// layout). Synthetic data, a widget render — not a device screenshot.
void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_expenses_review_');
  });
  tearDown(() => harness.dispose());

  Future<void> seed(NexModuleStore store, {required bool persian}) async {
    final now = DateTime.now();
    final month = NexModuleMonth.of(now, solar: persian);
    Future<void> tx(
      String id,
      String type,
      int amount,
      String cat,
      String note,
    ) => store.put('tx', id, {
      'type': type,
      'amountRial': amount,
      'date': now.toIso8601String(),
      'category': cat,
      'note': note,
    });
    await tx(
      't1',
      'expense',
      2850000,
      'cat-groceries',
      persian ? 'خرید هفتگی' : 'Weekly shop',
    );
    await tx(
      't2',
      'expense',
      120000000,
      'cat-rent',
      persian ? 'اجاره' : 'Rent',
    );
    await tx(
      't3',
      'expense',
      4500000,
      'cat-bills',
      persian ? 'اینترنت' : 'Internet',
    );
    await tx(
      't4',
      'income',
      250000000,
      'cat-salary',
      persian ? 'حقوق' : 'Salary',
    );
    await store.put('budget', 'budget-${monthStartIso(month)}-all', {
      'start': monthStartIso(month),
      'amountRial': 200000000,
    });
    await store.put('budget', 'budget-${monthStartIso(month)}-cat-groceries', {
      'start': monthStartIso(month),
      'category': 'cat-groceries',
      'amountRial': 10000000,
    });
    await store.put('tpl', 'tpl-rent', {
      'label': persian ? 'اجاره' : 'Rent',
      'type': 'expense',
      'amountRial': 120000000,
      'category': 'cat-rent',
      'day': 1,
      'calendar': persian ? 'jalali' : 'gregorian',
    });
  }

  Future<void> save(GlobalKey boundary, String name) async {
    const output = String.fromEnvironment('NEX_CAPTURE');
    if (output.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(output)..createSync(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  for (final persian in [true, false]) {
    testWidgets(
      'the home and the editor render in ${persian ? 'Persian dark' : 'English light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = NexModuleStore(harness.services, 'expenses');
        await seed(store, persian: persian);
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: persian
                  ? nexDarkTheme(fontFamily: 'Vazirmatn')
                  : nexLightTheme(fontFamily: 'Inter'),
              home: ExpensesScreen(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => save(
            boundary,
            'expenses_home_${persian ? 'fa_dark' : 'en_light'}',
          ),
        );
        // The editor, on the same page: amount, category, and today.
        await tester.tap(find.byKey(const ValueKey('expenses-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('expenses-amount')),
          persian ? '۱۲۵٬۰۰۰' : '125,000',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => save(
            boundary,
            'expenses_editor_${persian ? 'fa_dark' : 'en_light'}',
          ),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('320×480 at 2× text holds the layout', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = NexModuleStore(harness.services, 'expenses');
    await seed(store, persian: true);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nexDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ExpensesScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
