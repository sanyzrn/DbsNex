import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/controller.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';
import 'package:nex_client/modules/maintenance/asset_editor.dart';
import 'package:nex_client/modules/maintenance/event_editor.dart';
import 'package:nex_client/modules/maintenance/rule_editor.dart';
import 'package:nex_client/modules/maintenance/reading_editor.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  late MaintenanceController controller;
  late MaintenanceAsset asset;
  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_widgets_');
    store = NexModuleStore(h.services, 'maintenance');
    controller = MaintenanceController(store);
    asset = MaintenanceAsset(
      id: 'a',
      nickname: 'Car',
      type: 'car',
      meterKind: MeterKind.distance,
      distanceUnit: DistanceUnit.km,
    );
    await controller.saveAsset(asset);
  });
  tearDown(() async {
    controller.dispose();
    await h.dispose();
  });
  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open, {
    bool small = false,
    bool fa = false,
  }) async {
    tester.view.physicalSize = small
        ? const Size(320, 480)
        : const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(fa ? 'fa' : 'en'),
        theme: fa ? nexDarkTheme() : nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            disableAnimations: small,
          ),
          child: child!,
        ),
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

  testWidgets('current reading writes independently with Persian decimals', (
    tester,
  ) async {
    await host(
      tester,
      (context) =>
          showReadingEditor(context, controller: controller, asset: asset),
    );
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-current-meter')),
      '۱۲۳٫۴۵۶',
    );
    await tester.tap(find.byKey(const ValueKey('maintenance-reading-save')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30 && (await store.list('reading')).isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(await store.list('reading'), hasLength(1));
    expect((await store.list('reading')).single.body['value'], 123456);
    expect(await store.list('event'), isEmpty);
    expect(await store.list('draft'), isEmpty);
  });
  testWidgets('raw current-reading draft survives keep and reopen', (
    tester,
  ) async {
    await host(
      tester,
      (context) =>
          showReadingEditor(context, controller: controller, asset: asset),
    );
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-current-meter')),
      '۱۲٫',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep draft & close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('maintenance-current-meter')),
    );
    expect(field.controller!.text, '۱۲٫');
    expect(await store.list('reading'), isEmpty);
  });
  testWidgets('typed cost without currency is refused and kept', (
    tester,
  ) async {
    await host(
      tester,
      (context) =>
          showEventEditor(context, controller: controller, asset: asset),
    );
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-task')),
      'Oil',
    );
    await tester.enterText(
      find.byKey(const ValueKey('maintenance-cost')),
      '12.5',
    );
    await tester.tap(find.byKey(const ValueKey('maintenance-event-save')));
    await tester.pumpAndSettle();
    expect(await store.list('event'), isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('maintenance-cost')))
          .controller!
          .text,
      '12.5',
    );
    expect(tester.takeException(), isNull);
  });
  for (final fa in [false, true]) {
    for (final kind in ['asset', 'event', 'rule', 'reading']) {
      testWidgets(
        '$kind editor at 320x480, scale 2, ${fa ? 'Persian dark' : 'English light'}',
        (tester) async {
          await host(
            tester,
            (context) => switch (kind) {
              'asset' => showAssetEditor(context, controller: controller),
              'event' => showEventEditor(
                context,
                controller: controller,
                asset: asset,
              ),
              'rule' => showRuleEditor(
                context,
                controller: controller,
                asset: asset,
              ),
              _ => showReadingEditor(
                context,
                controller: controller,
                asset: asset,
              ),
            },
            small: true,
            fa: fa,
          );
          expect(tester.takeException(), isNull);
          final save = find.byKey(
            ValueKey(
              'maintenance-${kind == 'reading' ? 'reading' : kind}-save',
            ),
          );
          expect(save, findsOneWidget);
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
