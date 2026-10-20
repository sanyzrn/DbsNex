import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_detail.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';

import '../../support/nex_harness.dart';
import 'warranty_widget_test.dart' show scrollWarrantyTo;

/// The opt-in device reminder on a purchase: the control the platform
/// provides, offered where a person manages the purchase — its detail
/// sheet — for the end of the coverage or a claim deadline, and cleared
/// again with the purchase.
///
/// Scheduling itself needs the platform's notification permission and a
/// rolled-out module, so these tests stay honest to what a test build can
/// observe: the control sits on the detail sheet of an active purchase,
/// Clearing removes the stored reminder, and an archived purchase offers
/// nothing (the platform cancels its reminders with the archive).
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'warranty_reminder_');
    store = NexModuleStore(h.services, 'warranty');
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

  Map<String, Object?> activeBody() => {
    'v': 1,
    'product': 'Kettle',
    'purchasedAt': '2026-10-13',
    'coverageEnd': '2030-10-13',
  };

  ModuleRecord purchase(Map<String, Object?> body) => ModuleRecord(
    module: 'warranty',
    kind: WarrantyModels.warranty,
    id: 'w1',
    body: body,
    updatedAt: DateTime.now(),
  );

  testWidgets('an active purchase offers the reminder on its detail sheet', (
    tester,
  ) async {
    await store.put('warranty', 'w1', activeBody());
    await pump(
      tester,
      WarrantyDetailSheet(store: store, record: purchase(activeBody())),
    );

    expect(find.byKey(const ValueKey('warranty-reminders')), findsOneWidget);
    expect(find.text('Pick a time…'), findsOneWidget);
    expect(find.text('Remove reminder'), findsOneWidget);
    expect(find.textContaining('device alert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear removes the stored reminder for this purchase', (
    tester,
  ) async {
    await store.put('warranty', 'w1', activeBody());
    await store.put('__reminder', 'warranty:w1', {
      'sourceKind': 'warranty',
      'sourceId': 'w1',
      'at': DateTime.now()
          .add(const Duration(hours: 3))
          .toUtc()
          .toIso8601String(),
      'title': 'Nex reminder',
      'body': 'Coverage',
    });
    await pump(
      tester,
      WarrantyDetailSheet(store: store, record: purchase(activeBody())),
    );

    final clear = find.text('Remove reminder');
    await scrollWarrantyTo(tester, clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(await store.get('__reminder', 'warranty:w1'), isNull);
    // The control stays, ready for another reminder.
    expect(find.text('Remove reminder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived purchase offers no reminder', (tester) async {
    // A tall surface, so "not there" is a real answer and not a scroll
    // view that simply has not built that far.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final body = {...activeBody(), 'archived': true};
    await store.put('warranty', 'w1', body);
    await pump(
      tester,
      WarrantyDetailSheet(store: store, record: purchase(body)),
    );

    expect(find.text('Pick a time…'), findsNothing);
    expect(find.text('Remove reminder'), findsNothing);
    expect(find.textContaining('device alert'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
