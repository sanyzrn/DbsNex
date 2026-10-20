import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_repository.dart';
import 'package:nex_client/modules/medicine/medicine_screen.dart';
import 'package:nex_client/modules/medicine/medicine_editor.dart';
import 'package:nex_client/modules/medicine/medicine_parse.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/local_values.dart';
import 'package:nex_client/modules/medicine/local_writes.dart';
import '../../support/more_details.dart';
import '../../support/nex_harness.dart';

import 'medicine_fault_store.dart';

part 'medicine_reliability_cases.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore inner;
  late FaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'medicine_reliability_');
    inner = NexModuleStore(h.services, 'medicine');
    store = FaultStore(inner);
  });
  tearDown(() => h.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  testWidgets('two retry taps share one checkpoint read', (tester) async {
    store.failDraft = true;
    await tester.pumpWidget(host(MedicineEditorSheet(store: store)));
    await tester.pumpAndSettle();
    store.failDraft = false;
    store.pauseDraft = Completer<void>();
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(store.draftReads, 2);
    store.pauseDraft!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('explicit kept draft resumes raw text with stable identity', (
    tester,
  ) async {
    await tester.pumpWidget(host(MedicineEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-name')),
      'Draft example',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final keep = find.byKey(const ValueKey('medicine-keep-draft'));
    await Scrollable.ensureVisible(tester.element(keep), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(keep);
    await tester.pumpAndSettle();
    final draft = await inner.get('draft', 'medicine:new');
    expect((draft!['fields'] as Map)['name'], 'Draft example');
    final id = (draft['fields'] as Map)['recordId'];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(MedicineEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('medicine-field-name')))
          .controller!
          .text,
      'Draft example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-name')),
      'Draft updated',
    );
    await tester.pumpAndSettle();
    expect(
      ((await inner.get('draft', 'medicine:new'))!['fields']
          as Map)['recordId'],
      id,
    );
    expect(await inner.list('medicine'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('civil dates retain the written day across timezone offsets', () {
    final date = MedicineModels.readDate({
      'expiresAt': '2026-10-13T00:00:00+03:30',
    }, 'expiresAt');
    expect(date, DateTime.utc(2026, 10, 13));
    final instant = MedicineModels.readDate({
      'at': '2026-10-13T00:00:00+03:30',
    }, 'at');
    expect(instant, DateTime.utc(2026, 10, 12, 20, 30));
  });
  testWidgets('Back exits a failed draft read without replacing data', (
    tester,
  ) async {
    final original = {
      'v': 1,
      'base': '{}',
      'fields': {'name': 'Kept text', 'recordId': 'saved-id'},
    };
    await inner.put('draft', 'medicine:new', original);
    store.failDraft = true;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => nexShowSheet<void>(
              context: context,
              dismissible: false,
              builder: (_) => MedicineEditorSheet(store: store),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MedicineEditorSheet), findsNothing);
    expect(await inner.get('draft', 'medicine:new'), original);
    expect(tester.takeException(), isNull);
  });
  test('strict dates refuse normalization, Arabic and Persian digits work', () {
    expect(LocalValues.day('2026/02/30'), isNull);
    expect(LocalValues.day('2026/13/01'), isNull);
    expect(LocalValues.day('٢٠٢٤/٠٢/٢٩'), DateTime(2024, 2, 29));
    expect(
      MedicineModels.readDate({'at': '2026-02-30T12:00:00Z'}, 'at'),
      isNull,
    );
    expect(LocalValues.stamp('2026-02-28T24:00:00'), isNull);
    expect(LocalValues.stamp('2026-02-28T12:00:00+25:00'), isNull);
    expect(
      LocalValues.stamp('2026-02-28T12:00:00Z'),
      DateTime.utc(2026, 2, 28, 12),
    );
  });
  test('JSON counters stay finite, integral and exact', () {
    for (final raw in [
      -1,
      1.5,
      double.nan,
      double.infinity,
      9007199254740992,
    ]) {
      expect(MedicineModels.readCount({'n': raw}, 'n'), isNull);
    }
    expect(LocalValues.writtenCount('۹۰۰۷۱۹۹۲۵۴۷۴۰۹۹۱'), LocalValues.maxExact);
    expect(LocalValues.writtenCount('9007199254740992'), isNull);
  });
  test('rollback recovers raw bodies and refuses stale Undo', () async {
    final original = {
      'v': 1,
      'future': {'value': 'keep'},
    };
    await inner.put('medicine', 'item', original);
    await inner.put('child', 'child', {'parent': 'item', 'unknown': true});
    store.failDelete = 'medicine';
    await expectLater(
      LocalWrites.delete(
        store,
        'medicine',
        'item',
        children: 'child',
        parentField: 'parent',
      ),
      throwsStateError,
    );
    expect(await inner.get('medicine', 'item'), original);
    expect(await inner.get('child', 'child'), {
      'parent': 'item',
      'unknown': true,
    });
    final undo = await LocalWrites.delete(
      store,
      'medicine',
      'item',
      children: 'child',
      parentField: 'parent',
    );
    await undo();
    expect(await inner.get('medicine', 'item'), original);
    final undo2 = await LocalWrites.delete(store, 'medicine', 'item');
    await inner.put('medicine', 'item', {'later': true});
    await expectLater(undo2(), throwsStateError);
    expect(await inner.get('medicine', 'item'), {'later': true});
  });
  test('reopen rolls back a crash, keeps committed operation intact', () async {
    await inner.put('medicine', 'item', {'value': 'after'});
    final before = [
      {
        'kind': 'medicine',
        'id': 'item',
        'body': {'value': 'before'},
      },
    ];
    await inner.put('operation', 'pending', {'v': 1, 'before': before});
    await LocalWrites.recover(store);
    expect(await inner.get('medicine', 'item'), {'value': 'before'});
    await inner.put('medicine', 'item', {'value': 'committed'});
    await inner.put('operation', 'pending', {
      'v': 1,
      'before': before,
      'committed': true,
    });
    await LocalWrites.recover(store);
    expect(await inner.get('medicine', 'item'), {'value': 'committed'});
    expect(await inner.list('operation'), isEmpty);
  });
  testWidgets('list read failure shows a working Retry', (tester) async {
    store.failList = true;
    await tester.pumpWidget(host(MedicineScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    store.failList = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed draft read never destroys the checkpoint', (
    tester,
  ) async {
    final original = {
      'v': 1,
      'base': '{}',
      'fields': {'name': 'Keep text', 'recordId': 'stable'},
    };
    await inner.put('draft', 'medicine:new', original);
    store.failDraft = true;
    await tester.pumpWidget(host(MedicineEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(await inner.get('draft', 'medicine:new'), original);
    store.failDraft = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    final text = tester
        .widget<TextField>(find.byKey(const ValueKey('medicine-field-name')))
        .controller!
        .text;
    expect(text, 'Keep text');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps raw input; retry writes only one record', (
    tester,
  ) async {
    store.failPut = 'medicine';
    await tester.pumpWidget(host(MedicineEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-name')),
      'Example',
    );

    final save = find.byKey(const ValueKey('medicine-save'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await inner.list('medicine'), isEmpty);
    expect(find.byKey(const ValueKey('medicine-save')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('medicine-field-name')))
          .controller!
          .text,
      'Example',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await inner.list('medicine'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  _registerStockCases(() => store, () => inner, host);
}
