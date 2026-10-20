import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_detail_screen.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loan_detail_screen.dart';
import 'package:nex_client/modules/lent_borrowed/loans_screen.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/comparison.dart';
import 'package:nex_client/modules/price_lens/lens_widgets.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/price_lens_screen.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/modules/price_lens/units.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../support/nex_harness.dart';

/// Habits, Price Lens and Lent & Borrowed as they are once finished: one
/// primary action per page, the calendar button beside its field, a daily
/// habit reminder, a loan's due-date reminder, a result worth copying.
void main() {
  late NexTestHarness h;
  setUp(() async => h = await NexTestHarness.create(name: 'nex_reviewed_'));
  tearDown(() => h.dispose());

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: nexLightTheme(),
    home: home,
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  group('one primary action per page', () {
    testWidgets(
      'habits: the button in the empty state, then the floating one',
      (tester) async {
        final store = NexModuleStore(h.services, 'habits');
        await tester.pumpWidget(app(HabitsScreen(store: store)));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('habits-new')), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);

        await store.put('habit', 'h1', {
          'name': 'Stretch',
          'note': '',
          'schedule': 'daily',
          'target': 1,
          'archived': false,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await settle(tester);
        // The page reloads on a changed store; give it the pull it would get.
        await tester.pumpWidget(app(HabitsScreen(store: store)));
        await settle(tester);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.byKey(const ValueKey('habits-new')), findsOneWidget);
      },
    );

    testWidgets('loans: one button with no record, floating after', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'lent_borrowed');
      await tester.pumpWidget(app(LoansScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('loans-new')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      await store.put('loan', 'l1', {
        'person': 'Sara',
        'direction': 'lent',
        'type': 'money',
        'amount': 1000,
        'currency': 'IRR',
        'issued': '2026-10-01',
        'due': null,
        'note': '',
      });
      await tester.pumpWidget(app(LoansScreen(store: store)));
      await settle(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      // The other tab is empty, and says so without a second button.
      await tester.tap(find.byKey(const ValueKey('loans-tab-borrowed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('loans-new')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('price lens: the same, until four offers fill it', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'price_lens');
      await tester.pumpWidget(app(PriceLensScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lens-add')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('the calendar button sits beside its field', () {
    testWidgets('at the same height, not on a row of its own', (tester) async {
      final controller = TextEditingController(text: '2026/10/20');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: NexModuleDateEntry(
              controller: controller,
              child: TextField(
                key: const ValueKey('date-field'),
                controller: controller,
              ),
            ),
          ),
        ),
      );
      final field = tester.getRect(find.byKey(const ValueKey('date-field')));
      final button = tester.getRect(find.byIcon(Icons.calendar_month_outlined));
      expect(button.top, lessThan(field.bottom));
      expect(button.center.dx, greaterThan(field.right));
    });
  });

  group('a daily reminder for a habit', () {
    test('rings at the next occurrence of the clock face', () {
      final now = DateTime(2026, 10, 20, 9, 30);
      expect(
        nexNextDailyRing(DateTime(2026, 1, 1, 20, 0), now),
        DateTime(2026, 10, 20, 20, 0),
      );
      expect(
        nexNextDailyRing(DateTime(2026, 1, 1, 8, 15), now),
        DateTime(2026, 10, 21, 8, 15),
      );
      // The same minute is not "ahead": it is tomorrow's.
      expect(
        nexNextDailyRing(DateTime(2026, 1, 1, 9, 30), now),
        DateTime(2026, 10, 21, 9, 30),
      );
    });

    testWidgets('shows the stored time and a switch that clears it', (
      tester,
    ) async {
      final store = NexModuleStore(h.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'Stretch',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await store.put('__reminder', 'habit:h1', {
        'sourceKind': 'habit',
        'sourceId': 'h1',
        'at': DateTime(2026, 10, 20, 20, 0).toUtc().toIso8601String(),
        'title': 'Habit',
        'body': 'A habit is waiting for today.',
        'repeat': 'daily',
      });
      // The page has a calendar now; a tall screen keeps every panel built.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(HabitDetailScreen(store: store, habitId: 'h1')),
      );
      await settle(tester);
      expect(find.text('Daily reminder'), findsOneWidget);
      expect(find.text('Every day at 20:00'), findsOneWidget);
      final toggle = find.byKey(const ValueKey('habit-reminder-switch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      expect(await store.get('__reminder', 'habit:h1'), isNull);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('an archived habit has no reminder row', (tester) async {
      final store = NexModuleStore(h.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'Stretch',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(
        app(HabitDetailScreen(store: store, habitId: 'h1')),
      );
      await settle(tester);
      expect(find.text('Daily reminder'), findsNothing);
    });
  });

  group('a loan\'s reminder', () {
    Future<NexModuleStore> seedLoan() async {
      final store = NexModuleStore(h.services, 'lent_borrowed');
      await store.put('loan', 'l1', {
        'person': 'Sara',
        'direction': 'lent',
        'type': 'money',
        'amount': 1000,
        'currency': 'IRR',
        'issued': '2026-10-01',
        'due': '2030-01-01',
        'note': '',
      });
      await store.put('__reminder', 'loan:l1', {
        'sourceKind': 'loan',
        'sourceId': 'l1',
        'at': DateTime(2030, 1, 1, 9).toUtc().toIso8601String(),
        'title': 'Reminder',
        'body': 'A loan with Sara is due back.',
      });
      return store;
    }

    testWidgets('has its section on an open loan', (tester) async {
      final store = await seedLoan();
      await tester.pumpWidget(
        app(LoanDetailScreen(store: store, loanId: 'l1')),
      );
      await settle(tester);
      expect(find.text('Reminder'), findsOneWidget);
      expect(find.text('Pick a time…'), findsOneWidget);
    });

    testWidgets('goes when the loan is settled', (tester) async {
      final store = await seedLoan();
      await tester.pumpWidget(
        app(LoanDetailScreen(store: store, loanId: 'l1')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('loan-mark-settled')));
      await settle(tester);
      await settle(tester);
      expect(await store.get('__reminder', 'loan:l1'), isNull);
    });
  });

  testWidgets('price lens copies its result as lines', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    PriceOption offer(String id, String label, int price, num q, String unit) =>
        PriceOption(
          id: id,
          label: label,
          priceMinor: price,
          currency: 'USD',
          quantity: fractionFromDecimal('$q')!,
          unitKey: unit,
        );
    final unit = priceUnitOf('kg')!;
    final comparison = compareOptions([
      offer('a', 'Rice 750g', 525, 750, 'g'),
      offer('b', 'Rice 1kg', 650, 1, 'kg'),
    ], unit);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(
            children: [
              LensResultPanel(
                comparison: comparison,
                commonUnit: unit,
                persian: false,
                memoryLine: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('lens-copy-result')));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    final lines = copied!.split('\n');
    expect(lines, hasLength(4));
    // 6.50 against 7.00 a kilo: 0.50 less, 7.1% of the dearer one.
    expect(lines[1], 'Rice 1kg costs 7.1% less per kg than Rice 750g.');
    expect(lines[2], startsWith('• '));
    expect(lines[2], contains('Rice 750g'));
    expect(lines[3], startsWith('✓ '));
    expect(lines[3], contains('Rice 1kg'));
  });

  test('prices can be read per 100 g and per 100 ml', () {
    final g100 = priceUnitOf('g100')!;
    final ml100 = priceUnitOf('ml100')!;
    expect(
      convertQuantity(const Fraction(750), priceUnitOf('g')!, g100),
      const Fraction(15, 2),
    );
    expect(
      convertQuantity(const Fraction(1), priceUnitOf('l')!, ml100),
      const Fraction(10),
    );
    expect(convertQuantity(const Fraction(1), g100, ml100), isNull);
  });
}
