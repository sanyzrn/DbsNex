import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_places_sheet.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';

import '../../support/nex_harness.dart';
import 'parking_test_support.dart';

/// All the remembered places, not only the six the home shelves show: a
/// person can find every one, star it, start a parking from it, or forget it
/// and take that back.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'parking_places_');
    store = NexModuleStore(h.services, 'parking');
    for (var n = 1; n <= 7; n++) {
      await store.put('place', 'p$n', {
        'v': 1,
        'place': 'Place $n',
        'floor': '$n',
        'spot': 'A$n',
        'useCount': n,
        'lastUsedAt': DateTime.now()
            .subtract(Duration(days: 8 - n))
            .toUtc()
            .toIso8601String(),
      });
    }
  });

  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester) async {
    await pumpParkingHome(tester, ParkingScreen(store: store));
  }

  Future<void> openAll(WidgetTester tester) async {
    final all = find.byKey(const ValueKey('parking-places-all'));
    await tester.dragUntilVisible(
      all,
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(all);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Your places'), findsOneWidget);
  }

  Finder inSheet(Key key) => find.descendant(
    of: find.byType(ParkingPlacesSheet),
    matching: find.byKey(key),
  );

  testWidgets('every place is reachable, starred and forgotten with Undo', (
    tester,
  ) async {
    await pump(tester);
    await openAll(tester);

    expect(find.text('Your places'), findsOneWidget);
    expect(inSheet(const ValueKey('parking-places-row-p7')), findsOneWidget);

    await tester.tap(inSheet(const ValueKey('parking-favourite-p7')));
    await tester.pumpAndSettle();
    expect((await store.get('place', 'p7'))!['favorite'], isTrue);

    await tester.tap(inSheet(const ValueKey('parking-place-delete-p7')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('parking-place-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(await store.get('place', 'p7'), isNull);

    await tester.tap(find.byKey(const ValueKey('parking-undo')));
    await tester.pumpAndSettle();
    expect(await store.get('place', 'p7'), isNotNull);
    expect(inSheet(const ValueKey('parking-places-row-p7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place from the sheet fills the editor, not a silent park', (
    tester,
  ) async {
    await pump(tester);
    await openAll(tester);

    await tester.tap(inSheet(const ValueKey('parking-places-row-p7')));
    await tester.pumpAndSettle();
    expect(fieldText(tester, const ValueKey('parking-field-place')), 'Place 7');
    expect(await store.list('session'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
