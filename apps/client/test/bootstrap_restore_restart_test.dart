import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/bootstrap_host.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/restart_scope.dart';
import 'package:nex_client/screens/ai_provider_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';
import 'support/nex_harness.dart';

void main() {
  testWidgets(
    'restore restart removes old routes, displays new notes, and saves new credentials',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nex/os_capture'),
        (call) async => call.method == 'isShareWindow' ? false : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('nex/os_capture'),
          null,
        ),
      );
      final before = await NexTestHarness.create(name: 'nex-before-restore-');
      await before.preferences.setAiProvider(
        const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'before-secret',
        ),
      );
      await before.services.captureText('Note before restore');
      final after = await NexTestHarness.create(name: 'nex-after-restore-');
      await after.preferences.setAiProvider(
        const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'restored-secret',
        ),
      );
      await after.services.captureText('Restored note visible immediately');
      final next = Completer<NexBootstrapSession>();
      var loads = 0;
      await tester.pumpWidget(
        NexBootstrapHost(
          load: () async {
            if (loads++ == 0) {
              return NexBootstrapSession(before.preferences, before.services);
            }
            return next.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(NexApp), findsOneWidget);
      expect(
        find.textContaining('Note before restore', findRichText: true),
        findsWidgets,
      );
      final oldApp = tester.state(find.byType(NexApp));
      final oldContext = tester.element(find.byType(TimelineScreen));
      unawaited(
        Navigator.of(oldContext).push(
          NexPageRoute<void>(
            builder: (_) => AiProviderScreen(preferences: before.preferences),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final providerContext = tester.element(find.byType(AiProviderScreen));
      NexRestartScope.of(providerContext).restart();
      await tester.pump();
      await tester.pump();
      expect(oldApp.mounted, isFalse);
      expect(find.byType(AiProviderScreen), findsNothing);
      next.complete(NexBootstrapSession(after.preferences, after.services));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Restored note visible immediately',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Note before restore', findRichText: true),
        findsNothing,
      );
      final newContext = tester.element(find.byType(TimelineScreen));
      unawaited(
        Navigator.of(newContext).push(
          NexPageRoute<void>(
            builder: (_) => AiProviderScreen(
              preferences: after.preferences,
              client: MockClient(
                (_) async => http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'message': {'content': 'ok'},
                      },
                    ],
                  }),
                  200,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, 'API key');
      await tester.scrollUntilVisible(
        input,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(input).controller!.text,
        'restored-secret',
      );
      await tester.enterText(input, 'new-tested-secret');
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      final reloaded = await NexPreferences.load();
      expect(reloaded.aiProvider.apiKey, 'new-tested-secret');
      reloaded.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      // The host owns and closes both service graphs and preferences.
      before.root.deleteSync(recursive: true);
      after.root.deleteSync(recursive: true);
    },
  );
}
