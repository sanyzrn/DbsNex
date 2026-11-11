import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_ui/nex_ui.dart';

/// One motion language — the Motion section of
/// `docs/16-design-language.md`, and [NexMotion].
void main() {
  Iterable<(String, String)> sources() sync* {
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is File && file.path.endsWith('.dart')) {
        yield (file.path.replaceAll(r'\', '/'), file.readAsStringSync());
      }
    }
  }

  test('every dialog opens through nexShowDialog', () {
    final raw = RegExp(r'(?<![A-Za-z_])showDialog\s*[<(]');
    final offenders = [
      for (final (path, source) in sources())
        if (path != 'lib/widgets/nex_dialog.dart' && raw.hasMatch(source)) path,
    ];
    expect(offenders, isEmpty, reason: 'Use nexShowDialog.');
  });

  test('every sheet rises the same way', () {
    // The reduce-motion gate (F-01) may wrap the shared rise — the canonical
    // form only, so anything else naming another style still flags.
    final gate = RegExp(
      r'MediaQuery\.disableAnimationsOf\(context\)\s*\?\s*'
      r'AnimationStyle\.noAnimation\s*:\s*',
    );
    final style = RegExp(r'sheetAnimationStyle:\s*([\w.]+)');
    final offenders = [
      for (final (path, source) in sources())
        for (final match in style.allMatches(source.replaceAll(gate, '')))
          if (!const {
            'nexSheetRise',
            'NexMotion.sheet',
          }.contains(match.group(1)))
            '$path: ${match.group(0)}',
    ];
    expect(offenders, isEmpty);
  });

  test('transitions take their timing from NexMotion', () {
    // The signature animations — the splash, the onboarding scenes, the
    // living wordmark, the top capsule, Cycle's breathing light, the
    // recording pulse, the assistant's thinking dots, the camera's flash —
    // are choreographed pieces with
    // their own timing, and say so where they are defined. Everything else
    // that arrives, leaves or changes uses the tokens.
    const signature = {
      'lib/screens/camera_sheet.dart',
      'lib/screens/onboarding/onboarding_scenes.dart',
      'lib/screens/onboarding/onboarding_art.dart',
      // The writing portrait's per-section entrance.
      'lib/screens/profile/profile_portrait_motion.dart',
      'lib/screens/cycle/cycle_space.dart',
      'lib/widgets/nex_splash.dart',
      'lib/widgets/nex_brand.dart',
      'lib/widgets/nex_banner.dart',
      'lib/widgets/recording_sheet.dart',
      'lib/widgets/ai_chat/chat_thinking.dart',
    };
    final literal = RegExp(
      r'(?:duration|Duration|reverseDuration|transitionDuration)'
      r'(?:\s*:|\s*=>)\s*const\s+Duration\(milliseconds',
    );
    final offenders = [
      for (final (path, source) in sources())
        if (!signature.contains(path) && literal.hasMatch(source)) path,
    ];
    expect(offenders, isEmpty, reason: 'Use NexMotion.enter, exit, …');
  });

  testWidgets('a dialog rises and leaves like a sheet', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox();
          },
        ),
      ),
    );
    late ModalRoute<Object?> route;
    final closed = nexShowDialog<String>(
      context: host,
      builder: (context) {
        route = ModalRoute.of(context)!;
        return const AlertDialog(title: Text('Question'));
      },
    );
    await tester.pump();
    expect(route.transitionDuration, NexMotion.enter);
    expect(route.reverseTransitionDuration, NexMotion.exit);
    // Still arriving half way through, settled at the end.
    await tester.pump(NexMotion.enter ~/ 2);
    expect(route.animation!.value, inExclusiveRange(0, 1));
    await tester.pump(NexMotion.enter);
    expect(route.animation!.value, 1);
    Navigator.of(host).pop('answer');
    await tester.pumpAndSettle();
    expect(await closed, 'answer');
  });

  testWidgets('a sheet appears in place under reduce motion (F-01)', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox();
          },
        ),
      ),
    );
    late ModalRoute<Object?> route;
    final opened = nexShowSheet<void>(
      context: host,
      builder: (context) {
        route = ModalRoute.of(context)!;
        return const SizedBox(height: 100);
      },
    );
    await tester.pump();
    // Not rising: the most-executed animation in the app honours the
    // system's "remove animations" — it was still at 0.5 at 150ms before.
    expect(route.animation!.value, 1);
    expect(route.transitionDuration, Duration.zero);
    await tester.pumpAndSettle();
    Navigator.of(host).pop();
    await opened;
  });

  testWidgets('a page appears in place under reduce motion (F-02)', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final route = NexPageRoute<void>(builder: (context) => const Text('next'));
    final pushed = Navigator.of(host).push<void>(route);
    await tester.pump();
    expect(route.transitionDuration, Duration.zero);
    expect(route.animation!.value, 1);
    await tester.pumpAndSettle();
    Navigator.of(host).pop();
    await pushed;
  });

  testWidgets('a page still slides at the token durations normally', (
    tester,
  ) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final route = NexPageRoute<void>(builder: (context) => const Text('next'));
    final pushed = Navigator.of(host).push<void>(route);
    await tester.pump();
    expect(route.transitionDuration, NexMotion.enter);
    expect(route.reverseTransitionDuration, NexMotion.exit);
    await tester.pumpAndSettle();
    Navigator.of(host).pop();
    await pushed;
  });
}
