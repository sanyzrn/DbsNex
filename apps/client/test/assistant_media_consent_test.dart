import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'support/nex_harness.dart';

void main() {
  for (final allowed in [false, true]) {
    testWidgets('assistant sends image only with image capability $allowed', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
      );
      await h.preferences.setAiCapabilities(AiCapabilities(ocr: allowed));
      final file = File('${h.mediaDir}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
      final now = DateTime.now().toUtc();
      final note = Note(
        id: 'photo',
        type: NoteType.photo,
        content: 'my picture',
        mediaUri: file.path,
        mimeType: 'image/jpeg',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.body);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Done'},
              },
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AiChatSheet(
              services: h.services,
              preferences: h.preferences,
              history: h.preferences.chatHistory,
              client: client,
              focus: note,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AiChatSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Describe it');
      await tester.tap(find.byKey(const ValueKey('send')));
      await tester.pumpAndSettle();
      expect(requests, isNotEmpty);
      expect(requests.last.contains('image_url'), allowed);
      if (allowed) {
        await h.preferences.setAiCapabilities(const AiCapabilities(ocr: false));
        await tester.enterText(field, 'Again');
        await tester.tap(find.byKey(const ValueKey('send')));
        await tester.pumpAndSettle();
        expect(
          requests.last,
          isNot(contains('image_url')),
          reason: 'revocation applies in the same open chat',
        );
      } else {
        await h.preferences.setAiCapabilities(const AiCapabilities(ocr: true));
        await tester.enterText(field, 'Read the picture now');
        await tester.tap(find.byKey(const ValueKey('send')));
        await tester.pumpAndSettle();
        expect(
          requests.last,
          contains('image_url'),
          reason: 'enabling applies without reopening',
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('voice capability hides and reveals assistant microphone live', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
    );
    await h.preferences.setAiCapabilities(
      const AiCapabilities(transcription: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AiChatSheet(
            services: h.services,
            preferences: h.preferences,
            history: h.preferences.chatHistory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mic')), findsNothing);
    await h.preferences.setAiCapabilities(
      const AiCapabilities(transcription: true),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mic')), findsOneWidget);
    await h.preferences.setAiEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mic')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
