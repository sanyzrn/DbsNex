import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_editor.dart';
import 'package:nex_client/modules/parking/parking_repository.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_draft_merge_');
    store = NexModuleStore(h.services, 'parking');
  });
  tearDown(() => h.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  ModuleRecord record(String id, Map<String, Object?> body) => ModuleRecord(
    module: 'parking',
    kind: 'session',
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
        'vehicle': 'Car',
        'place': 'Original',
        'startedAt': '2026-10-13T12:00:00Z',
      };
      await store.put('session', 'r', original);
      await tester.pumpWidget(
        host(ParkingEditorSheet(store: store, existing: record('r', original))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-place')),
        'Typed correction',
      );
      await tap(tester, 'parking-keep-draft');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await ParkingRepository.found(store, 'r');
      final fresh = (await store.get('session', 'r'))!;
      await tester.pumpWidget(
        host(ParkingEditorSheet(store: store, existing: record('r', fresh))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('parking-field-place')),
            )
            .controller!
            .text,
        'Typed correction',
      );
      await tap(tester, 'parking-save');
      final saved = (await store.get('session', 'r'))!;
      expect(saved['place'], 'Typed correction');
      expect(saved['foundAt'], fresh['foundAt']);
      expect(tester.takeException(), isNull);
    },
  );
}
