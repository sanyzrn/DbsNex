import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// What 2.7.2 and 2.8.0 drew was missing on the owner's phone (2.8.1): the
/// list card's edge in its kind's colour, and the brief's wash of the
/// accent (which 2.8.2 took back to the plain card). Both were switched off under a *minimal* appearance, and every
/// designed palette and soft appearance is one — so they were drawn for
/// almost nobody, and every test ran on the one look that is not.
void main() {
  for (final (preset, mode) in [
    ('classic', 'light'),
    ('paper', 'soft_dark'),
    ('ocean', 'night'),
  ]) {
    group('$preset, $mode', () {
      late NexTestHarness harness;

      setUp(() async {
        harness = await NexTestHarness.create(
          name: 'nex_minimal_',
          onboarded: true,
          preferences: {
            'appearance.theme_preset': preset,
            'appearance.theme': mode,
          },
        );
        await harness.preferences.setAiEnabled(true);
        await harness.preferences.setAiProvider(
          const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
        );
        await harness.preferences.setAiDaySummary(
          text: 'A calm day ahead\nCall the plumber\nFinish the draft',
          dateKey: 'cached',
        );
        await harness.services.captureText('a note to read');
        await harness.services.refreshTimeline();
      });

      tearDown(() => harness.dispose());

      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(harness.app());
        // Pumped by hand: the brief's light keeps frames coming.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      testWidgets('a list card carries its kind\'s edge', (tester) async {
        await open(tester);
        final card = find.byType(NoteCard).first;
        final shape =
            tester
                    .widget<Material>(
                      find
                          .descendant(of: card, matching: find.byType(Material))
                          .first,
                    )
                    .shape!
                as RoundedRectangleBorder;
        expect(shape.side, isNot(BorderSide.none));
        expect(shape.side.color.a, greaterThan(0));
      });

      testWidgets('the brief is the plain card ground again (2.8.2)', (
        tester,
      ) async {
        await open(tester);
        final surface = tester.widget<NexGlassSurface>(
          find.byKey(const ValueKey('timeline-recap-surface')),
        );
        expect(surface.blur, isFalse);
        final scheme = Theme.of(
          tester.element(find.byKey(const ValueKey('timeline-recap'))),
        ).colorScheme;
        expect(surface.fallbackColor, scheme.surfaceContainerLowest);
        // The surface's own ground: the first box under it. (Deeper ones
        // are the panel's, such as the fade on folded words.)
        final ground =
            tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(
                          const ValueKey('timeline-recap-surface'),
                        ),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration;
        expect(ground.gradient, isNull);
        expect(ground.color, scheme.surfaceContainerLowest);
      });

      testWidgets('the brief\'s heading: the time under its name, the fold '
          'in one pill at its end', (tester) async {
        await harness.preferences.setDaySummaryFolded(true);
        await open(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TimelineScreen)),
        );
        final pill = find.byKey(const ValueKey('brief-fold-pill'));
        expect(pill, findsOneWidget);
        expect(
          find.descendant(
            of: pill,
            matching: find.text(l10n.aiDaySummaryMore(1)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: pill,
            matching: find.byKey(const ValueKey('brief-fold-arrow')),
          ),
          findsOneWidget,
        );
        final title = tester.getRect(find.text(l10n.aiDaySummaryTitle));
        // Opening it changes the pill alone: the name stays where it was.
        await tester.tap(find.byKey(const ValueKey('timeline-recap')));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Finish the draft'), findsOneWidget);
        expect(tester.getRect(find.text(l10n.aiDaySummaryTitle)), title);
      });
    });
  }
}
