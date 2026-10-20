import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_detail.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';

import '../../support/nex_harness.dart';

/// Every date a person reads, in the person's own calendar: the history
/// row and the detail page. A Persian reader sees Jalali with Persian
/// digits; an English one sees Gregorian; storage stays ISO 8601 instants.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_dates_');
    store = NexModuleStore(h.services, 'parking');
  });
  tearDown(() => h.dispose);

  // 2024-02-29 08:30 UTC is 1402/12/10 in the Persian calendar. The test
  // zone is UTC, so the stored instant reads back as that same civil day.
  final started = DateTime.utc(2024, 2, 29, 8, 30);

  Future<void> pump(WidgetTester tester, Widget home, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an English reader sees the civil date', (tester) async {
    await store.put('session', 's1', {
      'v': 1,
      'vehicle': 'Car',
      'place': 'Library',
      'startedAt': started.toIso8601String(),
      'foundAt': started.add(const Duration(hours: 2)).toIso8601String(),
    });
    await pump(tester, ParkingScreen(store: store), const Locale('en'));

    expect(find.textContaining('2024/02/29'), findsOneWidget);
    expect(find.textContaining('1402'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Persian reader sees Jalali, in Persian digits', (
    tester,
  ) async {
    await store.put('session', 's1', {
      'v': 1,
      'vehicle': 'Car',
      'place': 'کتابخانه',
      'startedAt': started.toIso8601String(),
      'foundAt': started.add(const Duration(hours: 2)).toIso8601String(),
    });
    await pump(tester, ParkingScreen(store: store), const Locale('fa'));

    expect(find.textContaining('۱۴۰۲/۱۲/۱۰'), findsOneWidget);
    // Never the civil date in Latin digits, never a Gregorian label.
    expect(find.textContaining('2024/02/29'), findsNothing);
    expect(find.textContaining('میلادی'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the detail page shows the date and the time together', (
    tester,
  ) async {
    await store.put('session', 's1', {
      'v': 1,
      'vehicle': 'Car',
      'place': 'Library',
      'startedAt': started.toIso8601String(),
      'foundAt': started.add(const Duration(hours: 2)).toIso8601String(),
      'expiresAt': started.add(const Duration(hours: 3)).toIso8601String(),
    });
    await pump(
      tester,
      ParkingDetailPage(store: store, sessionId: 's1'),
      const Locale('fa'),
    );

    expect(find.textContaining('۱۴۰۲/۱۲/۱۰ · ۰۸:۳۰'), findsOneWidget);
    // Started, found and the paid-until moment all read in full.
    expect(find.textContaining('۱۱:۳۰'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the detail page in English reads Gregorian and 24-hour', (
    tester,
  ) async {
    await store.put('session', 's1', {
      'v': 1,
      'vehicle': 'Car',
      'place': 'Library',
      'startedAt': started.toIso8601String(),
    });
    await pump(
      tester,
      ParkingDetailPage(store: store, sessionId: 's1'),
      const Locale('en'),
    );

    expect(find.textContaining('2024/02/29 · 08:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a parking from today says today, in both words', (tester) async {
    final now = DateTime.now();
    await store.put('session', 's1', {
      'v': 1,
      'vehicle': 'Car',
      'place': 'Library',
      'startedAt': now.subtract(const Duration(minutes: 90)).toIso8601String(),
      'foundAt': now.toIso8601String(),
    });
    await pump(tester, ParkingScreen(store: store), const Locale('fa'));
    expect(find.textContaining('امروز'), findsOneWidget);
    await pump(tester, ParkingScreen(store: store), const Locale('en'));
    expect(find.textContaining('today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
