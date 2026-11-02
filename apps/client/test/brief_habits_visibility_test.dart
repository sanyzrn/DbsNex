import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/brief_screen.dart';
import 'support/nex_harness.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    testWidgets(
      '$locale: habits consent is offered only while the module is active',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        tester.view.physicalSize = const Size(600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await h.preferences.setBriefUseHabits(true);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BriefScreen(preferences: h.preferences),
          ),
        );
        await tester.pumpAndSettle();
        final option = find.byKey(const ValueKey('brief-use-habits'));
        expect(option, findsNothing);
        await h.preferences.setModuleOn('habits', true);
        await tester.pumpAndSettle();
        expect(option, findsOneWidget);
        await h.preferences.setModuleOn('habits', false);
        await tester.pumpAndSettle();
        expect(option, findsNothing);
        expect(h.preferences.briefHabitsAllowed, isFalse);
        expect(h.preferences.briefUseHabits, isTrue);
      },
    );
  }
}
