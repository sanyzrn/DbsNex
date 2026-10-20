import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_editor.dart';
import 'package:nex_client/modules/maintenance/controller.dart';
import 'package:nex_client/modules/maintenance/event_editor.dart';
import 'package:nex_client/modules/maintenance/logic.dart';
import 'package:nex_client/modules/maintenance/maintenance_screen.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';

import '../../support/nex_harness.dart';

/// The pieces this upgrade added or fixed, end to end over a real
/// store: the shared multiline note fields, the delete notice that
/// used to show a raw string key in Persian, the archive notice with
/// its guarded Undo, and the deterministic same-instant orders.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_flows_');
    store = NexModuleStore(h.services, 'maintenance');
  });
  tearDown(() => h.dispose());

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open, {
    bool fa = false,
  }) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(fa ? 'fa' : 'en'),
        theme: fa ? nexDarkTheme() : nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(
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
        theme: nexLightTheme(),
        home: MaintenanceScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addAsset(
    WidgetTester tester, {
    String name = 'My car',
    bool persian = false,
  }) async {
    await tester.tap(find.byKey(const ValueKey('maintenance-add-asset')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-nickname')),
      name,
    );
    final odometer = find.descendant(
      of: find.byKey(const ValueKey('maintenance-meterkind')),
      matching: find.text(persian ? 'کیلومترشمار' : 'Odometer'),
    );
    await tester.ensureVisible(odometer);
    await tester.pumpAndSettle();
    await tester.tap(odometer);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('maintenance-asset-save')));
    await tester.pumpAndSettle();
  }

  group('the shared multiline note fields', () {
    testWidgets('service notes are multiline and survive the save', (
      tester,
    ) async {
      final controller = MaintenanceController(store);
      addTearDown(controller.dispose);
      final asset = MaintenanceAsset(
        id: 'a',
        nickname: 'Car',
        type: 'car',
        meterKind: MeterKind.distance,
        distanceUnit: DistanceUnit.km,
      );
      await controller.saveAsset(asset);
      await host(
        tester,
        (context) =>
            showEventEditor(context, controller: controller, asset: asset),
      );

      final field = find.byKey(const ValueKey('maintenance-event-notes'));
      // The key sits on the shared wrapper; the editor itself is below it.
      final editor = find.descendant(
        of: field,
        matching: find.byType(TextField),
      );
      expect(editor, findsOneWidget);
      final widget = tester.widget<TextField>(editor);
      expect(widget.maxLines, 4);
      expect(widget.minLines, 2);

      await tester.enterText(
        find.byKey(const ValueKey('maintenance-task')),
        'Oil',
      );
      await tester.enterText(field, 'first line\nsecond line');
      // The focused field schedules its own scroll-into-view; let it
      // settle before reaching for the save button.
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('maintenance-event-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && (await store.list('event')).isEmpty; i++) {
        await tester.pumpAndSettle();
      }
      expect(
        (await store.get(
          'event',
          (await store.list('event')).single.id,
        ))?['notes'],
        'first line\nsecond line',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('asset notes are the same shared multiline editor', (
      tester,
    ) async {
      final controller = MaintenanceController(store);
      addTearDown(controller.dispose);
      await host(
        tester,
        (context) => showAssetEditor(context, controller: controller),
      );
      final editor = find.descendant(
        of: find.byKey(const ValueKey('maintenance-notes')),
        matching: find.byType(TextField),
      );
      expect(editor, findsOneWidget);
      expect(tester.widget<TextField>(editor).maxLines, 4);
      expect(tester.takeException(), isNull);
    });
  });

  group('notices', () {
    testWidgets('deleting an interval says so in Persian, not a raw key', (
      tester,
    ) async {
      await pumpScreen(tester, locale: const Locale('fa'));
      await addAsset(tester, name: 'خودم', persian: true);
      await tester.tap(find.text('خودم'));
      await tester.pumpAndSettle();

      // A six-day interval for the oil change.
      await tester.tap(find.text('بازه‌ی جدید'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rule-task')),
        'تعویض روغن',
      );
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rule-time')),
        '6',
      );
      await tester.tap(find.byKey(const ValueKey('maintenance-rule-save')));
      await tester.pumpAndSettle();
      expect(find.text('تعویض روغن'), findsAtLeast(1));

      // Open the rule and delete it.
      await tester.tap(find.text('تعویض روغن').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('maintenance-rule-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف').last);
      await tester.pumpAndSettle();

      // The SnackBar speaks Persian; the missing-key bug showed the
      // raw map key instead.
      expect(find.text('بازه حذف شد'), findsOneWidget);
      expect(find.text('deletedRule'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('archiving says so, and Undo un-archives', (tester) async {
      await pumpScreen(tester);
      await addAsset(tester);
      await tester.tap(find.text('My car'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      expect(find.text('Archive this asset?'), findsOneWidget);
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();

      // The notice on the page that stayed open.
      expect(find.text('Archived'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Back home the asset is active again, not in the archived group.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No schedule · 1'), findsOneWidget);
      expect(find.text('Archived · 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('deterministic orders', () {
    test('same-date services fall back to the id, newest id first', () {
      final a = ServiceEvent(
        id: 'event-1',
        assetId: 'a',
        task: 'Oil',
        date: DateTime(2026, 6, 1),
      );
      final b = ServiceEvent(
        id: 'event-2',
        assetId: 'a',
        task: 'Wash',
        date: DateTime(2026, 6, 1),
      );
      // Newest first: the larger id sorts before the smaller one.
      expect(compareServices(a, b), greaterThan(0));
      expect(compareServices(b, a), lessThan(0));
    });

    test('same-instant readings pick one stable winner', () {
      final asset = MaintenanceAsset(
        id: 'a',
        nickname: 'Car',
        type: 'car',
        meterKind: MeterKind.hours,
        distanceUnit: DistanceUnit.km,
      );
      final at = DateTime(2026, 10, 14, 10);
      final older = MaintenanceReading(
        id: 'reading-1',
        assetId: 'a',
        value: 100,
        kind: MeterKind.hours,
        at: at,
      );
      final newer = MaintenanceReading(
        id: 'reading-2',
        assetId: 'a',
        value: 200,
        kind: MeterKind.hours,
        at: at,
      );
      final first = latestEnteredMeter(asset, const [], [older, newer], at);
      final second = latestEnteredMeter(asset, const [], [newer, older], at);
      // Whichever order the store returned them in, the answer is the
      // same record — not the sort's accident.
      expect(first!.value, second!.value);
      expect(first.value, 200);
    });
  });
}
