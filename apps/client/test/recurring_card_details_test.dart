import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    for (final dark in [false, true]) {
      testWidgets(
        '$locale $dark: hourly details fit a narrow large-text card',
        (tester) async {
          final harness = await NexTestHarness.create();
          addTearDown(harness.dispose);
          tester.view.physicalSize = const Size(320, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final now = DateTime.now();
          final hourly = NexCommitment(
            id: 'hourly',
            title: locale == 'fa' ? 'یادآوری نوشیدن آب' : 'Drink water',
            cadence: NexCadence.hours,
            every: 2,
            dueAt: now.add(const Duration(minutes: 90)),
            createdAt: now,
            updatedAt: now,
            details: {
              'amountMinor': 12345,
              'currency': 'USD',
              'scheduledDue': now
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
            },
          );
          await harness.services.worker.saveCommitment(hourly);
          await harness.services.worker.saveCommitment(
            NexCommitment(
              id: 'paused',
              title: 'Paused',
              paused: true,
              cadence: NexCadence.days,
              every: 1,
              dueAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: nexApplyThemePreset(
                dark ? nexDarkTheme() : nexLightTheme(),
                'still',
                null,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: RecurringScreen(services: harness.services),
            ),
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(RecurringScreen)),
          );
          expect(
            find.byKey(const ValueKey('recurring-countdown-hourly')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('recurring-due-hourly')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('recurring-countdown-paused')),
            findsNothing,
          );
          expect(find.textContaining(l.commitmentTally(0, 12)), findsWidgets);
          expect(find.text(l.commitmentSnoozed), findsOneWidget);
          final card = tester.getRect(
            find.byKey(const ValueKey('recurring-card-hourly')),
          );
          for (final key in [
            'recurring-complete-hourly',
            'recurring-more-hourly',
          ]) {
            final action = tester.getRect(find.byKey(ValueKey(key)));
            expect(action.center.dy, closeTo(card.center.dy, 0.1));
            expect(action.width, greaterThanOrEqualTo(48));
            expect(action.height, greaterThanOrEqualTo(48));
          }
          final countdown = tester.getRect(
            find.byKey(const ValueKey('recurring-countdown-hourly')),
          );
          expect(
            countdown.left - card.left,
            greaterThanOrEqualTo(NexSpacing.md),
          );
          expect(
            card.right - countdown.right,
            greaterThanOrEqualTo(NexSpacing.md),
          );
          expect(find.byTooltip(l.commitmentMarkOccurrence), findsWidgets);
          expect(
            find.text(locale == 'fa' ? '۱۲۳.۴۵ USD' : '123.45 USD'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          // Unmounting must cancel the minute clock rather than leave a timer.
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
