import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_logic.dart';
import 'package:nex_client/modules/parking/parking_quick_reminder.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';

import '../../support/nex_harness.dart';

/// The upgrade's additions: one-tap parking, favourite places, the large
/// countdown, the words for coming back, the quick reminder before paid time
/// ends, and old records still opening as they were.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_upgrade_');
    store = NexModuleStore(h.services, 'parking');
  });
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, [Widget? screen]) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen ?? ParkingScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object?> open({
    String id = 's1',
    String place = 'North lot',
    String vehicle = 'Car',
    Duration? endsIn,
  }) => {
    'v': 1,
    'vehicle': vehicle,
    'place': place,
    'startedAt': DateTime.now()
        .subtract(const Duration(minutes: 30))
        .toUtc()
        .toIso8601String(),
    if (endsIn != null)
      'expiresAt': DateTime.now().add(endsIn).toUtc().toIso8601String(),
  };

  group('favourite places', () {
    testWidgets('a star moves a remembered place into Favourites', (
      tester,
    ) async {
      await store.put('place', 'p1', {
        'v': 1,
        'place': 'Saba mall',
        'floor': '-1',
        'spot': 'B12',
        'useCount': 3,
        'lastUsedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await pump(tester);
      expect(find.text('Favourites'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('parking-favourite-p1')));
      await tester.pumpAndSettle();

      expect((await store.get('place', 'p1'))!['favorite'], isTrue);
      expect(find.text('Favourites'), findsOneWidget);

      // The favourite fills the editor in one tap — it never parks silently.
      await tester.tap(find.text('Saba mall'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('parking-field-place')),
            )
            .controller!
            .text,
        'Saba mall',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    });

    testWidgets('an old place without the mark is simply not a favourite', (
      tester,
    ) async {
      await store.put('place', 'old', {
        'v': 1,
        'place': 'Library',
        'useCount': 1,
        'lastUsedAt': '2024-01-01T10:00:00.000Z',
      });
      await pump(tester);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Favourites'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the paid time', () {
    testWidgets('time left is the large line, with its meaning below', (
      tester,
    ) async {
      await store.put(
        'session',
        's1',
        open(endsIn: const Duration(minutes: 78)),
      );
      await pump(tester);

      final left = tester.widget<Text>(
        find.byKey(const ValueKey('parking-time-left')),
      );
      // Whole minutes, rounded down: the test's clock moves while it runs.
      expect(left.data, matches(RegExp(r'^1 h 1[78] min$')));
      expect(find.text('Left on the meter'), findsOneWidget);
    });

    testWidgets('a past time says it is past, not negative', (tester) async {
      await store.put(
        'session',
        's1',
        open(endsIn: const Duration(minutes: -5)),
      );
      await pump(tester);
      expect(find.text('Past the paid time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a part of a minute is said in words, not as zero', (
      tester,
    ) async {
      final body = open(endsIn: const Duration(seconds: 40));
      body['startedAt'] = DateTime.now()
          .subtract(const Duration(seconds: 30))
          .toUtc()
          .toIso8601String();
      await store.put('session', 's1', body);
      await pump(tester);
      expect(find.text('Parked for under a minute'), findsOneWidget);
      expect(find.byKey(const ValueKey('parking-time-left')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('parking-time-left')))
            .data,
        'under a minute',
      );
    });
  });

  group('coming back', () {
    testWidgets('«I\'m back» ends the parking and keeps it in history', (
      tester,
    ) async {
      await store.put('session', 's1', open());
      await pump(tester);
      expect(find.text("I'm back"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();

      final saved = (await store.get('session', 's1'))!;
      expect(saved['foundAt'], isNotNull);
      expect(find.text("I'm back"), findsNothing);
      expect(find.text('North lot'), findsWidgets);
    });
  });

  group('the quick reminder before paid time ends', () {
    testWidgets('opens with ten minutes, editable, and says when it rings', (
      tester,
    ) async {
      await store.put('session', 's1', open(endsIn: const Duration(hours: 2)));
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('parking-quick-remind')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('parking-remind-minutes')),
      );
      expect(field.controller!.text, '10');
      expect(find.textContaining('Alerts at'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('parking-remind-minutes')),
        '25',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Alerts at'), findsOneWidget);
    });

    testWidgets('reopens on the lead already set, not a silent ten', (
      tester,
    ) async {
      final body = open(endsIn: const Duration(hours: 2));
      body['remindMinutes'] = 30;
      await store.put('session', 's1', body);
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('parking-quick-remind')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('parking-remind-minutes')),
            )
            .controller!
            .text,
        '30',
      );
    });

    testWidgets('a short stay opens on a lead that still fits', (tester) async {
      await store.put(
        'session',
        's1',
        open(endsIn: const Duration(minutes: 8)),
      );
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('parking-quick-remind')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('parking-remind-minutes')),
            )
            .controller!
            .text,
        '5',
      );
      // A half-hour lead cannot fit in eight minutes, so it is not offered.
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('parking-remind-30')))
            .onSelected,
        isNull,
      );
    });

    testWidgets('an ended paid time offers no reminder at all', (tester) async {
      await store.put(
        'session',
        's1',
        open(endsIn: const Duration(minutes: -5)),
      );
      await pump(tester);
      expect(find.byKey(const ValueKey('parking-quick-remind')), findsNothing);
      expect(find.text('Past the paid time'), findsOneWidget);
    });

    testWidgets('a paid time under a minute away offers no reminder', (
      tester,
    ) async {
      await store.put(
        'session',
        's1',
        open(endsIn: const Duration(seconds: 40)),
      );
      await pump(tester);
      expect(find.byKey(const ValueKey('parking-quick-remind')), findsNothing);
      expect(find.byKey(const ValueKey('parking-time-left')), findsOneWidget);
    });

    testWidgets('the sheet still refuses a past moment when opened directly', (
      tester,
    ) async {
      await store.put('session', 's1', open());
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      await pump(
        tester,
        Scaffold(
          body: ParkingReminderSheet(
            store: store,
            recordId: 's1',
            expiresAt: past,
            place: 'North lot',
            floor: '',
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('parking-remind-minutes')),
        '10',
      );
      await tester.tap(find.byKey(const ValueKey('parking-remind-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('That moment has passed. Pick fewer minutes.'),
        findsOneWidget,
      );
      expect(await store.get('__reminder', 'session:s1'), isNull);
    });

    testWidgets('a non-number is refused in words', (tester) async {
      await store.put('session', 's1', open(endsIn: const Duration(hours: 2)));
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('parking-quick-remind')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-remind-minutes')),
        'soon',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('parking-remind-save')));
      await tester.pumpAndSettle();

      expect(find.text('Write a whole number of minutes.'), findsOneWidget);
      expect(await store.get('__reminder', 'session:s1'), isNull);
    });

    test('the arithmetic never sets a reminder in the past', () {
      final now = DateTime(2026, 11, 17, 12);
      final ends = DateTime(2026, 11, 17, 13);
      expect(ParkingLogic.reminderAt(ends, 10), DateTime(2026, 11, 17, 12, 50));
      expect(ParkingLogic.reminderFits(ends, 10, now), isTrue);
      expect(ParkingLogic.reminderFits(ends, 61, now), isFalse);
      expect(ParkingLogic.reminderFits(ends, 0, now), isFalse);
      expect(ParkingLogic.reminderFits(ends, -5, now), isFalse);
    });
  });

  group('records written before the upgrade', () {
    testWidgets('open, show and save without gaining or losing meaning', (
      tester,
    ) async {
      await store.put('session', 'old', {
        'v': 1,
        'vehicle': 'Car',
        'place': 'Old mall',
        'floor': '2',
        'spot': 'A1',
        'landmark': 'By the lift',
        'startedAt': '2024-05-05T08:00:00.000Z',
        'foundAt': '2024-05-05T10:30:00.000Z',
      });
      await pump(tester);

      expect(find.text('Old mall'), findsOneWidget);
      await tester.tap(find.text('Old mall'));
      await tester.pumpAndSettle();
      expect(find.text('Parking'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
