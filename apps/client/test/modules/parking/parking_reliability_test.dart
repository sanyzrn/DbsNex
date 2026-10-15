import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_repository.dart';
import 'package:nex_client/modules/parking/parking_writes.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import 'package:nex_client/modules/parking/parking_editor.dart';
import 'package:nex_client/modules/parking/parking_parse.dart';
import 'package:nex_client/modules/parking/parking_models.dart';
import 'package:nex_client/modules/parking/local_values.dart';
import 'package:nex_client/modules/parking/local_writes.dart';
import '../../support/nex_harness.dart';

import 'parking_fault_store.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore inner;
  late FaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_reliability_');
    inner = NexModuleStore(h.services, 'parking');
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
    await tester.pumpWidget(host(ParkingEditorSheet(store: store)));
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
    await tester.pumpWidget(host(ParkingEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-place')),
      'Draft example',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final keep = find.byKey(const ValueKey('parking-keep-draft'));
    await Scrollable.ensureVisible(tester.element(keep), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(keep);
    await tester.pumpAndSettle();
    final draft = await inner.get('draft', 'session:new');
    expect((draft!['fields'] as Map)['place'], 'Draft example');
    final id = (draft['fields'] as Map)['recordId'];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(ParkingEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('parking-field-place')))
          .controller!
          .text,
      'Draft example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-place')),
      'Draft updated',
    );
    await tester.pumpAndSettle();
    expect(
      ((await inner.get('draft', 'session:new'))!['fields'] as Map)['recordId'],
      id,
    );
    expect(await inner.list('session'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Back exits a failed draft read without replacing data', (
    tester,
  ) async {
    final original = {
      'v': 1,
      'base': '{}',
      'fields': {'place': 'Kept text', 'recordId': 'saved-id'},
    };
    await inner.put('draft', 'session:new', original);
    store.failDraft = true;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => nexShowSheet<void>(
              context: context,
              dismissible: false,
              builder: (_) => ParkingEditorSheet(store: store),
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
    expect(find.byType(ParkingEditorSheet), findsNothing);
    expect(await inner.get('draft', 'session:new'), original);
    expect(tester.takeException(), isNull);
  });
  test('strict dates refuse normalization, Arabic and Persian digits work', () {
    expect(LocalValues.day('2026/02/30'), isNull);
    expect(LocalValues.day('2026/13/01'), isNull);
    expect(LocalValues.day('٢٠٢٤/٠٢/٢٩'), DateTime(2024, 2, 29));
    expect(
      ParkingModels.readDate({'at': '2026-02-30T12:00:00Z'}, 'at'),
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
      expect(ParkingModels.readCount({'n': raw}, 'n'), isNull);
    }
    expect(LocalValues.writtenCount('۹۰۰۷۱۹۹۲۵۴۷۴۰۹۹۱'), LocalValues.maxExact);
    expect(LocalValues.writtenCount('9007199254740992'), isNull);
  });
  test('rollback recovers raw bodies and refuses stale Undo', () async {
    final original = {
      'v': 1,
      'future': {'value': 'keep'},
    };
    await inner.put('session', 'item', original);
    await inner.put('child', 'child', {'parent': 'item', 'unknown': true});
    store.failDelete = 'session';
    await expectLater(
      LocalWrites.delete(
        store,
        'session',
        'item',
        children: 'child',
        parentField: 'parent',
      ),
      throwsStateError,
    );
    expect(await inner.get('session', 'item'), original);
    expect(await inner.get('child', 'child'), {
      'parent': 'item',
      'unknown': true,
    });
    final undo = await LocalWrites.delete(
      store,
      'session',
      'item',
      children: 'child',
      parentField: 'parent',
    );
    await undo();
    expect(await inner.get('session', 'item'), original);
    final undo2 = await LocalWrites.delete(store, 'session', 'item');
    await inner.put('session', 'item', {'later': true});
    await expectLater(undo2(), throwsStateError);
    expect(await inner.get('session', 'item'), {'later': true});
  });
  test('reopen rolls back a crash, keeps committed operation intact', () async {
    await inner.put('session', 'item', {'value': 'after'});
    final before = [
      {
        'kind': 'session',
        'id': 'item',
        'body': {'value': 'before'},
      },
    ];
    await inner.put('operation', 'pending', {'v': 1, 'before': before});
    await LocalWrites.recover(store);
    expect(await inner.get('session', 'item'), {'value': 'before'});
    await inner.put('session', 'item', {'value': 'committed'});
    await inner.put('operation', 'pending', {
      'v': 1,
      'before': before,
      'committed': true,
    });
    await LocalWrites.recover(store);
    expect(await inner.get('session', 'item'), {'value': 'committed'});
    expect(await inner.list('operation'), isEmpty);
  });
  testWidgets('list read failure shows a working Retry', (tester) async {
    store.failList = true;
    await tester.pumpWidget(host(ParkingScreen(store: store)));
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
      'fields': {'place': 'Keep text', 'recordId': 'stable'},
    };
    await inner.put('draft', 'session:new', original);
    store.failDraft = true;
    await tester.pumpWidget(host(ParkingEditorSheet(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(await inner.get('draft', 'session:new'), original);
    store.failDraft = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    final text = tester
        .widget<TextField>(find.byKey(const ValueKey('parking-field-place')))
        .controller!
        .text;
    expect(text, 'Keep text');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps raw input; retry writes only one record', (
    tester,
  ) async {
    store.failPut = 'session';
    await tester.pumpWidget(host(ParkingEditorSheet(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-place')),
      'Example',
    );

    final save = find.byKey(const ValueKey('parking-save'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await inner.list('session'), isEmpty);
    expect(find.byKey(const ValueKey('parking-save')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('parking-field-place')))
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
    expect(await inner.list('session'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  test('malformed coordinate/time are errors, precision roundtrips', () {
    expect(ParkingParse.coordinate('garbage', -90, 90)!.isNaN, isTrue);
    expect(ParkingParse.coordinate('Infinity', -90, 90)!.isNaN, isTrue);
    expect(ParkingParse.expiry('2026/02/30', '12:00'), ParkingParse.invalid);
    expect(ParkingParse.expiry('2026/02/28', '24:60'), ParkingParse.invalid);
    const coord = 35.123456789;
    expect(double.parse(ParkingParse.coordinateText(coord)), coord);
    final stamp = DateTime.utc(2026, 10, 13, 12, 10, 45);
    final (date, time) = ParkingParse.expiryText(stamp);
    final local = stamp.toLocal();
    expect(date, '${local.year}/${local.month}/${local.day}');
    expect(time, '${local.hour}:${local.minute.toString().padLeft(2, '0')}');
  });
  test(
    'editing vehicle conflicts; closing old and starting new rolls back on failure',
    () async {
      await inner.put('session', 'old', {
        'vehicle': 'Car',
        'place': 'Old',
        'startedAt': '2026-10-13T12:00:00',
        'future': true,
      });
      await inner.put('session', 'new', {
        'vehicle': 'Bike',
        'place': 'New',
        'startedAt': '2026-10-13T13:00:00',
      });
      await expectLater(
        ParkingRepository.save(
          store,
          'new',
          {'vehicle': ' Car '},
          ['vehicle'],
          existing: true,
        ),
        throwsA(isA<ParkingConflict>()),
      );
      store.failPut = 'session';
      await expectLater(
        ParkingRepository.save(
          store,
          'new',
          {'vehicle': 'Car'},
          ['vehicle'],
          existing: true,
          closeEarlier: true,
        ),
        throwsStateError,
      );
      expect((await inner.get('session', 'old'))!['foundAt'], isNull);
      expect((await inner.get('session', 'new'))!['vehicle'], 'Bike');
      await ParkingRepository.save(
        store,
        'new',
        {'vehicle': 'Car'},
        ['vehicle'],
        existing: true,
        closeEarlier: true,
      );
      expect((await inner.get('session', 'old'))!['future'], isTrue);
      expect((await inner.get('session', 'old'))!['foundAt'], isNotNull);
    },
  );
  test(
    'Undo of deleted active parking cannot create a second active session',
    () async {
      await inner.put('session', 'old', {'vehicle': 'Car', 'place': 'Old'});
      final undo = await ParkingRepository.delete(store, 'old');
      await inner.put('session', 'new', {'vehicle': 'Car', 'place': 'New'});
      await expectLater(undo(), throwsStateError);
      expect(await inner.get('session', 'old'), isNull);
    },
  );
  test(
    'repeated query is moved, not duplicated; stored cap is enforced',
    () async {
      for (var n = 0; n < 12; n++) {
        await ParkingWrites.rememberQuery(store, const [], 'query$n');
      }
      await ParkingWrites.rememberQuery(store, const [], 'QUERY11');
      final queries = await inner.list('search');
      expect(queries, hasLength(8));
      expect(
        queries.where(
          (r) => r.body['query'].toString().toLowerCase() == 'query11',
        ),
        hasLength(1),
      );
    },
  );
  test('cleared coordinates do not survive in a remembered template', () async {
    await ParkingWrites.rememberPlace(store, const [], {
      'place': 'Example',
      'lat': 35.123,
      'lng': 51.123,
    });
    await ParkingWrites.rememberPlace(store, const [], {'place': 'Example'});
    final template = (await inner.list('place')).single;
    expect(template.body.containsKey('lat'), isFalse);
    expect(template.body.containsKey('lng'), isFalse);
    expect(template.body['useCount'], 2);
  });
}
