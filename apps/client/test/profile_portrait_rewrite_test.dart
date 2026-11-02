import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/profile/profile_portrait.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'support/nex_harness.dart';

NexPortrait portrait(String prefix) => NexPortrait(
  headline: '$prefix headline',
  portrait: '$prefix description.',
  traits: [
    NexPortraitTrait(name: '$prefix organised', score: 80, line: 'Plans.'),
    NexPortraitTrait(name: '$prefix curious', score: 60, line: 'Questions.'),
    NexPortraitTrait(name: '$prefix steady', score: 70, line: 'Practice.'),
  ],
  strengths: ['$prefix strength'],
  invitation: '$prefix suggestion',
  writtenAt: DateTime(2026, 11, 2),
  basedOn: 30,
);

void main() {
  for (final success in [true, false]) {
    testWidgets(
      'rewrite keeps the existing portrait; success=$success settles in place',
      (tester) async {
        final previousHttp = HttpOverrides.current;
        HttpOverrides.global = null;
        final received = Completer<void>();
        final release = Completer<void>();
        late HttpServer server;
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            await request.drain<void>();
            if (!received.isCompleted) received.complete();
            await release.future;
            request.response.headers.contentType = ContentType.json;
            request.response.statusCode = success ? 200 : 400;
            request.response.write(
              jsonEncode(
                success
                    ? {
                        'choices': [
                          {
                            'message': {
                              'content': jsonEncode(portrait('Fresh').toJson()),
                            },
                            'finish_reason': 'stop',
                          },
                        ],
                      }
                    : {
                        'error': {'message': 'Fixture failure'},
                      },
              ),
            );
            await request.response.close();
          });
        });
        final h = await NexTestHarness.create();
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          HttpOverrides.global = previousHttp;
          await h.dispose();
          await server.close(force: true);
        });
        final now = DateTime.now();
        for (var i = 0; i < 30; i++) {
          final note = (await h.db.captureText('A useful note number $i'))!;
          h.db.backdate(note.id, now.subtract(Duration(days: i % 10)));
        }
        await h.preferences.setProfilePortrait(portrait('Kept'));
        await h.preferences.setAiEnabled(true);
        await h.preferences.setAiProvider(
          AiProviderConfig(
            provider: AiProvider.custom,
            apiKey: 'fixture',
            model: 'fixture',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
          ),
        );
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: nexLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProfilePortrait(
                  services: h.services,
                  preferences: h.preferences,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rewrite = find.byKey(const ValueKey('profile-portrait-rewrite'));
        await tester.ensureVisible(rewrite);
        await tester.pumpAndSettle();
        await tester.tap(rewrite);
        await tester.pump();
        for (var i = 0; i < 100 && !received.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(received.isCompleted, isTrue);
        // The old implementation removed every written section at this point.
        expect(find.text('Kept description.'), findsOneWidget);
        expect(tester.widget<TextButton>(rewrite).onPressed, isNull);
        release.complete();
        for (var i = 0; i < 80; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 30));
          if (tester.widget<TextButton>(rewrite).onPressed != null) break;
        }
        await tester.pumpAndSettle();
        final prefix = success ? 'Fresh' : 'Kept';
        expect(find.text('$prefix description.'), findsOneWidget);
        final fades = tester.widgetList<FadeTransition>(
          find.ancestor(
            of: find.text('$prefix organised'),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fades, isNotEmpty);
        expect(
          fades.every((fade) => fade.opacity.value == 1),
          isTrue,
          reason:
              'The new traits must paint without leaving and reopening Profile.',
        );
        if (success) expect(find.text('Kept description.'), findsNothing);
        expect(h.preferences.profilePortrait!.headline, '$prefix headline');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
