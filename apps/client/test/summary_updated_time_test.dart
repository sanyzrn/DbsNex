import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'support/nex_harness.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/summary_updated_time.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    test(
      '$locale: success ages use minute boundaries and clamp future times',
      () async {
        final l = await AppLocalizations.delegate.load(Locale(locale));
        final now = DateTime(2026, 11, 2, 12);
        String age(Duration d) => nexSummaryAge(l, now.subtract(d), now);
        expect(age(const Duration(seconds: -90)), l.timeNow);
        expect(age(const Duration(seconds: 59)), l.timeNow);
        expect(age(const Duration(minutes: 1)), l.briefUpdatedMinutes(1));
        expect(age(const Duration(minutes: 20)), l.briefUpdatedMinutes(20));
        expect(age(const Duration(hours: 1)), l.briefUpdatedHours(1));
        expect(
          age(const Duration(hours: 2, minutes: 5)),
          l.briefUpdatedHoursMinutes(2, 5),
        );
        expect(age(const Duration(hours: 25)), l.briefUpdatedDaysHours(1, 1));
      },
    );
    testWidgets(
      '$locale: cached success age sits opposite the home summary title',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await h.preferences.setLocale(locale);
        await h.services.captureText('A useful draft');
        await h.preferences.setAiEnabled(true);
        await h.preferences.setAiProvider(
          const AiProviderConfig(
            provider: AiProvider.openai,
            apiKey: 'fixture',
          ),
        );
        await h.preferences.setAiDaySummary(
          text: 'A stable cached brief',
          dateKey: '2026-11-02',
          at: DateTime.now().subtract(const Duration(minutes: 20)),
        );
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        final age = find.byKey(const ValueKey('brief-updated-age'));
        final l = AppLocalizations.of(tester.element(age));
        expect(find.text(l.briefUpdatedMinutes(20)), findsOneWidget);
        final title = find.text(l.aiDaySummaryTitle);
        expect(
          locale == 'fa'
              ? tester.getCenter(age).dx < tester.getCenter(title).dx
              : tester.getCenter(age).dx > tester.getCenter(title).dx,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$locale: only the label ticks; replacing a timestamp restarts its clock',
      (tester) async {
        var now = DateTime(2026, 11, 2, 12);
        final at = now.subtract(const Duration(seconds: 50));
        Widget host(DateTime stamp) => MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SummaryUpdatedTime(at: stamp, clock: () => now),
          ),
        );
        await tester.pumpWidget(host(at));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(SummaryUpdatedTime)),
        );
        expect(find.text(l.timeNow), findsOneWidget);
        now = now.add(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 10));
        expect(find.text(l.briefUpdatedMinutes(1)), findsOneWidget);
        await tester.pumpWidget(host(now));
        expect(find.text(l.timeNow), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
