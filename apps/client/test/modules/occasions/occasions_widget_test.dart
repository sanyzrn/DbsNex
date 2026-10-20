import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/occasions/occasion_detail.dart';
import 'package:nex_client/modules/occasions/occasions_screen.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'occasions_');
    store = NexModuleStore(h.services, 'occasions');
  });
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nexLightTheme(),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object?> body({
    String title = 'Sara',
    String kind = 'birthday',
    String calendar = 'gregorian',
    required int month,
    required int day,
    int? year,
    bool archived = false,
  }) => {
    'v': 1,
    'title': title,
    'kind': kind,
    'calendar': calendar,
    'month': month,
    'day': day,
    'yearKnown': year != null,
    if (year != null) 'year': year,
    'leapPolicy': 'lastDay',
    'note': '',
    'favorite': false,
    'muted': false,
    'archived': archived,
    'remindMinutes': 540,
    'createdAt': '2026-01-01T00:00:00.000',
  };

  group('the list', () {
    testWidgets('nothing yet: one button, no floating one', (tester) async {
      await pump(tester, OccasionsScreen(store: store));
      expect(
        find.text('No dates yet. Add a birthday or an anniversary.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('occasions-add')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('today, soon and later are grouped, nearest first', (
      tester,
    ) async {
      final now = DateTime.now();
      final soon = now.add(const Duration(days: 3));
      final later = now.add(const Duration(days: 100));
      await store.put(
        'occasion',
        'a',
        body(title: 'Today one', month: now.month, day: now.day),
      );
      await store.put(
        'occasion',
        'b',
        body(title: 'Soon one', month: soon.month, day: soon.day),
      );
      await store.put(
        'occasion',
        'c',
        body(title: 'Later one', month: later.month, day: later.day),
      );
      await pump(tester, OccasionsScreen(store: store));
      expect(find.text('Today'), findsAtLeast(1));
      expect(find.text('In the next 7 days'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('in 3 days'), findsOneWidget);
      expect(find.byKey(const ValueKey('occasion-days-a')), findsOneWidget);
      final today = tester.getTopLeft(find.text('Today one')).dy;
      final soonY = tester.getTopLeft(find.text('Soon one')).dy;
      final laterY = tester.getTopLeft(find.text('Later one')).dy;
      expect(today, lessThan(soonY));
      expect(soonY, lessThan(laterY));
      // One primary action once there is something.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('a known birth year shows the age; unknown shows none', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 5));
      await store.put(
        'occasion',
        'a',
        body(
          title: 'Known',
          month: soon.month,
          day: soon.day,
          year: soon.year - 30,
        ),
      );
      await store.put(
        'occasion',
        'b',
        body(title: 'Unknown', month: soon.month, day: soon.day),
      );
      await pump(tester, OccasionsScreen(store: store));
      expect(find.textContaining('turns 30'), findsOneWidget);
      expect(find.textContaining('turns'), findsOneWidget);
    });

    testWidgets('an impossible date is listed to be fixed, not guessed', (
      tester,
    ) async {
      await store.put(
        'occasion',
        'x',
        body(title: 'Broken', month: 13, day: 5),
      );
      await pump(tester, OccasionsScreen(store: store));
      expect(find.text('Needs a date'), findsOneWidget);
      expect(find.text('Choose a day and month for this one.'), findsOneWidget);
    });

    testWidgets('archived ones wait behind a button', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 2));
      await store.put(
        'occasion',
        'a',
        body(title: 'Active', month: soon.month, day: soon.day),
      );
      await store.put(
        'occasion',
        'z',
        body(
          title: 'Old one',
          month: soon.month,
          day: soon.day,
          archived: true,
        ),
      );
      await pump(tester, OccasionsScreen(store: store));
      expect(find.text('Old one'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('occasions-archived-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Old one'), findsOneWidget);
    });

    testWidgets('in Persian the countdown and dates are Persian', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 3));
      await store.put(
        'occasion',
        'a',
        body(
          title: 'سارا',
          calendar: 'jalali',
          month: nexPersianDate(soon).month,
          day: nexPersianDate(soon).day,
        ),
      );
      await pump(
        tester,
        OccasionsScreen(store: store),
        locale: const Locale('fa'),
      );
      expect(find.text('۳ روز دیگر'), findsOneWidget);
      expect(find.text('۷ روز آینده'), findsOneWidget);
    });
  });

  group('adding one', () {
    testWidgets('saves a Jalali birthday with its own calendar fields', (
      tester,
    ) async {
      await pump(tester, OccasionsScreen(store: store));
      await tester.tap(find.byKey(const ValueKey('occasions-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-title')),
        'Sara',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('occasion-field-calendar')),
          matching: find.text('Jalali'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-day')),
        '15',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-field-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehr').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-year')),
        '1378',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-save')));
      await settle(tester);

      final records = await store.list('occasion');
      expect(records, hasLength(1));
      final saved = records.single.body;
      expect(saved['title'], 'Sara');
      expect(saved['calendar'], 'jalali');
      expect(saved['month'], 7);
      expect(saved['day'], 15);
      expect(saved['year'], 1378);
      expect(saved['yearKnown'], true);
      // It is on the list, in its own calendar.
      expect(find.text('Sara'), findsOneWidget);
    });

    testWidgets('refuses a day the month does not have, and a future year', (
      tester,
    ) async {
      await pump(tester, OccasionsScreen(store: store));
      await tester.tap(find.byKey(const ValueKey('occasions-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-title')),
        'Odd',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('occasion-field-calendar')),
          matching: find.text('Gregorian'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-day')),
        '31',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-field-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('April').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('occasion-year-unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('occasion-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('occasion-day-error')), findsOneWidget);
      expect(await store.list('occasion'), isEmpty);

      // A real day, but a year that has not come.
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-day')),
        '30',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-year-unknown')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-year')),
        '${DateTime.now().year + 2}',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-save')));
      await tester.pumpAndSettle();
      expect(find.text('That year has not come yet.'), findsOneWidget);
      expect(await store.list('occasion'), isEmpty);
    });

    testWidgets('29 February offers the choice for years without it', (
      tester,
    ) async {
      await pump(tester, OccasionsScreen(store: store));
      await tester.tap(find.byKey(const ValueKey('occasions-add')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('occasion-field-calendar')),
          matching: find.text('Gregorian'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('occasion-field-leap')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-day')),
        '29',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-field-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('February').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('occasion-field-leap')), findsOneWidget);
    });

    testWidgets('Persian digits are read as numbers', (tester) async {
      await pump(
        tester,
        OccasionsScreen(store: store),
        locale: const Locale('fa'),
      );
      await tester.tap(find.byKey(const ValueKey('occasions-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-title')),
        'علی',
      );
      await tester.enterText(
        find.byKey(const ValueKey('occasion-field-day')),
        '۱۲',
      );
      await tester.tap(find.byKey(const ValueKey('occasion-year-unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('occasion-save')));
      await settle(tester);
      final saved = (await store.list('occasion')).single.body;
      expect(saved['day'], 12);
      expect(saved['yearKnown'], false);
      expect(saved.containsKey('year'), isFalse);
    });
  });

  group('one occasion', () {
    Future<void> openDetail(WidgetTester tester, {Locale? locale}) => pump(
      tester,
      OccasionDetailScreen(store: store, occasionId: 'a'),
      locale: locale ?? const Locale('en'),
    );

    testWidgets('shows the countdown, both calendars and a greeting', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 4));
      await store.put(
        'occasion',
        'a',
        body(month: soon.month, day: soon.day, year: soon.year - 20),
      );
      await openDetail(tester);
      expect(find.text('in 4 days'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('occasion-both-calendars')),
        findsOneWidget,
      );
      expect(find.textContaining('Jalali:'), findsOneWidget);
      expect(find.textContaining('Gregorian:'), findsAtLeast(1));
      expect(find.text('turns 20'), findsOneWidget);
      expect(find.textContaining('Happy birthday'), findsOneWidget);
      expect(find.text('No reminder.'), findsOneWidget);
    });

    testWidgets('delete takes it away, with Undo that brings it all back', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 4));
      final original = body(
        month: soon.month,
        day: soon.day,
        year: soon.year - 20,
      )..['futureField'] = {'kept': true};
      await store.put('occasion', 'a', original);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        OccasionDetailScreen(store: store, occasionId: 'a'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('occasion-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(await store.get('occasion', 'a'), isNull);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      final back = await store.get('occasion', 'a');
      expect(back, isNotNull);
      expect(back!['futureField'], {'kept': true});
      expect(back['title'], 'Sara');
    });

    testWidgets('archive and favourite change only their own field', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 4));
      await store.put(
        'occasion',
        'a',
        body(month: soon.month, day: soon.day)..['futureField'] = 7,
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const ValueKey('occasion-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as important'));
      await settle(tester);
      var saved = (await store.get('occasion', 'a'))!;
      expect(saved['favorite'], true);
      expect(saved['futureField'], 7);
      expect(saved['archived'], false);
      await tester.tap(find.byKey(const ValueKey('occasion-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await settle(tester);
      saved = (await store.get('occasion', 'a'))!;
      expect(saved['archived'], true);
      expect(saved['favorite'], true);
    });
  });
}
