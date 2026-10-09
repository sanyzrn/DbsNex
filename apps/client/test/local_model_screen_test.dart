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

  group('more than one model', () {
    test('both are offered, the long-standing one first and by default', () {
      expect(NexModels.all.map((m) => m.id), [
        NexModels.gemma4E2B.id,
        NexModels.miniCpm5_2B.id,
      ]);
      expect(NexModels.standard, NexModels.gemma4E2B);
      for (final model in NexModels.all) {
        expect(NexModelStore.installable(model), isTrue, reason: model.id);
        expect(model.name, isNotEmpty);
        expect(model.licenseUrl, isNotEmpty);
      }
      // Each is found by its digest — what a full backup records.
      expect(
        NexModels.bySha256(NexModels.miniCpm5_2B.sha256),
        NexModels.miniCpm5_2B,
      );
      expect(NexModels.byId('nope'), isNull);
    });

    test('MiniCPM5 is the published single asset, digest and size', () {
      const model = NexModels.miniCpm5_2B;
      expect(model.parts, hasLength(1));
      expect(model.sizeBytes, 1553670064);
      expect(model.parts.single.sha256, model.sha256);
      expect(model.parts.single.url, endsWith('/MiniCPM5-2B_int4.litertlm'));
    });

    test('the choice is remembered beside the models', () async {
      final root = Directory.systemTemp.createTempSync('nex_models_');
      addTearDown(() => root.deleteSync(recursive: true));
      final store = NexModelStore(root: root);
      expect(store.selected, NexModels.standard);
      await store.select(NexModels.miniCpm5_2B);
      expect(store.selected, NexModels.miniCpm5_2B);
      // A fresh store — the next launch — reads it back.
      expect(NexModelStore(root: root).selected, NexModels.miniCpm5_2B);
      // Each model has its own place on disk.
      expect(
        store.fileFor(NexModels.gemma4E2B).parent.path,
        isNot(store.fileFor(NexModels.miniCpm5_2B).parent.path),
      );
    });
  });
}
