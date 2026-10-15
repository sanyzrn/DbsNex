import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  for (final persian in [false, true]) {
    testWidgets(
      'receipt toggle never relabels or reinterprets toman input, fa:$persian',
      (tester) async {
        final h = await NexTestHarness.create(name: 'gold_input_unit_');
        addTearDown(h.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(persian ? 'fa' : 'en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GoldScreen(store: NexModuleStore(h.services, 'gold')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('gold-rate')), '100');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('gold-unit-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.text(persian ? 'قیمت هر گرم (تومان)' : 'Price per gram (toman)'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('gold-rate')))
              .controller!
              .text,
          '100',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
