import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/family_fund/detail.dart';
import 'package:nex_client/modules/family_fund/editor.dart';
import 'package:nex_client/modules/family_fund/model.dart';
import 'package:nex_client/modules/family_fund/reminder.dart';
import 'package:nex_client/modules/family_fund/screen.dart';

import '../../support/nex_harness.dart';
import 'model_test.dart' show example;
import '../../support/text_input.dart';

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

  Fund seeded({List<String> paid = const []}) {
    final sample = example(fundMonth(DateTime.now()));
    final month = sample.start;
    return Fund(sample.id, {
      ...sample.body,
      'members': [
        for (final (i, member) in sample.members.indexed)
          {...member, 'shares': i + 1},
      ],
      'payments': [
        for (final id in paid)
          <String, Object?>{
            'member': id,
            'month': dayKey(month.first),
            'at': dayKey(month.first),
            'amountRial': 5000 * (int.parse(id) + 1),
          },
      ],
    });
  }

  testWidgets(
    'creation retains unfinished fields and saves the amount in rials',
    (t) async {
      await show(t, FamilyFundsScreen(store: store));
      await tap(t, find.text('New fund'));
      await enterNexText(t, find.byType(TextField).first, 'Friday fund');
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pumpAndSettle();
      await tap(t, find.text('New fund'));
      expect(find.text('Friday fund'), findsOneWidget);
      await enterNexText(t, find.byType(TextField).at(1), '۵۰۰۰۰');
      await t.pumpAndSettle();
      await tap(t, find.text('Save'));
      final row = (await store.list('fund')).single;
      expect(row.body['shareRial'], 500000);
      expect(find.text('Friday fund'), findsOneWidget);
    },
  );

  testWidgets(
    'the draw sheet shows the pool, records a result and keeps redraws',
    (t) async {
      final f = seeded();
      await store.put('fund', f.id, f.body);
      await show(t, FundDetail(store: store, initial: f));
      await tap(t, find.text('Draw the winner'));
      expect(find.text('Eligible members · round 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-confirm')), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('draw-confirm')));
      expect(find.text('The winner is'), findsOneWidget);
      final first = Fund('x', (await store.get('fund', f.id))!).draws.single;
      final firstWinner = nameOf(
        rows(first['eligible']).firstWhere((e) => e['id'] == first['winner']),
      );
      expect(find.text(firstWinner), findsWidgets);
      await tap(t, find.byKey(const ValueKey('draw-again-in-sheet')));
      expect(find.text('Winner: $firstWinner'), findsWidgets);
      expect(
        find.text(
          'Both results stay in the history. Write why you are drawing again.',
        ),
        findsOneWidget,
      );
      await tap(t, find.byKey(const ValueKey('draw-confirm')));
      expect(find.text('Write a reason for drawing again.'), findsOneWidget);
      await enterNexText(t, nexInputs().last, 'Mistake in the first pool');
      await tap(t, find.byKey(const ValueKey('draw-confirm')));
      expect(find.text('The winner is'), findsOneWidget);
      final saved = Fund('x', (await store.get('fund', f.id))!);
      expect(saved.draws, hasLength(2));
      expect(saved.draws.last['reason'], 'Mistake in the first pool');
      await tap(t, find.text('Draw history').last);
      expect(find.textContaining('Mistake in the first pool'), findsOneWidget);
    },
  );

  testWidgets('payout and instalments change recorded cash once', (t) async {
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
    await enterNexText(t, find.byType(TextField).first, '300');
    await enterNexText(t, find.byType(TextField).at(1), '3');
    await tap(t, find.text('Save'));
    Future<Fund> read() async => Fund(f.id, (await store.get('fund', f.id))!);
    expect((await read()).balanceAt(when), 2000);
    expect(find.text('Draw again'), findsNothing);
    await tap(t, find.text('Loans'));
    expect(find.text('All instalments'), findsOneWidget);
    await tap(t, find.text('Instalment 1'));
    expect((await read()).balanceAt(when), 3000);
    expect(
      rows((await read()).loans.single['instalments']).first['paidAt'],
      dayKey(when),
    );
    await tap(t, find.text('All instalments'));
    expect(find.text('Instalment 3'), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('loan:winner:inst:1')));
    expect(
      rows((await read()).loans.single['instalments'])[1]['paidAt'],
      dayKey(when),
    );
  });

  testWidgets(
    'a member sheet shows the history and records the current month',
    (t) async {
      final f = seeded(paid: ['0']);
      await store.put('fund', f.id, f.body);
      await show(t, FundDetail(store: store, initial: f));
      await tap(t, find.text('Members').first);
      await tap(t, find.text('Mina'));
      expect(find.text('This round'), findsOneWidget);
      expect(find.text('Contributions'), findsOneWidget);
      expect(find.text('Record this month'), findsOneWidget);
      await tap(t, find.text('Record this month'));
      final saved = Fund('x', (await store.get('fund', f.id))!);
      expect(saved.payments.any((p) => p['member'] == '1'), isTrue);
    },
  );

  testWidgets('fund details can be corrected without touching the ledger', (
    t,
  ) async {
    final f = seeded();
    await store.put('fund', f.id, f.body);
    await show(t, FundDetail(store: store, initial: f));
    await tap(t, find.byIcon(Icons.more_vert));
    await tap(t, find.text('Edit fund'));
    await enterNexText(t, find.byType(TextField).first, 'Family fund 2');
    await tap(t, find.text('Save'));
    expect((await store.get('fund', f.id))!['name'], 'Family fund 2');
    expect(find.text('Family fund 2'), findsOneWidget);
  });

  testWidgets('a share change starts at its month and keeps recorded amounts', (
    t,
  ) async {
    final f = seeded(paid: ['0']);
    await store.put('fund', f.id, f.body);
    await show(t, FundDetail(store: store, initial: f));
    await tap(t, find.text('Members').first);
    await tap(t, find.text('Change share'));
    await enterNexText(t, find.byType(TextField).first, '700');
    await tap(t, find.text('Save'));
    final saved = Fund('x', (await store.get('fund', f.id))!);
    expect(saved.shareChanges, hasLength(1));
    expect(saved.shareChanges.single['shareRial'], 7000);
    expect(saved.shareChanges.single['from'], dayKey(saved.start.first));
    expect(saved.payments.single['amountRial'], 5000);
    expect(saved.potFor(saved.start), 42000);
  });

  testWidgets('a month whose contributions are all in does not ring again', (
    t,
  ) async {
    final sample = example(fundMonth(DateTime.now()));
    final month = sample.start;
    final today = DateUtils.dateOnly(DateTime.now());
    if (!dueDay(month, sample.paymentDay).isAfter(today)) return;
    final f = Fund(sample.id, {
      ...sample.body,
      'payments': [
        for (final member in sample.members)
          <String, Object?>{
            'member': member['id'],
            'month': dayKey(month.first),
            'at': dayKey(today),
            'amountRial': sample.shareFor(month) * (member['shares'] as int),
          },
      ],
    });
    await store.put('fund', f.id, f.body);
    await show(t, FundDetail(store: store, initial: f));
    final reminder = t
        .widgetList<FundReminder>(find.byType(FundReminder))
        .first;
    expect(fundMonth(reminder.initial), isNot(month));
  });

  testWidgets('the fund shelf opens a fund and explains an empty one', (
    t,
  ) async {
    final f = seeded();
    final second = Fund('y', {
      ...f.body,
      'name': 'Office fund',
      'start': dayKey(f.start.shift(1).first),
    });
    await store.put('fund', f.id, f.body);
    await store.put('fund', second.id, second.body);
    await show(t, FamilyFundsScreen(store: store));
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Office fund'), findsOneWidget);
    expect(find.text('2 funds'), findsOneWidget);
    await tap(t, find.byKey(ValueKey('fund:${f.id}')));
    expect(find.byType(FundDetail), findsOneWidget);
  });

  testWidgets('an empty shelf offers the first fund', (t) async {
    await show(t, FamilyFundsScreen(store: store));
    expect(find.textContaining('Create your first fund'), findsOneWidget);
    await tap(t, find.text('New fund'));
    expect(find.byType(FundEditor), findsOneWidget);
  });

  testWidgets('the draw sheet fits a compact Persian screen', (t) async {
    final f = seeded();
    await store.put('fund', f.id, f.body);
    await show(
      t,
      FundDetail(store: store, initial: f),
      fa: true,
      compact: true,
    );
    await tap(t, find.text('قرعه‌کشی'));
    expect(t.takeException(), isNull);
    await tap(t, find.byKey(const ValueKey('draw-confirm')));
    expect(t.takeException(), isNull);
    expect(find.text('برنده'), findsWidgets);
    await tap(t, find.text('تمام'));
  });

  test('a reminder names the day and clock that were chosen', () {
    final at = DateTime(2026, 11, 22, 9, 5);
    final en = fundReminderBody('Family fund', at, persian: false);
    expect(
      en,
      'Family fund · ${nexReadableDate(at, solar: true, persian: false, time: true)}',
    );
    expect(en, contains('09:05'));
    final fa = fundReminderBody('صندوق خانواده', at, persian: true);
    expect(fa, contains('، '));
    expect(fa, contains('۰۹:۰۵'));
    expect(fa, contains('۱۴۰۵'));
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
