import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_smoke_free_regression_');
  });
  tearDown(() => harness.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 70)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    Locale locale,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: SmokeFreeScreen(
          store: NexModuleStore(harness.services, 'smoke_free'),
        ),
      ),
    );
    await settle(tester);
  }

  for (final locale in [const Locale('fa'), const Locale('en')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'compact ${locale.languageCode} $brightness large-text editor and back',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pump(tester, locale, brightness);
          await tester.tap(find.byKey(const ValueKey('smoke-start')));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).last,
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await settle(tester);
        },
      );
    }
  }
}
