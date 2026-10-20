part of 'screen_test.dart';

/// The shared Jalali/civil date entry and the shared multiline notes:
/// the calendar button beside the date field, the typed day landing in
/// storage exactly (with its clock), refusal of a day that is not one,
/// and notes that take more than one line through NexTextField.
void _screenCases3() {
  group('the shared date entry', () {
    testWidgets('a calendar button sits beside the typed day', (tester) async {
      final now = DateTime.now();
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('expenses-date-entry'));
      expect(
        find.descendant(
          of: entry,
          matching: find.byIcon(Icons.calendar_month_outlined),
        ),
        findsOneWidget,
      );
      // A new payment starts on today, as the old date button did.
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: entry, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        expensesDateEntryText(now),
      );
    });

    testWidgets('a typed day saves exactly and survives reopening', (
      tester,
    ) async {
      final day = DateTime.now().subtract(const Duration(days: 3));
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-date')),
        expensesDateEntryText(day),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '1500',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      final record = (await store.list('tx')).single;
      expect(
        record.body['date'],
        startsWith(expensesDateEntryText(day).replaceAll('/', '-')),
      );
      // All time: the row is there whatever month it landed in, and
      // the row's day reads through the shared date label.
      await tester.tap(find.text('All time').first);
      await tester.pumpAndSettle();
      expect(find.textContaining(expensesDateEntryText(day)), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('expenses-tx-${record.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('expenses-date')))
            .controller!
            .text,
        expensesDateEntryText(day),
      );
    });

    testWidgets('the typed clock is kept when the day is typed', (
      tester,
    ) async {
      final day = DateTime.now().subtract(const Duration(days: 4));
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      String clock() => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('expenses-time')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      final before = clock();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-date')),
        expensesDateEntryText(day),
      );
      await tester.pumpAndSettle();
      expect(clock(), before); // changing the date never drops the clock
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '700',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      final body = (await store.list('tx')).single.body;
      expect((body['date'] as String).substring(11, 16), before);
    });

    testWidgets('a day that is not one is refused, not guessed', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '1000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-date')),
        '2026/02/30',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);
      // The field says it, and so does the refused save's SnackBar.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expenses-date')),
          matching: find.text('Choose a valid date'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(await store.list('tx'), isEmpty);
      // Persian digits parse to the same refusal and the same day.
      await tester.enterText(
        find.byKey(const ValueKey('expenses-date')),
        '۲۰۲۶/۰۲/۲۸',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      expect(
        (await store.list('tx')).single.body['date'],
        startsWith('2026-02-28T'),
      );
    });

    testWidgets('the shared calendar writes a picked day and it saves', (
      tester,
    ) async {
      await pumpScreen(tester, locale: const Locale('fa'));
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '2000',
      );
      await tester.pumpAndSettle();
      final calendar = find.descendant(
        of: find.byKey(const ValueKey('expenses-date-entry')),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(calendar);
      await tester.tap(calendar);
      await tester.pumpAndSettle();
      expect(find.byType(NexAlertDialog), findsOneWidget);
      final day = find.text('۲۰');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pump();
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      final typed = tester
          .widget<TextField>(find.byKey(const ValueKey('expenses-date')))
          .controller!
          .text;
      expect(typed, isNotEmpty);
      expect(LocalValues.day(typed), isNotNull);
      final save = find.byKey(const ValueKey('expenses-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        (await store.list('tx')).single.body['date'],
        startsWith(typed.replaceAll('/', '-')),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the shared multiline notes', () {
    testWidgets('a payment note takes two lines and saves them', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-add')));
      await tester.pumpAndSettle();
      final note = tester.widget<NexTextField>(
        find.byKey(const ValueKey('expenses-note')),
      );
      expect(note.minLines, 2);
      expect(note.maxLines, 4);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '900',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-note')),
        'first line\nsecond line',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await tester.pumpAndSettle();
      final body = (await store.list('tx')).single.body;
      expect(body['note'], 'first line\nsecond line');
      expect(find.text('first line\nsecond line'), findsOneWidget);
    });

    testWidgets('a template note is the same shared editor', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expenses-new-template')));
      await tester.pumpAndSettle();
      final note = tester.widget<NexTextField>(
        find.byKey(const ValueKey('expenses-template-note')),
      );
      expect(note.minLines, 2);
      await tester.enterText(
        find.byKey(const ValueKey('expenses-template-name')),
        'Gym',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-amount')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expenses-template-note')),
        'monthly\nfee note',
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('expenses-template-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final body = (await store.list('tpl')).single.body;
      expect(body['note'], 'monthly\nfee note');
    });
  });

  group('template deletion', () {
    testWidgets('asks before deleting, and Undo brings it back', (
      tester,
    ) async {
      final controller = ExpensesController(store);
      await controller.load();
      await controller.saveTemplate(
        const ExpenseTemplate(
          id: 'tpl-gym',
          label: 'Gym',
          type: 'expense',
          amount: 5000,
          currency: 'IRR',
        ),
      );
      controller.dispose();

      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete template?'), findsOneWidget);
      expect(
        find.text('Records already saved from it are untouched.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Gym'), findsNothing);
      expect(await store.get('tpl', 'tpl-gym'), isNull);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await store.get('tpl', 'tpl-gym'))!['label'], 'Gym');
      expect(find.text('Gym'), findsOneWidget);
    });
  });
}
