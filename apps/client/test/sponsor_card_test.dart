import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets(
    'a narrow sponsor stays readable with large text in either language',
    (tester) async {
      for (final lang in ['en', 'fa']) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(lang),
              theme: dark ? nexDarkTheme() : nexLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.9)),
                child: Scaffold(
                  body: SizedBox(
                    width: 320,
                    child: SponsorCard(
                      sponsor: NexSponsor(
                        id: 'large',
                        title: lang == 'fa'
                            ? 'عنوان حامی نکس'
                            : 'A longer sponsor title',
                        body: 'The extra supporting line',
                      ),
                      onOpen: () {},
                      onDismiss: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(IconButton)).width,
            greaterThanOrEqualTo(48),
          );
        }
      }
    },
  );

  testWidgets(
    'an unreadable cached picture falls back to the complete word card',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('nex_bad_banner_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/banner.png')
        ..writeAsStringSync('not an image');
      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SponsorCard(
              sponsor: const NexSponsor(
                id: 'broken',
                title: 'A real title',
                body: 'Readable without the image',
              ),
              image: file,
              onOpen: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          FileImage(file),
          tester.element(find.byType(SponsorCard)),
          onError: (_, _) {},
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('A real title'), findsOneWidget);
      expect(find.text('Readable without the image'), findsOneWidget);
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a decoded picture fits large text without losing its sponsor label',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('nex_valid_banner_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/banner.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEklEQVR4nGNkyC1ngAEmBiQAABU3AOjW8uYTAAAAAElFTkSuQmCC',
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: nexDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.9),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: SponsorCard(
                  sponsor: const NexSponsor(
                    id: 'picture',
                    title: 'A longer campaign title that spans two lines',
                  ),
                  image: file,
                  onOpen: () {},
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ),
      );
      for (
        var frame = 0;
        frame < 30 &&
            find.byIcon(Icons.campaign_outlined).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
      expect(find.text('SPONSORED'), findsOneWidget);
      expect(
        find.text('A longer campaign title that spans two lines'),
        findsOneWidget,
      );
      final title = tester.renderObject<RenderParagraph>(
        find.text('A longer campaign title that spans two lines'),
      );
      for (final box in title.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: title.text.toPlainText().length,
        ),
      )) {
        expect(
          box.bottom,
          lessThanOrEqualTo(title.size.height + 0.5),
          reason: 'the last visible line must not be clipped',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
