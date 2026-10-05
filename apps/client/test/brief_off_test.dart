import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/brief_screen.dart';

import 'support/nex_harness.dart';

/// Turning the smart summary off sends nothing for it (1.94.0). It used to
/// hide the card while still writing it in the background, spending tokens
/// on text nobody could see. Read off the disclosure log, which records
/// every request the app makes to a provider.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;
  late Directory logDir;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_brief_off_',
      onboarded: true,
    );
    services = harness.services;
    preferences = harness.preferences;
    await preferences.setAiEnabled(true);
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    await services.captureText('something worth summarising');
    await services.refreshTimeline();
    logDir = Directory.systemTemp.createTempSync('nex_brief_log_');
    NexDisclosureLog.configure(logDir.path);
  });

  tearDown(() async {
    await harness.dispose();
    if (logDir.existsSync()) logDir.deleteSync(recursive: true);
  });

  Future<Set<DisclosurePurpose>> purposesAfterLaunch(
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final entries = await tester.runAsync(NexDisclosureLog.read) ?? const [];
    await tester.pumpWidget(const SizedBox());
    return {for (final e in entries) e.purpose};
  }

  testWidgets('switched on, the summary is requested (the control)', (
    tester,
  ) async {
    final purposes = await purposesAfterLaunch(tester);
    expect(purposes, contains(DisclosurePurpose.dailySummary));
  });

  testWidgets('switched off, the summary and headline are never requested', (
    tester,
  ) async {
    await preferences.setShowDaySummary(false);
    await preferences.setShowGreeting(false);
    final purposes = await purposesAfterLaunch(tester);
    expect(purposes, isNot(contains(DisclosurePurpose.dailySummary)));
    expect(purposes, isNot(contains(DisclosurePurpose.greeting)));
  });

  testWidgets('the Smart summary page turns it off in one switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BriefScreen(preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(BriefScreen)));
    expect(find.text(l10n.briefStyleLabel), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brief-enabled')));
    await tester.pumpAndSettle();
    expect(preferences.showDaySummary, isFalse);
    expect(find.text(l10n.briefEnabledOff), findsOneWidget);
    // Nothing left to choose while it is off.
    expect(find.text(l10n.briefStyleLabel), findsNothing);
  });
}
