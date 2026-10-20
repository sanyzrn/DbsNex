import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';

import '../../support/nex_harness.dart';

/// The shared calendar labels: every absolute date the person reads —
/// a rule's due date, a service's day — follows their saved calendar
/// (Jalali with Persian digits for a solar reader), and the editors
/// carry no module-owned "Gregorian" annotation any more.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_dates_');
    store = NexModuleStore(h.services, 'maintenance');
  });
  tearDown(() => h.dispose());

  // A fixed, historic service: its 6-month due date (2020-07-15) is
  // always in the past, so the row shows the "due since" fact with an
  // absolute date — the one label that must follow the calendar.
  Future<void> putRecords() async {
    await store.put('asset', 'car', {
      'nickname': 'Daily car',
      'type': 'car',
      'meterKind': 'distance',
      'distanceUnit': 'km',
      'archived': false,
    });
    await store.put('event', 'oil', {
      'assetId': 'car',
      'task': 'Oil change',
      'date': '2020-01-15T00:00:00',
      'meter': 45000,
      'meterUnit': 'km',
    });
    await store.put('rule', 'oil-rule', {
      'assetId': 'car',
      'task': 'Oil change',
      'months': 6,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssetPage(store: store, assetId: 'car'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('English reads shared civil date labels', (tester) async {
    await putRecords();
    await pump(tester);

    // The rule's overdue fact and the service's day, in the shared
    // zero-padded civil form the app uses everywhere. The service day
    // also feeds the meter panel's "entered on" line.
    expect(find.text('Due since 2020/07/15'), findsOneWidget);
    expect(find.textContaining('2020/01/15'), findsAtLeast(1));
    expect(find.text('January'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian reads Jalali dates with Persian digits', (tester) async {
    await putRecords();
    // A service logged today keeps its relative word — and proves the
    // Persian side still reads naturally where relative is better.
    await store.put('event', 'today-oil', {
      'assetId': 'car',
      'task': 'Wash',
      'date': DateTime.now().toIso8601String(),
    });
    await pump(tester, locale: const Locale('fa'));

    // 2020-01-15 is Jalali 1398, its 6-month due date 2020-07-15 is
    // Jalali 1399: the absolute dates follow the solar calendar.
    expect(find.textContaining('۱۳۹۸'), findsAtLeast(1));
    expect(find.textContaining('۱۳۹۹'), findsOneWidget);
    expect(find.textContaining('امروز'), findsAtLeast(1));
    // The retired module-owned annotation is gone in Persian.
    expect(find.text('میلادی'), findsNothing);
    expect(find.text('ژانویه'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editors carry no calendar annotation', (tester) async {
    await putRecords();
    await pump(tester);

    // The service editor's date row: the shared calendar picker's
    // affordance, no "Gregorian" label under it.
    await tester.tap(find.byKey(const ValueKey('maintenance-log-service')));
    await tester.pumpAndSettle();
    expect(find.text('Gregorian'), findsNothing);
    expect(find.byTooltip('Change the date'), findsOneWidget);
    // The sheet has no × — it closes the way back does.
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();

    // The asset editor's purchased-date row: same.
    await tester.tap(find.byTooltip('Edit asset'));
    await tester.pumpAndSettle();
    expect(find.text('Gregorian'), findsNothing);
    expect(find.text('شمسی'), findsNothing);
    expect(find.byTooltip('Change the date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
