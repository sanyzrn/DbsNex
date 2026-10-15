import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';
import 'warranty_widget_test.dart'
    show addWarranty, pumpWarranty, scrollWarrantyTo;

/// The warranties screen, further along: claims kept as dated notes,
/// archiving and deleting with Undo, and the states that hold up —
/// persistence, isolation, Persian, dark, large text on a small phone.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) async {
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

void main() {
  group('claims', () {
    testWidgets('a dated claim note is kept with the purchase', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      await tester.tap(find.text('Kettle'));
      await tester.pumpAndSettle();
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-add-claim')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-add-claim')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-claim-field')),
        'Called the shop; part ordered.',
      );
      await tester.tap(find.byKey(const ValueKey('warranty-claim-save')));
      await tester.pumpAndSettle();
      final claims = await h.services.moduleRecords('warranty', 'claim');
      expect(claims, hasLength(1));
      expect(claims.single.body['kind'], WarrantyModels.claimKind);
      expect(claims.single.body['note'], 'Called the shop; part ordered.');

      // Deleting the note is a correction with Undo.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('warranty', 'claim'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('warranty-undo')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('warranty', 'claim'), hasLength(1));
    });
  });

  group('archived and deleted', () {
    testWidgets('archiving moves a purchase out, and it comes back', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      await tester.tap(find.text('Kettle'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('warranty-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      final stored = await h.services.moduleRecords('warranty', 'warranty');
      expect(stored.single.body['archived'], isTrue);
      expect(find.text('Kettle'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('warranty-archived-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('warranty-unarchive-${stored.single.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        (await h.services.moduleRecords(
          'warranty',
          'warranty',
        )).single.body['archived'],
        isFalse,
      );
    });

    testWidgets('deleting takes the claim notes, undo returns them all', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      await tester.tap(find.text('Kettle'));
      await tester.pumpAndSettle();
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-add-service')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-add-service')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-claim-field')),
        'Annual check.',
      );
      await tester.tap(find.byKey(const ValueKey('warranty-claim-save')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('warranty', 'claim'), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('warranty-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('warranty-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
      expect(await h.services.moduleRecords('warranty', 'claim'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('warranty-undo')));
      await tester.pumpAndSettle();
      expect(
        await h.services.moduleRecords('warranty', 'warranty'),
        hasLength(1),
      );
      expect(await h.services.moduleRecords('warranty', 'claim'), hasLength(1));
    });
  });

  group('persistence, isolation and appearance', () {
    testWidgets('a reopened screen finds everything where it was', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      await _pump(
        tester,
        WarrantyScreen(store: NexModuleStore(h.services, 'warranty')),
      );
      expect(find.text('Kettle'), findsWidgets);
    });

    testWidgets('another module sees none of it', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      expect(await h.services.moduleRecords('other', 'warranty'), isEmpty);
    });

    testWidgets('Persian reads right to left, in Persian words', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'warranty_fa_');
      addTearDown(h.dispose);
      await _pump(
        tester,
        WarrantyScreen(store: NexModuleStore(h.services, 'warranty')),
        locale: const Locale('fa'),
      );
      expect(find.text('ضمانت‌نامه‌ها'), findsOneWidget);
      expect(
        Directionality.of(tester.state(find.byType(Scaffold)).context),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark, twice the text, a small phone', (tester) async {
      final h = await NexTestHarness.create(name: 'warranty_look_');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: WarrantyScreen(store: NexModuleStore(h.services, 'warranty')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('warranty-fab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
