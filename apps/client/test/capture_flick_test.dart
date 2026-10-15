import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/capture_flick.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NexPreferences preferences;
  final launched = <CaptureShortcut>[];
  var assistant = 0;
  var holdStarts = 0;
  var taps = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
    launched.clear();
    assistant = holdStarts = taps = 0;
  });

  Future<void> show(
    WidgetTester tester, {
    bool still = false,
    String language = 'en',
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: brightness == Brightness.dark ? nexDarkTheme() : nexLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: Scaffold(
            body: Center(
              child: NexLongPressGlow(
                startDelay: CaptureFlick.assistantDelay,
                colors: nexAssistantSpectrum,
                onHoldStart: () => holdStarts++,
                onTriggered: () => assistant++,
                child: CaptureFlick(
                  preferences: preferences,
                  onShortcut: launched.add,
                  builder: (context, glyph) => FloatingActionButton(
                    onPressed: () => taps++,
                    child: glyph,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> drag(WidgetTester tester, double distance) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FloatingActionButton)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveBy(Offset(distance, 0));
    await tester.pump();
    return gesture;
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'capture fill follows each shortcut and returns after cancel ($brightness)',
      (tester) async {
        await show(tester, brightness: brightness);
        Color fill() => tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(FloatingActionButton),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        final original = fill();
        for (final direction in [-1.0, 1.0]) {
          final shortcut = direction < 0
              ? preferences.captureFlickLeft
              : preferences.captureFlickRight;
          final expected = captureShortcutColor(
            tester.element(find.byType(CaptureFlick)),
            shortcut,
          );
          final gesture = await drag(tester, direction * 22);
          await tester.pump(const Duration(milliseconds: 250));
          expect(fill(), isNot(original));
          expect(fill(), isNot(expected));
          await gesture.moveBy(Offset(direction * 30, 0));
          await tester.pump(const Duration(milliseconds: 250));
          expect(fill(), expected);
          final theme = Theme.of(
            tester.element(find.byType(FloatingActionButton)),
          );
          expect(
            nexContrastRatio(
              theme.floatingActionButtonTheme.foregroundColor!,
              fill(),
            ),
            greaterThanOrEqualTo(4.5),
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(fill(), original);
        }
        expect(launched, isEmpty);
      },
    );
  }

  testWidgets('tap and sideways swipe never flash the assistant', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(holdStarts, 0);
    expect(find.byType(NexEdgeGlow), findsNothing);
    final gesture = await drag(tester, 55);
    expect(find.byType(NexEdgeTrace), findsOneWidget);
    expect(find.byType(NexEdgeGlow), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(launched, [CaptureShortcut.camera]);
    expect(assistant, 0);
    expect(holdStarts, 0);
    expect(taps, 1);
    expect(find.byType(NexEdgeTrace), findsNothing);
  });

  testWidgets('border follows distance, changes colour on reversal, cancels', (
    tester,
  ) async {
    await show(tester);
    final gesture = await drag(tester, 25);
    var trace = tester.widget<NexEdgeTrace>(find.byType(NexEdgeTrace));
    expect(trace.progress, inExclusiveRange(0, 1));
    final context = tester.element(find.byType(CaptureFlick));
    expect(trace.color, captureShortcutColor(context, CaptureShortcut.camera));
    expect(trace.toRight, isTrue);
    await gesture.moveBy(const Offset(-55, 0));
    await tester.pump();
    trace = tester.widget<NexEdgeTrace>(find.byType(NexEdgeTrace));
    expect(trace.color, captureShortcutColor(context, CaptureShortcut.voice));
    expect(trace.toRight, isFalse);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(find.byType(NexEdgeTrace), findsNothing);
    expect(holdStarts, 0);
  });

  testWidgets('full border is painted before launch, exactly once', (
    tester,
  ) async {
    await show(tester);
    final gesture = await drag(tester, -55);
    expect(tester.widget<NexEdgeTrace>(find.byType(NexEdgeTrace)).progress, 1);
    expect(launched, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(launched, [CaptureShortcut.voice]);
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(find.byType(NexEdgeTrace), findsNothing);
  });

  testWidgets('a fast short flick completes its border before opening', (
    tester,
  ) async {
    await show(tester);
    // Four touch samples, like a finger at 100 Hz. The fling helper uses
    // fifty sub-millisecond samples, whose velocity history covers less
    // than touch slop for such a short distance.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FloatingActionButton)),
    );
    for (var step = 1; step <= 4; step++) {
      await gesture.moveBy(
        const Offset(10, 0),
        timeStamp: Duration(milliseconds: step * 10),
      );
    }
    await tester.pump();
    expect(
      tester.widget<NexEdgeTrace>(find.byType(NexEdgeTrace)).progress,
      lessThan(1),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 41));
    expect(launched, isEmpty);
    await tester.pumpAndSettle();
    expect(launched, [CaptureShortcut.camera]);
    expect(holdStarts, 0);
    expect(find.byType(NexEdgeTrace), findsNothing);
  });

  testWidgets('moving after the hold ramp starts cancels the assistant', (
    tester,
  ) async {
    await show(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FloatingActionButton)),
    );
    await tester.pump(CaptureFlick.assistantDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(NexEdgeGlow), findsOneWidget);
    await gesture.moveBy(const Offset(55, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(launched, [CaptureShortcut.camera]);
    expect(assistant, 0);
    expect(find.byType(NexEdgeGlow), findsNothing);
  });

  testWidgets('hold waits silently, then glows and triggers', (tester) async {
    await show(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FloatingActionButton)),
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(holdStarts, 0);
    expect(find.byType(NexEdgeGlow), findsNothing);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(holdStarts, 1);
    expect(assistant, 0);
    await tester.pump(const Duration(milliseconds: 430));
    expect(assistant, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
  });

  testWidgets(
    'reduced motion launches without a border and still delays hold',
    (tester) async {
      await show(tester, still: true);
      final gesture = await drag(tester, 55);
      expect(find.byType(NexEdgeTrace), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(launched, [CaptureShortcut.camera]);
      expect(assistant, 0);
      expect(holdStarts, 0);
    },
  );

  testWidgets(
    'disabled side does nothing and custom sides stay physical in RTL',
    (tester) async {
      await preferences.setCaptureFlick(
        left: true,
        shortcut: CaptureShortcut.none,
      );
      await preferences.setCaptureFlick(
        left: false,
        shortcut: CaptureShortcut.file,
      );
      await show(tester, language: 'fa', brightness: Brightness.dark);
      final left = await drag(tester, -55);
      expect(find.byType(NexEdgeTrace), findsNothing);
      await left.up();
      await tester.pumpAndSettle();
      expect(launched, isEmpty);
      final right = await drag(tester, 55);
      final context = tester.element(find.byType(CaptureFlick));
      expect(
        tester.widget<NexEdgeTrace>(find.byType(NexEdgeTrace)).color,
        captureShortcutColor(context, CaptureShortcut.file),
      );
      await right.up();
      await tester.pumpAndSettle();
      expect(launched, [CaptureShortcut.file]);
    },
  );

  testWidgets('disposal removes feedback and cancels a pending hold', (
    tester,
  ) async {
    await show(tester);
    final gesture = await drag(tester, 30);
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(find.byType(NexEdgeTrace), findsNothing);
    expect(tester.takeException(), isNull);
    await show(tester);
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(FloatingActionButton)),
    );
    await tester.pumpWidget(const SizedBox());
    await hold.up();
    await tester.pump(const Duration(seconds: 1));
    expect(holdStarts, 0);
    expect(assistant, 0);
    expect(tester.takeException(), isNull);
  });
}
