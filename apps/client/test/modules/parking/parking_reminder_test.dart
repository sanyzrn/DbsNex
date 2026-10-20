import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_detail.dart';
import 'package:nex_client/modules/parking/parking_repository.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';

import '../../support/nex_harness.dart';

/// The opt-in device reminder on an open parking: the control the platform
/// provides, offered where a person manages the parking, and cleared again
/// when the parking itself ends.
///
/// Scheduling itself needs the platform's notification permission and a
/// rolled-out module, so these tests stay honest to what a test build can
/// observe: the control appears in both places a person manages an open
/// parking, Clearing removes the stored reminder, «Found my car» clears it
/// too, and a closed parking offers nothing.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_reminder_');
    store = NexModuleStore(h.services, 'parking');
  });
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object?> openSession(String id, {String place = 'North lot'}) => {
    'v': 1,
    'vehicle': 'Car',
    'place': place,
    'startedAt': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, Object?> closedSession(String id) => {
    ...openSession(id),
    'foundAt': DateTime.now().toUtc().toIso8601String(),
  };

  group('the open parking offers the reminder', () {
    testWidgets('both buttons sit on the active card', (tester) async {
      await store.put('session', 's1', openSession('s1'));
      await pump(tester, ParkingScreen(store: store));

      expect(find.byKey(const ValueKey('parking-reminders')), findsOneWidget);
      expect(find.text('Pick a time…'), findsOneWidget);
      expect(find.text('Remove reminder'), findsOneWidget);
      expect(find.textContaining('device alert'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Clear removes the stored reminder for this parking', (
      tester,
    ) async {
      await store.put('session', 's1', openSession('s1'));
      await store.put('__reminder', 'session:s1', {
        'sourceKind': 'session',
        'sourceId': 's1',
        'at': DateTime.now()
            .add(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'title': 'Parking',
        'body': 'Paid time',
      });
      await pump(tester, ParkingScreen(store: store));

      await tester.tap(find.text('Remove reminder'));
      await tester.pumpAndSettle();
      expect(await store.get('__reminder', 'session:s1'), isNull);
      // The control stays, ready for another reminder.
      expect(find.text('Remove reminder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the date picker opens, and backing out sets nothing', (
      tester,
    ) async {
      await store.put('session', 's1', openSession('s1'));
      await pump(tester, ParkingScreen(store: store));

      await tester.tap(find.text('Pick a time…'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      // Backing out of the date leaves nothing behind.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(await store.list('__reminder'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('the detail page', () {
    // The detail list is longer than a test phone is tall, so the reminder
    // is reached the way a person reaches it: by scrolling.
    final detailScroll = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    testWidgets('an open parking offers the reminder there too', (
      tester,
    ) async {
      await store.put('session', 's1', openSession('s1'));
      await pump(tester, ParkingDetailPage(store: store, sessionId: 's1'));

      final pick = find.text('Pick a time…');
      await tester.dragUntilVisible(pick, detailScroll, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(pick, findsOneWidget);
      expect(find.text('Remove reminder'), findsOneWidget);

      await store.put('__reminder', 'session:s1', {
        'sourceKind': 'session',
        'sourceId': 's1',
        'at': DateTime.now()
            .add(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'title': 'Parking',
        'body': 'Paid time',
      });
      await tester.tap(find.text('Remove reminder'));
      await tester.pumpAndSettle();
      expect(await store.get('__reminder', 'session:s1'), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a closed parking offers no reminder', (tester) async {
      // A tall surface, so "not there" is a real answer and not a lazy
      // ListView that simply has not built that far.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await store.put('session', 's1', closedSession('s1'));
      await pump(tester, ParkingDetailPage(store: store, sessionId: 's1'));

      expect(find.text('Pick a time…'), findsNothing);
      expect(find.text('Remove reminder'), findsNothing);
      expect(find.textContaining('device alert'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('when the parking ends', () {
    testWidgets('«Found my car» clears the reminder with it', (tester) async {
      await store.put('session', 's1', openSession('s1'));
      await store.put('__reminder', 'session:s1', {
        'sourceKind': 'session',
        'sourceId': 's1',
        'at': DateTime.now()
            .add(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'title': 'Parking',
        'body': 'Paid time',
      });
      await pump(tester, ParkingScreen(store: store));

      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();

      final saved = await store.get('session', 's1');
      expect(saved!['foundAt'], isNotNull);
      expect(await store.get('__reminder', 'session:s1'), isNull);
      // The card is gone from the open list, and nothing was left dangling.
      expect(find.text('Pick a time…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('finding an unknown parking changes nothing', () async {
      // A record that vanished between the screen and the tap must not
      // resurrect a reminder or throw.
      await ParkingRepository.found(store, 'missing');
      final saved = await store.get('session', 'missing');
      expect(saved, isNull);
    });
  });
}
