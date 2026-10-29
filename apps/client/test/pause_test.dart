import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/screens/modules_screen.dart';
import 'package:nex_client/screens/pause/pause_patterns.dart';
import 'package:nex_client/screens/pause/pause_screen.dart';
import 'package:nex_client/screens/pause/pause_session.dart';
import 'package:nex_client/screens/pause/pause_sound.dart';
import 'package:nex_client/screens/pause/pause_synth.dart';

import 'support/nex_harness.dart';

/// Pause, the breathing break (2.3.7).
void main() {
  group('the breathing', () {
    test('each mode is the pattern its name stands for', () {
      expect(PauseMode.calm.rhythm, '5.5 · 5.5');
      expect(PauseMode.focus.rhythm, '4 · 4 · 4 · 4');
      expect(PauseMode.relax.rhythm, '4 · 7 · 8');
      expect(PauseMode.calm.sessionDuration, const Duration(seconds: 110));
      expect(PauseMode.focus.sessionDuration, const Duration(seconds: 96));
      expect(PauseMode.relax.sessionDuration, const Duration(seconds: 76));
      // Every round ends empty, so its sound loops without a seam.
      for (final mode in PauseMode.values) {
        expect(mode.phases.first.step, PauseStep.inhale);
        expect(
          mode.phases.last.step,
          anyOf(PauseStep.exhale, PauseStep.holdEmpty),
        );
      }
    });

    test('the moment follows the clock, and ends after the last round', () {
      final half = pauseMomentAt(
        PauseMode.calm,
        const Duration(milliseconds: 2750),
      );
      expect(half.phase.step, PauseStep.inhale);
      expect(half.fullness, closeTo(0.5, 0.001));

      final held = pauseMomentAt(PauseMode.relax, const Duration(seconds: 6));
      expect(held.phase.step, PauseStep.holdFull);
      expect(held.fullness, 1);
      expect(held.secondsLeft, 5);

      final second = pauseMomentAt(
        PauseMode.focus,
        const Duration(seconds: 17),
      );
      expect(second.round, 1);
      expect(second.phase.step, PauseStep.inhale);

      expect(
        pauseMomentAt(PauseMode.calm, const Duration(seconds: 110)).done,
        isTrue,
      );
      expect(
        pauseMomentAt(PauseMode.calm, const Duration(seconds: 109)).done,
        isFalse,
      );
    });

    test('the taps come closer as an inhale fills and part as it empties', () {
      List<double> gaps(List<double> marks) => [
        for (var i = 1; i < marks.length; i++) marks[i] - marks[i - 1],
      ];
      final inhale = gaps(pauseTapsFor(PauseStep.inhale));
      final exhale = gaps(pauseTapsFor(PauseStep.exhale));
      for (var i = 1; i < inhale.length; i++) {
        expect(inhale[i], lessThan(inhale[i - 1]));
      }
      for (var i = 1; i < exhale.length; i++) {
        expect(exhale[i], greaterThan(exhale[i - 1]));
      }
    });
  });

  group('the sound', () {
    test('a round is one breath long, never clips and loops cleanly', () {
      for (final mode in PauseMode.values) {
        final round = pauseSynthRound(mode);
        expect(round.length, mode.roundMillis * pauseSampleRate ~/ 1000);
        var peak = 0.0;
        for (final s in round) {
          if (s.abs() > peak) peak = s.abs();
        }
        expect(peak, lessThanOrEqualTo(0.71));
        expect(peak, greaterThan(0.3));
        // Both ends at silence: where the loop joins there is no click.
        expect(round.first.abs(), lessThan(0.01));
        expect(round.last.abs(), lessThan(0.01));
      }
    });

    test('is written as a plain mono 16-bit WAV', () {
      final wav = pauseWav(Float32List.fromList([0, 0.5, -0.5, 1]));
      final data = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), pauseSampleRate);
      expect(data.getUint16(34, Endian.little), 16);
      expect(data.getUint32(40, Endian.little), 8);
      expect(data.getInt16(44 + 6, Endian.little), 32767);
    });

    test('the countdown and the bowl are made too', () {
      expect(pauseSynthCountdown().length, pauseSampleRate * 3);
      expect(pauseSynthBowl().length, pauseSampleRate * 7);
    });
  });

  group('the screens', () {
    late NexTestHarness harness;
    final taps = <String>[];

    setUp(() async {
      harness = await NexTestHarness.create();
      pauseSoundFactory = SilentPauseSound.new;
      taps.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              taps.add('${call.arguments}');
            }
            return null;
          });
    });

    tearDown(() async {
      pauseSoundFactory = NexPauseSound.new;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await harness.dispose();
    });

    // A session's clock never stops, so a session is pumped, not settled.
    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      String lang = 'en',
    }) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );
      if (home is PauseSession) {
        await tester.pump();
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
    }

    testWidgets('Pause is a module people can add, not Soon', (tester) async {
      final pause = nexModules.firstWhere((m) => m.id == 'pause');
      expect(pause.available, isTrue);
      await pump(
        tester,
        ModulesScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('module-pause')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('module-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('module-pause-add')));
      await tester.pumpAndSettle();
      expect(harness.preferences.isModuleOn('pause'), isTrue);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    });

    testWidgets('the page picks a mode and remembers it', (tester) async {
      await pump(tester, PauseScreen(preferences: harness.preferences));
      expect(find.text('Breathing break'), findsOneWidget);
      expect(find.text('For calm'), findsOneWidget);
      expect(find.text('5.5 · 5.5 s · 10 breaths · 1:50'), findsOneWidget);

      // Swiped to the next card, as a person would.
      await tester.drag(
        find.byKey(const ValueKey('pause-modes')),
        const Offset(-240, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('For focus'), findsOneWidget);
      expect(harness.preferences.pauseMode, 'focus');

      await tester.tap(find.byKey(const ValueKey('pause-sound-setting')));
      await tester.pumpAndSettle();
      expect(harness.preferences.pauseSound, isFalse);
    });

    testWidgets('a session counts in, breathes, pauses and ends', (
      tester,
    ) async {
      await pump(
        tester,
        PauseSession(mode: PauseMode.calm, preferences: harness.preferences),
      );
      expect(find.byKey(const ValueKey('pause-count')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Inhale'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(taps, isNotEmpty, reason: 'the countdown and the breath tap');

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Exhale'), findsOneWidget);

      // A tap on the card holds the session where it is.
      await tester.tap(find.byKey(const ValueKey('pause-card')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tap to carry on'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Tap to carry on'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-card')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Exhale'), findsOneWidget);

      for (var i = 0; i < 110; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Well done'), findsWidgets);
      expect(find.text('10 breaths · 1:50'), findsOneWidget);
      expect(find.byKey(const ValueKey('pause-again')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving the app pauses the session', (tester) async {
      await pump(
        tester,
        PauseSession(mode: PauseMode.calm, preferences: harness.preferences),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Inhale'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tap to carry on'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('in Persian the words and digits are Persian', (tester) async {
      await pump(
        tester,
        PauseSession(mode: PauseMode.relax, preferences: harness.preferences),
        lang: 'fa',
      );
      expect(find.text('۳'), findsOneWidget);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('دم'), findsOneWidget);
      expect(find.text('۴'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with vibration off nothing taps', (tester) async {
      await harness.preferences.setPauseHaptics(false);
      await pump(
        tester,
        PauseSession(mode: PauseMode.focus, preferences: harness.preferences),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(taps, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
