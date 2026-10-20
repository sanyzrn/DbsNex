import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';

import '../../support/nex_harness.dart';

/// The opt-in device reminder for an asset: the control the platform
/// provides, offered where a person manages the asset — its own page —
/// for the next service when it comes due, and cleared again with the
/// asset.
///
/// Scheduling itself needs the platform's notification permission and a
/// rolled-out module, so these tests stay honest to what a test build
/// can observe: the control sits on an active asset's page, Clearing
/// removes the stored reminder, and an archived asset offers nothing
/// (the platform cancels its reminders with the archive).
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_reminder_');
    store = NexModuleStore(h.services, 'maintenance');
  });
  tearDown(() => h.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    // A tall surface, so "not there" is a real answer and not a lazy
    // list that simply has not built that far.
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

  Future<void> putAsset({bool archived = false}) => store.put('asset', 'car', {
    'nickname': 'Daily car',
    'type': 'car',
    'meterKind': 'distance',
    'distanceUnit': 'km',
    'archived': archived,
  });

  testWidgets('an active asset offers the reminder on its page', (
    tester,
  ) async {
    await putAsset();
    await pump(tester);

    expect(find.byKey(const ValueKey('maintenance-reminders')), findsOneWidget);
    expect(find.text('Pick a time…'), findsOneWidget);
    expect(find.text('Remove reminder'), findsOneWidget);
    expect(find.textContaining('device alert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear removes the stored reminder for this asset', (
    tester,
  ) async {
    await putAsset();
    await store.put('__reminder', 'asset:car', {
      'sourceKind': 'asset',
      'sourceId': 'car',
      'at': DateTime.now()
          .add(const Duration(hours: 3))
          .toUtc()
          .toIso8601String(),
      'title': 'Nex reminder',
      'body': 'Next service',
    });
    await pump(tester);

    final clear = find.text('Remove reminder');
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(await store.get('__reminder', 'asset:car'), isNull);
    // The control stays, ready for another reminder.
    expect(find.text('Remove reminder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived asset offers no reminder', (tester) async {
    await putAsset(archived: true);
    await pump(tester);

    expect(find.text('Pick a time…'), findsNothing);
    expect(find.text('Remove reminder'), findsNothing);
    expect(find.textContaining('device alert'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing asset shows the gone message, no reminder', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const ValueKey('maintenance-reminders')), findsNothing);
    expect(find.text('This asset was removed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
