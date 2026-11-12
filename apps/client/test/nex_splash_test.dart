import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_brand.dart';
import 'package:nex_client/widgets/nex_splash.dart';

Widget _host({
  bool reduceMotion = false,
  NexSplashIntro intro = NexSplashIntro.play,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Center(child: NexSplash(intro: intro)),
    ),
  ),
);

double _taglineOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.text('One mind. A thousand connections.'),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  group('nexSvgPath', () {
    test('absolute and relative lines, h, v and close', () {
      final path = nexSvgPath('M10,10h20v20H10Z m40,0 l10,0 0,10 -10,0z');
      expect(path.getBounds(), const Rect.fromLTRB(10, 10, 60, 30));
      expect(path.contains(const Offset(20, 20)), isTrue);
      expect(path.contains(const Offset(55, 15)), isTrue);
      expect(path.contains(const Offset(40, 20)), isFalse);
    });

    test('numbers run together the way Illustrator writes them', () {
      // "5.5.5" is 5.5 then .5, and a minus sign starts a new number.
      final path = nexSvgPath('M0,0l5.5.5-.5-.5L0,10Z');
      final bounds = path.getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, closeTo(5.5, 1e-9));
      expect(bounds.bottom, 10);
    });

    test('s reflects the previous control point', () {
      final smooth = nexSvgPath('M0,0C0,10 10,10 10,0S20,-10 20,0');
      final spelled = nexSvgPath('M0,0C0,10 10,10 10,0C10,-10 20,-10 20,0');
      expect(smooth.getBounds(), spelled.getBounds());
    });

    test('refuses commands it does not draw', () {
      expect(() => nexSvgPath('M0,0A5,5 0 0,1 10,0'), throwsFormatException);
      expect(() => nexSvgPath('10,10'), throwsFormatException);
    });
  });

  test('the brand paths parse into the shapes of the source files', () {
    // Measured from docs/brand/nex_logo.svg and docs/brand/nex_logo_type.svg.
    final mark = NexBrand.markBounds;
    expect(mark.left, closeTo(21.8, .5));
    expect(mark.top, closeTo(22.7, .5));
    expect(mark.right, closeTo(214.3, .5));
    expect(mark.bottom, closeTo(251.6, .5));
    expect(NexBrand.wordBounds.width, greaterThan(800));
    // The e's counter is a hole, not ink.
    expect(NexBrand.wordE.fillType, ui.PathFillType.evenOdd);
    expect(NexBrand.wordE.contains(const Offset(430, 75)), isFalse);
    expect(NexBrand.wordE.contains(const Offset(330, 140)), isTrue);
  });

  testWidgets('runs its course and then only breathes', (tester) async {
    await tester.pumpWidget(_host());
    expect(_taglineOpacity(tester), 0);
    await tester.pump(NexSplash.duration ~/ 2);
    expect(_taglineOpacity(tester), 0);
    await tester.pump(NexSplash.duration ~/ 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_taglineOpacity(tester), 1);
    // The idle pulse repeats until the app replaces the splash.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with animations off it is complete from the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    expect(_taglineOpacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('an everyday launch stays on the eyes while opening is quick', (
    tester,
  ) async {
    await tester.pumpWidget(_host(intro: NexSplashIntro.whenSlow));
    await tester.pump(NexSplash.patience - const Duration(milliseconds: 50));
    // Nothing has moved: the picture is still the one Android's splash left.
    expect(_taglineOpacity(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
    // The library opened; the splash goes without its timer firing after it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a slow everyday launch plays the sequence after a wait', (
    tester,
  ) async {
    await tester.pumpWidget(_host(intro: NexSplashIntro.whenSlow));
    await tester.pump(NexSplash.patience);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(NexSplash.duration);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_taglineOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('undecided, it waits; told to play, it plays at once', (
    tester,
  ) async {
    await tester.pumpWidget(_host(intro: NexSplashIntro.pending));
    await tester.pump(const Duration(seconds: 5));
    expect(_taglineOpacity(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(_host());
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with animations off a slow launch completes without motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(reduceMotion: true, intro: NexSplashIntro.whenSlow),
    );
    expect(_taglineOpacity(tester), 0);
    await tester.pump(NexSplash.patience);
    await tester.pump();
    expect(_taglineOpacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the header mark is labelled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: NexMark(size: 28))),
    );
    expect(find.bySemanticsLabel('Nex'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CustomPaint).last),
      const Size.square(28),
    );
  });
}
