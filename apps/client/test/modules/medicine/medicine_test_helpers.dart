part of 'medicine_widget_test.dart';

// ------------------------------------------------------------------ helpers

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

/// Adds a medicine through the editor sheet, as a person would.
Future<void> _add(
  WidgetTester tester, {
  required String name,
  String strength = '',
  String quantity = '',
  String doseUnits = '',
  String refill = '',
  String packageUnit = '',
  String expiry = '',
  String instructions = '',
  bool expectSave = true,
}) async {
  await tester.tap(find.byKey(const ValueKey('medicine-fab')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('medicine-field-name')),
    name,
  );
  if (strength.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-strength')),
      strength,
    );
  }
  if (packageUnit.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-package')),
      packageUnit,
    );
  }
  if (instructions.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-instructions')),
      instructions,
    );
  }
  if (quantity.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-quantity')),
      quantity,
    );
  }
  if (doseUnits.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-dose-units')),
      doseUnits,
    );
  }
  if (refill.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-refill')),
      refill,
    );
  }
  if (expiry.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-expiry')),
      expiry,
    );
  }
  await _tapSave(tester);
  if (expectSave) await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  // `ensureVisible` can leave the button half under the screen edge, so
  // the sheet's list is dragged until the button is actually tappable.
  final sheetList = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  final save = find.byKey(const ValueKey('medicine-save'));
  for (var attempt = 0; attempt < 10; attempt++) {
    if (save.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(sheetList, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(save);
  await tester.pumpAndSettle();
}
