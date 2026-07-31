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

  // The action bar is pinned, so the button is on screen whatever the list
  // above it is scrolled to.
  Finder saveButton() => find.widgetWithText(OutlinedButton, 'Save');

  /// The key field sits below six provider rows, so it has to be scrolled to
  /// — exactly as a person would. The action bar is what must *not* need
  /// scrolling, and it does not.
  Future<Finder> keyField(WidgetTester tester) async {
    final finder = find.widgetWithText(TextField, 'API key');
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    return finder;
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(saveButton()).onPressed != null;

  testWidgets('save is unavailable until an input changes', (tester) async {
    await pump(tester);
    expect(
      saveEnabled(tester),
      isFalse,
      reason: 'nothing on screen differs from what is stored',
    );

    await tester.enterText(await keyField(tester), 'second');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('saving confirms, stores, and disables itself again', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(await keyField(tester), 'second');
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
    await tester.tap(find.text(AiProvider.none.label));
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isTrue);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(preferences.aiProvider.provider, AiProvider.none);
  });

  testWidgets(
    "switching providers shows each one's own key, not the one just left",
    (tester) async {
      // Gemini was configured once before, then OpenAI was made active again —
      // Gemini's key must still be there when the screen switches back to it.
      await preferences.setAiProvider(
        const AiProviderConfig(
          provider: AiProvider.gemini,
          apiKey: 'gemini-key',
        ),
      );
      await preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'first'),
      );
      await pump(tester);

      await tester.tap(find.text(AiProvider.gemini.label));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(await keyField(tester)).controller!.text,
        'gemini-key',
        reason: 'Gemini\'s own saved key, not OpenAI\'s',
      );
      // It is not the active provider yet, so Save is how you would switch to
      // it — even though nothing about it needs editing.
      expect(saveEnabled(tester), isTrue);

      await tester.tap(find.text(AiProvider.openai.label));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(await keyField(tester)).controller!.text,
        'first',
        reason: 'back to OpenAI, whose key was never touched',
      );
      expect(
        saveEnabled(tester),
        isFalse,
        reason: 'already active, and its fields still match what is stored',
      );
    },
  );
}
