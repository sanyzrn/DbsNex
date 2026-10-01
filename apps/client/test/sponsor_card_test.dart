import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/sponsor.dart';
import 'package:nex_client/widgets/sponsor_card.dart';
import 'package:nex_ui/nex_ui.dart';

/// The sponsor card keeps the standard card's size whatever card size is
/// chosen: its words and its banner are laid out for that one height.
void main() {
  Future<Size> cardAt(
    WidgetTester tester,
    NexCardDensity density, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexCardDensityScope(
            density: density,
            child: ListView(
              children: [
                SponsorCard(
                  sponsor: const NexSponsor(
                    id: 's1',
                    title: 'A sponsor',
                    body: 'Two lines of words',
                  ),
                  onOpen: () {},
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(SponsorCard));
  }

  testWidgets('every card size gives the sponsor card the standard height', (
    tester,
  ) async {
    final standard = await cardAt(tester, NexCardDensity.standard);
    expect(tester.takeException(), isNull, reason: 'its words fit');
    expect(await cardAt(tester, NexCardDensity.compact), standard);
    expect(await cardAt(tester, NexCardDensity.readable), standard);
    expect(tester.takeException(), isNull);
  });

  testWidgets('its words fit at a larger text size too', (tester) async {
    await cardAt(tester, NexCardDensity.standard, textScale: 1.6);
    expect(tester.takeException(), isNull);
  });
}
