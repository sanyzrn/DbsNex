import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/local_ai_support.dart';
import 'package:nex_client/platform/model_store.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/screens/local_model_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  Widget host() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: LocalModelScreen(preferences: preferences),
  );

  testWidgets('an unavailable device is told why, not shown a button', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // A test host is not Android or iOS, so the screen is in its blocked
    // state — which is the point: it explains rather than offering a 2.6 GB
    // download that could not be loaded afterwards.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  group('the licence record', () {
    test('starts unaccepted and is remembered once given', () async {
      expect(preferences.acceptedModelLicense(NexModels.gemma4E2B.id), isFalse);

      await preferences.acceptModelLicense(NexModels.gemma4E2B.id);

      expect(preferences.acceptedModelLicense(NexModels.gemma4E2B.id), isTrue);
      // Per model, not one flag for all of them: accepting Gemma's terms says
      // nothing about a different model under a different licence.
      expect(preferences.acceptedModelLicense('some-other-model'), isFalse);
    });

    test(
      'survives a reload, because it is a record and not a session flag',
      () async {
        await preferences.acceptModelLicense(NexModels.gemma4E2B.id);
        final reloaded = await NexPreferences.load();
        expect(reloaded.acceptedModelLicense(NexModels.gemma4E2B.id), isTrue);
      },
    );
  });

  test('the shipped model carries the notice its licence demands', () {
    // The licence names this sentence specifically, so it is reproduced rather
    // than paraphrased, and the screen shows it verbatim.
    expect(
      NexModels.gemma4E2B.licenseNotice,
      contains('ai.google.dev/gemma/terms'),
    );
    expect(NexModels.gemma4E2B.licenseUrl, isNotEmpty);
  });

  test('the standard flavor does not offer local models', () {
    // Set only by main_ai.dart. If this ever defaults true, the standard build
    // starts offering a download nothing in it can load.
    expect(LocalAi.flavorSupportsLocalModels, isFalse);
  });
}
