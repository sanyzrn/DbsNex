import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_client/widgets/assistant_settings.dart';

/// The chat had no way to reach the settings that decide what its next answer
/// looks like — the one place where you notice one needs changing.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  testWidgets('the panel opens over the chat and lays out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AssistantSettingsPanel.show(
                  context,
                  preferences: preferences,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AssistantSettingsBody), findsOneWidget);
    expect(find.text('How it talks'), findsOneWidget);
    // Nothing behind it was replaced: the conversation this is judged against
    // is the whole reason the panel exists.
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a change made there is kept', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AssistantSettingsBody(preferences: preferences)),
      ),
    );
    await tester.pumpAndSettle();

    expect(preferences.aiNotesOnly, isTrue);
    await tester.tap(find.text('Stay in my notes'));
    await tester.pumpAndSettle();
    expect(preferences.aiNotesOnly, isFalse);
  });
}
