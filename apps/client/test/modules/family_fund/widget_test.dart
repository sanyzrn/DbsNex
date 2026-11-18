import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/family_fund/detail.dart';
import 'package:nex_client/modules/family_fund/model.dart';
import 'package:nex_client/modules/family_fund/screen.dart';

import '../../support/nex_harness.dart';
import 'model_test.dart' show example;

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'family_fund_');
    store = NexModuleStore(h.services, 'family_fund');
  });
  tearDown(() => h.dispose());

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool fa = false,
    bool dark = false,
    bool compact = false,
  }) async {
    tester.view.physicalSize = compact
        ? const Size(320, 570)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(fa ? 'fa' : 'en'),
          theme: dark
              ? nexDarkTheme(fontFamily: 'Vazirmatn')
              : nexLightTheme(fontFamily: 'Inter'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(compact ? 2 : 1),
              disableAnimations: compact,
            ),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'creation retains unfinished fields and saves the amount in rials',
    (t) async {
      await show(t, FamilyFundsScreen(store: store));
      await tap(t, find.text('New fund'));
      await t.enterText(find.byType(TextField).first, 'Friday fund');
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pumpAndSettle();
      await tap(t, find.text('New fund'));
      expect(find.text('Friday fund'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(1), '۵۰۰۰۰');
      await t.pumpAndSettle();
      await tap(t, find.text('Save'));
      final row = (await store.list('fund')).single;
      expect(row.body['shareRial'], 500000);
      expect(find.text('Friday fund'), findsOneWidget);
    },
  );

  testWidgets(
    'one tap persists a contribution, and draw preview/history use eligible names',
    (t) async {
      final f = example(fundMonth(DateTime.now()));
      await store.put('fund', f.id, f.body);
      await show(t, FundDetail(store: store, initial: f));
      await tap(t, find.byKey(const ValueKey('pay:0')));
      final saved = Fund(f.id, (await store.get('fund', f.id))!);
      expect(saved.payments.single['amountRial'], 5000);
      await tap(t, find.text('Draw winner'));
      expect(find.textContaining('Ali · Mina · Sara'), findsOneWidget);
      await tap(t, find.text('Confirm'));
      expect(Fund(f.id, (await store.get('fund', f.id))!).draws, hasLength(1));
      await tap(t, find.text('Draw history'));
      expect(find.textContaining('Ali · Mina · Sara'), findsOneWidget);
    },
  );

  testWidgets('payout and repayment change recorded cash once', (t) async {
    final sample = example(fundMonth(DateTime.now()));
    final when = DateTime.now();
    final draft = sample.draw(sample.start, when, 'winner', '', Random(0));
    final f = Fund(sample.id, {
      ...draft,
      'payments': [
        <String, Object?>{
          'member': '0',
          'month': dayKey(sample.start.first),
          'at': dayKey(when),
          'amountRial': 5000,
        },
      ],
    });
    await store.put('fund', f.id, f.body);
    await show(t, FundDetail(store: store, initial: f));
    await tap(t, find.text('Record loan payout'));
    await t.enterText(find.byType(TextField).first, '300');
    await t.enterText(find.byType(TextField).at(1), '3');
    await tap(t, find.text('Save'));
    Future<Fund> read() async => Fund(f.id, (await store.get('fund', f.id))!);
    expect((await read()).balanceAt(when), 2000);
    expect(find.text('Draw again'), findsNothing);
    await tap(t, find.text('Loans'));
    await tap(t, find.text('Instalment 1'));
    expect((await read()).balanceAt(when), 3000);
    expect(
      rows((await read()).loans.single['instalments']).first['paidAt'],
      dayKey(when),
    );
  });

  for (final fa in [false, true]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets('ledger tabs fa:$fa dark:$dark compact:$compact', (
          t,
        ) async {
          const output = String.fromEnvironment('NEX_CAPTURE');
          final capture = output.isNotEmpty && !compact && fa == dark;
          if (capture) {
            await t.runAsync(() async {
              for (final (family, asset) in [
                ('Inter', 'assets/fonts/Inter-subset.ttf'),
                ('Vazirmatn', 'assets/fonts/VazirmatnVariable.ttf'),
                ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
              ]) {
                await (FontLoader(
                  family,
                )..addFont(rootBundle.load(asset))).load();
              }
            });
          }
          final sample = example(fundMonth(DateTime.now()));
          final month = sample.start;
          final f = Fund(sample.id, {
            ...sample.body,
            'name': fa ? 'صندوق خانوادهٔ بهار' : 'Spring family fund',
            'shareRial': 5000000,
            'members': [
              for (final (i, m) in sample.members.indexed)
                {
                  ...m,
                  'person': {
                    'name': fa ? ['علی', 'مینا', 'سارا'][i] : nameOf(m),
                  },
                },
            ],
            'payments': [
              <String, Object?>{
                'member': '0',
                'month': dayKey(month.first),
                'at': dayKey(month.first),
                'amountRial': 5000000,
              },
            ],
          });
          await store.put('fund', f.id, f.body);
          await show(
            t,
            FundDetail(store: store, initial: f),
            fa: fa,
            dark: dark,
            compact: compact,
          );
          Future<void> image(String page) async {
            if (!capture) return;
            await t.runAsync(() async {
              final boundary = t.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              );
              final img = await boundary.toImage();
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory(output).createSync(recursive: true);
              File('$output/${fa ? 'fa_dark' : 'en_light'}_$page.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }

          await image('month');
          await tap(t, find.text(fa ? 'اعضا' : 'Members').first);
          await image('members');
          await tap(t, find.text(fa ? 'وام‌ها' : 'Loans').first);
          await tap(
            t,
            find.byTooltip(fa ? 'پنهان‌کردن مبلغ‌ها' : 'Hide amounts'),
          );
          await tap(t, find.byTooltip(fa ? 'گزارش ماه' : 'Monthly report'));
          expect(find.byType(SelectableText), findsOneWidget);
          expect(
            t.widget<SelectableText>(find.byType(SelectableText)).data,
            contains(fa ? 'مبلغ پنهان است' : 'Amount hidden'),
          );
          expect(t.takeException(), isNull);
          await image('report');
        });
      }
    }
  }
}
