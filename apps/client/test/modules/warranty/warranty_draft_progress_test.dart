import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_editor.dart';
import 'package:nex_client/modules/warranty/warranty_widgets.dart';
import 'package:nex_client/modules/warranty/local_writes.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'warranty_draft_merge_');
    store = NexModuleStore(h.services, 'warranty');
  });
  tearDown(() => h.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  ModuleRecord record(String id, Map<String, Object?> body) => ModuleRecord(
    module: 'warranty',
    kind: 'warranty',
    id: id,
    body: body,
    updatedAt: DateTime.now(),
  );
  Future<void> tap(WidgetTester tester, String key) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(ValueKey(key))),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'draft text survives progress changes without overwriting fresh fields',
    (tester) async {
      final original = {
        'v': 1,
        'product': 'Original',
        'purchasedAt': '2026-10-13',
        'coverageEnd': '2027-10-13',
      };
      await store.put('warranty', 'r', original);
      await tester.pumpWidget(
        host(
          WarrantyEditorSheet(store: store, existing: record('r', original)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-product')),
        'Typed correction',
      );
      await tap(tester, 'warranty-keep-draft');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await store.put('warranty', 'r', {...original, 'archived': true});
      final fresh = (await store.get('warranty', 'r'))!;
      await tester.pumpWidget(
        host(WarrantyEditorSheet(store: store, existing: record('r', fresh))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('warranty-field-product')),
            )
            .controller!
            .text,
        'Typed correction',
      );
      await tap(tester, 'warranty-save');
      final saved = (await store.get('warranty', 'r'))!;
      expect(saved['product'], 'Typed correction');
      expect(saved['archived'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('claim drafts are scoped and included in parent delete Undo', (
    tester,
  ) async {
    await store.put('warranty', 'a', {'product': 'A'});
    await store.put('warranty', 'b', {'product': 'B'});
    for (final parent in ['a', 'b']) {
      await tester.pumpWidget(
        host(WarrantyClaimSheet(store: store, parentId: parent, kind: 'claim')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-claim-field')),
        'Draft $parent',
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    expect(
      ((await store.get('draft', 'claim:a:claim:new'))!['fields']
          as Map)['note'],
      'Draft a',
    );
    expect(
      ((await store.get('draft', 'claim:b:claim:new'))!['fields']
          as Map)['note'],
      'Draft b',
    );
    final undo = await LocalWrites.delete(
      store,
      'warranty',
      'a',
      children: 'claim',
      parentField: 'warrantyId',
    );
    expect(await store.get('draft', 'claim:a:claim:new'), isNull);
    expect(await store.get('draft', 'claim:b:claim:new'), isNotNull);
    await undo();
    expect(
      ((await store.get('draft', 'claim:a:claim:new'))!['fields']
          as Map)['note'],
      'Draft a',
    );
    await tester.pumpWidget(
      host(WarrantyClaimSheet(store: store, parentId: 'a', kind: 'claim')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NexTextField>(
            find.descendant(
              of: find.byKey(const ValueKey('warranty-claim-field')),
              matching: find.byType(NexTextField),
            ),
          )
          .controller
          .text,
      'Draft a',
    );
    expect(tester.takeException(), isNull);
  });
}
