import 'dart:io';

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

  testWidgets('the search model has its own screen, with no chat picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalModelScreen(preferences: preferences, search: true),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LocalModelScreen)),
    );

    expect(find.text(l10n.searchModelTitle), findsOneWidget);
    expect(find.text(l10n.searchModelExplained), findsOneWidget);
    // It is not one of the models the assistant can answer with.
    expect(find.text(l10n.localModelChoose), findsNothing);
    for (final model in NexModels.all) {
      expect(find.byKey(ValueKey('local-model-${model.id}')), findsNothing);
    }
  });

  test('the search model is used only once it is shown to run', () async {
    // Remembered by the screen after the model answered its check; until
    // then nothing points the library's vectors at it.
    expect(preferences.searchModelPath, isNull);
    await preferences.setSearchModelPath('/models/eg2.litertlm');
    expect(preferences.searchModelPath, '/models/eg2.litertlm');
    await preferences.setSearchModelPath(null);
    expect(preferences.searchModelPath, isNull);
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

  test('the shipped model names its licence: Apache 2.0 for Gemma 4', () {
    // Gemma 4 is Apache 2.0 (REL-14); the old Gemma Terms do not apply to it.
    expect(NexModels.gemma4E2B.licenseNotice, contains('Apache License'));
    expect(NexModels.gemma4E2B.licenseNotice, isNot(contains('Terms of Use')));
    expect(
      NexModels.gemma4E2B.licenseUrl,
      'https://ai.google.dev/gemma/apache_2',
    );
  });

  test('the standard flavor does not offer local models', () {
    // Set only by main_ai.dart. If this ever defaults true, the standard build
    // starts offering a download nothing in it can load.
    expect(LocalAi.flavorSupportsLocalModels, isFalse);
  });

  group('the models on offer', () {
    test('Gemma alone, and by default', () {
      // MiniCPM5 was taken off in 1.99.4: it brought the app down whenever
      // it was the model in use.
      expect(NexModels.all.map((m) => m.id), [NexModels.gemma4E2B.id]);
      expect(NexModels.standard, NexModels.gemma4E2B);
      for (final model in NexModels.all) {
        expect(NexModelStore.installable(model), isTrue, reason: model.id);
        expect(model.name, isNotEmpty);
        expect(model.licenseUrl, isNotEmpty);
      }
      expect(
        NexModels.bySha256(NexModels.gemma4E2B.sha256),
        NexModels.gemma4E2B,
      );
      expect(NexModels.byId('nope'), isNull);
    });

    test('a phone that had MiniCPM picked falls back to Gemma', () async {
      final root = Directory.systemTemp.createTempSync('nex_models_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/selected').writeAsStringSync('minicpm5-2b-int4');
      expect(NexModelStore(root: root).selected, NexModels.gemma4E2B);
    });

    test('its weights are swept, not kept', () async {
      final root = Directory.systemTemp.createTempSync('nex_models_');
      addTearDown(() => root.deleteSync(recursive: true));
      final old =
          File('${root.path}/minicpm5-2b-int4/MiniCPM5-2B_int4.litertlm')
            ..createSync(recursive: true)
            ..writeAsStringSync('weights');
      final store = NexModelStore(root: root);
      addTearDown(store.close);

      await store.sweep();

      expect(old.parent.existsSync(), isFalse);
    });
  });
}
