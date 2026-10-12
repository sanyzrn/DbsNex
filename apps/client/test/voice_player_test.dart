import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/voice_player.dart';
import 'package:nex_ui/nex_ui.dart';

/// The player is there with the note: its length and its shape before the
/// file is open, in either language and either theme, at a phone's width.
void main() {
  for (final locale in ['en', 'fa']) {
    for (final (name, theme) in [
      ('light', nexLightTheme()),
      ('dark', nexDarkTheme()),
    ]) {
      testWidgets('shown at once, before the file opens ($locale, $name)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: NexVoicePlayer(
                  path: null,
                  steady: null,
                  length: Duration(seconds: 83),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Its length, in the reader's digits, from the start.
        expect(find.text(locale == 'fa' ? '۱:۲۳' : '1:23'), findsOneWidget);
        // The button waits for the file: a touch does nothing yet.
        await tester.tap(find.byKey(const ValueKey('voice-player-play')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('voice-player-speed')),
          findsOneWidget,
        );
      });
    }
  }
}
