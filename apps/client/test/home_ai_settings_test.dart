import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/brief_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  testWidgets(
    'a wrong-language cached phrase falls back to the local greeting',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setLocale('fa');
      await h.preferences.setDisplayName('Saeed');
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
      );
      await h.preferences.setAiHeadline(
        text: 'Ready when you are',
        dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
        lang: 'fa',
      );
      await h.services.captureText('یادداشت امروز');
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready when you are'), findsNothing);
      final greeting = tester
          .widget<Text>(find.textContaining('Saeed').first)
          .data!;
      expect(greeting, matches(RegExp(r'[\u0600-\u06ff]')));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final inFlight in [false, true]) {
    testWidgets(
      'Full is applied before the hourly cooldown, pending=$inFlight',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        await h.preferences.setAiEnabled(true);
        await h.preferences.setAiProvider(
          const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test'),
        );
        await h.services.captureText('Something worth summarising');
        final reply = Completer<String?>();
        Future<Object?>? pending;
        if (inFlight) {
          pending = h.services.briefRefresh.refresh(
            fingerprint: 'standard',
            dateKey: 'today',
            request: () => reply.future,
          );
        } else {
          await h.preferences.setAiDaySummary(
            text: 'Previous standard brief',
            dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
          );
        }
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        expect(h.preferences.aiDaySummaryFailedAt, isNull);
        if (!inFlight) {
          final navigator = Navigator.of(
            tester.element(find.byType(TimelineScreen)),
          );
          unawaited(
            navigator.push(
              NexPageRoute<void>(
                builder: (_) => BriefScreen(preferences: h.preferences),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await h.preferences.setBriefLength(NexBriefLength.short);
          await h.preferences.setBriefLength(NexBriefLength.long);
          await tester.pumpAndSettle();
          expect(h.preferences.aiDaySummaryFailedAt, isNull);
          navigator.pop();
        } else {
          await h.preferences.setBriefLength(NexBriefLength.long);
        }
        await tester.pump();
        if (inFlight) {
          reply.complete('Previous standard brief');
          await pending;
        }
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // flutter_test returns HTTP 400. A failure stamp proves a request using
        // the new choice was attempted, instead of reusing the fresh old cache
        // or silently accepting the standard-length flight as its replacement.
        expect(h.preferences.aiDaySummaryFailedAt, isNotNull);
        expect(h.preferences.briefLength, NexBriefLength.long);
        expect(h.preferences.aiDaySummaryText, 'Previous standard brief');
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
