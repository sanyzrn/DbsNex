import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_repository.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';
import 'package:nex_client/modules/warranty/warranty_editor.dart';
import 'package:nex_client/modules/warranty/warranty_parse.dart';
import 'package:nex_client/modules/warranty/warranty_fields.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/local_values.dart';
import 'package:nex_client/modules/warranty/local_writes.dart';
import '../../support/nex_harness.dart';

import 'warranty_fault_store.dart';

part 'warranty_reliability_cases.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore inner;
  late FaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'warranty_reliability_');
    inner = NexModuleStore(h.services, 'warranty');
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
    await tester.pumpWidget(host(WarrantyEditorSheet(store: store)));
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
    await tester.pumpWidget(host(WarrantyEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-product')),
      'Draft example',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final keep = find.byKey(const ValueKey('warranty-keep-draft'));
    await Scrollable.ensureVisible(tester.element(keep), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(keep);
    await tester.pumpAndSettle();
    final draft = await inner.get('draft', 'warranty:new');
    expect((draft!['fields'] as Map)['product'], 'Draft example');
    final id = (draft['fields'] as Map)['recordId'];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(WarrantyEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('warranty-field-product')),
          )
          .controller!
          .text,
      'Draft example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-product')),
      'Draft updated',
    );
    await tester.pumpAndSettle();
    expect(
      ((await inner.get('draft', 'warranty:new'))!['fields']
          as Map)['recordId'],
      id,
    );
    expect(await inner.list('warranty'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('civil dates retain the written day across timezone offsets', () {
    final date = WarrantyModels.readDate({
      'coverageEnd': '2026-10-13T00:00:00+03:30',
    }, 'coverageEnd');
    expect(date, DateTime.utc(2026, 10, 13));
    final instant = WarrantyModels.readDate({
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
      'fields': {'product': 'Kept text', 'recordId': 'saved-id'},
    };
    await inner.put('draft', 'warranty:new', original);
    store.failDraft = true;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => nexShowSheet<void>(
              context: context,
              dismissible: false,
              builder: (_) => WarrantyEditorSheet(store: store),
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
    expect(find.byType(WarrantyEditorSheet), findsNothing);
    expect(await inner.get('draft', 'warranty:new'), original);
    expect(tester.takeException(), isNull);
  });
  test('strict dates refuse normalization, Arabic and Persian digits work', () {
    expect(LocalValues.day('2026/02/30'), isNull);
    expect(LocalValues.day('2026/13/01'), isNull);
    expect(LocalValues.day('٢٠٢٤/٠٢/٢٩'), DateTime(2024, 2, 29));
    expect(
      WarrantyModels.readDate({'at': '2026-02-30T12:00:00Z'}, 'at'),
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
      expect(WarrantyModels.readCount({'n': raw}, 'n'), isNull);
    }
    expect(LocalValues.writtenCount('۹۰۰۷۱۹۹۲۵۴۷۴۰۹۹۱'), LocalValues.maxExact);
    expect(LocalValues.writtenCount('9007199254740992'), isNull);
  });
  test('rollback recovers raw bodies and refuses stale Undo', () async {
    final original = {
      'v': 1,
      'future': {'value': 'keep'},
    };
    await inner.put('warranty', 'item', original);
    await inner.put('child', 'child', {'parent': 'item', 'unknown': true});
    store.failDelete = 'warranty';
    await expectLater(
      LocalWrites.delete(
        store,
        'warranty',
        'item',
        children: 'child',
        parentField: 'parent',
      ),
      throwsStateError,
    );
    expect(await inner.get('warranty', 'item'), original);
    expect(await inner.get('child', 'child'), {
      'parent': 'item',
      'unknown': true,
    });
    final undo = await LocalWrites.delete(
      store,
      'warranty',
      'item',
      children: 'child',
      parentField: 'parent',
    );
    await undo();
    expect(await inner.get('warranty', 'item'), original);
    final undo2 = await LocalWrites.delete(store, 'warranty', 'item');
    await inner.put('warranty', 'item', {'later': true});
    await expectLater(undo2(), throwsStateError);
    expect(await inner.get('warranty', 'item'), {'later': true});
  });
  test('reopen rolls back a crash, keeps committed operation intact', () async {
    await inner.put('warranty', 'item', {'value': 'after'});
    final before = [
      {
        'kind': 'warranty',
        'id': 'item',
        'body': {'value': 'before'},
      },
    ];
    await inner.put('operation', 'pending', {'v': 1, 'before': before});
    await LocalWrites.recover(store);
    expect(await inner.get('warranty', 'item'), {'value': 'before'});
    await inner.put('warranty', 'item', {'value': 'committed'});
    await inner.put('operation', 'pending', {
      'v': 1,
      'before': before,
      'committed': true,
    });
    await LocalWrites.recover(store);
    expect(await inner.get('warranty', 'item'), {'value': 'committed'});
    expect(await inner.list('operation'), isEmpty);
  });
  testWidgets('list read failure shows a working Retry', (tester) async {
    store.failList = true;
    await tester.pumpWidget(host(WarrantyScreen(store: store)));
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
      'fields': {'product': 'Keep text', 'recordId': 'stable'},
    };
    await inner.put('draft', 'warranty:new', original);
    store.failDraft = true;
    await tester.pumpWidget(host(WarrantyEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(await inner.get('draft', 'warranty:new'), original);
    store.failDraft = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    final text = tester
        .widget<TextField>(find.byKey(const ValueKey('warranty-field-product')))
        .controller!
        .text;
    expect(text, 'Keep text');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps raw input; retry writes only one record', (
    tester,
  ) async {
    store.failPut = 'warranty';
    await tester.pumpWidget(host(WarrantyEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-product')),
      'Example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-purchase')),
      '2026/10/13',
    );
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-end')),
      '2027/10/13',
    );
    final save = find.byKey(const ValueKey('warranty-save'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await inner.list('warranty'), isEmpty);
    expect(find.byKey(const ValueKey('warranty-save')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('warranty-field-product')),
          )
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
    expect(await inner.list('warranty'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  _registerWarrantyCases(() => store, () => inner, host);
}
