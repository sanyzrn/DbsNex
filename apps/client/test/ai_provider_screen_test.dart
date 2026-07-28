import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/screens/ai_provider_screen.dart';
import 'package:nex_ui/nex_ui.dart';

/// Saving a provider used to be a button that did nothing observable: no
/// confirmation, no error, and the button looked exactly the same afterwards.
/// There was no way to tell whether a key had been kept.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'first'),
    );
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiProviderScreen(preferences: preferences),
        ),
      );

  Finder saveButton() => find.widgetWithText(OutlinedButton, 'Save');

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(saveButton()).onPressed != null;

  testWidgets('save is unavailable until an input changes', (tester) async {
    await pump(tester);
    expect(
      saveEnabled(tester),
      isFalse,
      reason: 'nothing on screen differs from what is stored',
    );

    await tester.enterText(find.byType(TextField).first, 'second');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('saving confirms, stores, and disables itself again',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'second');
    await tester.pump();

    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.text('Provider saved.'), findsOneWidget);
    expect(preferences.aiProvider.apiKey, 'second');
    expect(
      saveEnabled(tester),
      isFalse,
      reason: 'what is on screen is now what is in effect',
    );
  });

  testWidgets('choosing no provider can be saved', (tester) async {
    // The save button used to live inside the block that only renders when a
    // provider is chosen, so picking "none" was a choice with nowhere to go.
    await pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<AiProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AiProvider.none.label).last);
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isTrue);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(preferences.aiProvider.provider, AiProvider.none);
  });
}
