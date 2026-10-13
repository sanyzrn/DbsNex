import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/audio_waveform.dart';
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

  // 1.99.93 built the seekable bar as a child of itself: a stack overflow and
  // a grey box the moment the file was open.
  testWidgets('the bar can be touched once the file is open', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: AudioWaveform(
              path: 'voice.m4a',
              progress: 0.3,
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tapAt(
      tester.getTopLeft(find.byType(AudioWaveform)) + const Offset(150, 20),
    );
    expect(seeks.single, closeTo(0.75, 0.01));
  });
}
