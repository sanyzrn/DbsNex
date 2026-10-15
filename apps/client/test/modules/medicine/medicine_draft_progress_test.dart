import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_editor.dart';
import 'package:nex_client/modules/medicine/medicine_repository.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'medicine_draft_merge_');
    store = NexModuleStore(h.services, 'medicine');
  });
  tearDown(() => h.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  ModuleRecord record(String id, Map<String, Object?> body) => ModuleRecord(
    module: 'medicine',
    kind: 'medicine',
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
        'name': 'Example',
        'quantity': 10,
        'doseUnits': 2,
      };
      await store.put('medicine', 'r', original);
      await tester.pumpWidget(
        host(
          MedicineEditorSheet(store: store, existing: record('r', original)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Typed correction',
      );
      await tap(tester, 'medicine-keep-draft');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await MedicineRepository.log(store, 'r', 'taken');
      final fresh = (await store.get('medicine', 'r'))!;
      await tester.pumpWidget(
        host(MedicineEditorSheet(store: store, existing: record('r', fresh))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('medicine-field-name')),
            )
            .controller!
            .text,
        'Typed correction',
      );
      await tap(tester, 'medicine-save');
      final saved = (await store.get('medicine', 'r'))!;
      expect(saved['name'], 'Typed correction');
      expect(saved['quantity'], 8);
      expect(saved['stockEpoch'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('archived detail cannot log a dose until unarchived', (
    tester,
  ) async {
    final body = {'name': 'Example', 'archived': true};
    await store.put('medicine', 'r', body);
    await tester.pumpWidget(
      host(MedicineDetailSheet(store: store, record: record('r', body))),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('medicine-taken')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('medicine-skipped')),
          )
          .onPressed,
      isNull,
    );
    expect(await store.list('dose'), isEmpty);
  });
}
