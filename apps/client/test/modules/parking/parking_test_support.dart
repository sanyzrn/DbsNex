import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/more_details.dart';

/// The helpers both parking screen tests share.
Future<void> pumpParkingHome(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// Writes a parking through the editor, as a person would.
Future<void> createParking(
  WidgetTester tester, {
  String place = 'North lot',
  String vehicle = '',
  String floor = '',
  String expiry = '',
  bool expectSave = true,
}) async {
  await tester.tap(find.byKey(const ValueKey('parking-park-details')));
  await tester.pumpAndSettle();
  await openMoreDetails(tester, 'parking-more-toggle');
  if (vehicle.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-vehicle')),
      vehicle,
    );
  }
  await tester.enterText(
    find.byKey(const ValueKey('parking-field-place')),
    place,
  );
  if (floor.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-floor')),
      floor,
    );
  }
  if (expiry.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-expiry-date')),
      expiry.split(' ').first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-expiry-time')),
      expiry.split(' ').last,
    );
  }
  await tapSave(tester);
  if (expectSave) {
    await tester.pumpAndSettle();
  }
}

Future<void> tapSave(WidgetTester tester) async {
  // `ensureVisible` can leave the button half under the screen edge, so
  // the sheet's list is dragged until the button is actually tappable.
  final sheetList = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  final save = find.byKey(const ValueKey('parking-save'));
  for (var attempt = 0; attempt < 10; attempt++) {
    if (save.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(sheetList, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(save);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, Key key) =>
    (tester.widget<TextField>(find.byKey(key)).controller!).text;
