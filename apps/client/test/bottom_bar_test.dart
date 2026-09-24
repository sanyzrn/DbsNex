import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_client/widgets/nex_banner.dart';

import 'support/in_process_db.dart';

/// The bar along the bottom of the timeline, and the recap above it.
///
/// The four destinations keep their places and full tap targets. Capture is
/// higher than the dock so it reads as the primary action at a glance.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_bottom_bar_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    await preferences.completeOnboarding();
    await preferences.completeTour();
    await services.captureText('a note to put a timeline under the bar');
    await services.refreshTimeline();
  });

  tearDown(() async {
    // The recap's failure banner outlives the widget tree it was raised over.
    nexHideBanner();
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the bar keeps its four places when the language turns round', (
    tester,
  ) async {
    // Everything else in this app mirrors, and should: it is made of words.
    // The bar is made of four fixed places at the bottom edge of a screen,
    // and which thumb reaches which is not a fact about the language being
    // read — so this is the one row whose order must survive the switch.
    for (final locale in ['en', 'fa']) {
      await preferences.setLocale(locale);
      await open(tester);

      double x(Finder f) => tester.getCenter(f).dx;
      final recurring = x(find.byIcon(Icons.event_repeat_outlined));
      final assistant = x(find.byIcon(Icons.auto_awesome));
      // By type, not by its glyph: `Icons.add` is the sort of icon another
      // surface starts wearing, and there is exactly one capture button.
      final capture = x(find.byType(FloatingActionButton));
      final library = x(find.byIcon(Icons.inventory_2_outlined));
      final settings = x(find.byIcon(Icons.settings_outlined));

      expect(
        recurring,
        lessThan(assistant),
        reason: 'recurring is first, $locale',
      );
      expect(
        assistant,
        lessThan(capture),
        reason: 'assistant is second, $locale',
      );
      expect(capture, lessThan(library), reason: 'capture is middle, $locale');
      expect(library, lessThan(settings), reason: 'settings is last, $locale');
    }
  });

  testWidgets('capture rises above a single home dock', (tester) async {
    await open(tester);

    final capture = tester.getRect(find.byType(FloatingActionButton));
    expect(capture.height, closeTo(nexCaptureFabSize, 1));

    final dock = tester.getRect(find.byType(NexNavigationDock));
    expect(
      dock.height,
      closeTo(NexNavigationDock.height + NexNavigationDock.lift, 1),
    );
    expect(capture.center.dx, closeTo(dock.center.dx, 1));
    expect(capture.top, closeTo(dock.top, 1));
    expect(capture.center.dy, lessThan(dock.center.dy));
  });

  testWidgets('every action in the bar is a full tap target', (tester) async {
    await open(tester);
    for (final icon in [
      Icons.event_repeat_outlined,
      Icons.auto_awesome,
      Icons.inventory_2_outlined,
      Icons.settings_outlined,
    ]) {
      final slot = tester.getRect(
        find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(NexDockAction),
        ),
      );
      // The kit draws a 36pt symbol. A 36pt *button* is under every
      // platform's floor, so the slot is 48 and the glyph inside it is 22 —
      // which lands the centres exactly where the kit puts them anyway.
      expect(slot.width, greaterThanOrEqualTo(nexMinTapTarget));
      expect(slot.height, greaterThanOrEqualTo(nexMinTapTarget));
    }
  });

  testWidgets('the dock fits a narrow phone without shrinking tap targets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in [320.0, 280.0]) {
      tester.view.physicalSize = Size(width, 700);
      await open(tester);
      final dock = tester.getRect(find.byType(NexNavigationDock));
      expect(dock.left, greaterThanOrEqualTo(0));
      expect(dock.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('glass settings sheet blurs the timeline behind it', (
    tester,
  ) async {
    // An opaque modal Material used to be painted before the glass wrapper,
    // leaving the backdrop filter only its own solid colour to sample.
    await preferences.setLiquidGlass(true);
    await open(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final sheets = tester.widgetList<BottomSheet>(find.byType(BottomSheet));
    expect(sheets.last.backgroundColor, Colors.transparent);
    expect(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.byType(BackdropFilter),
      ),
      findsWidgets,
    );
  });

  testWidgets('the assistant keeps its place with nothing to answer it', (
    tester,
  ) async {
    // Nothing is configured in this file's setUp, which is the state most
    // installs are in. The button used to vanish there, leaving the left
    // capsule half the width of the right one.
    await open(tester);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    expect(find.byType(NexNavigationDock), findsOneWidget);
    expect(find.byType(NexDockAction), findsNWidgets(4));

    // And the tap says so rather than opening a chat that cannot reply.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(TimelineScreen)),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();
    expect(find.text(l10n.assistantNeedsIntelligence), findsOneWidget);
    expect(find.byType(AiChatSheet), findsNothing);
  });

  testWidgets('the brief is the first card, and the sponsor is not', (
    tester,
  ) async {
    // A provider is what puts the brief on screen at all. The key is never
    // used: `flutter_test` answers every request with a 400, and a brief that
    // failed to generate still occupies its place on the page.
    await preferences.setAiEnabled(true);
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    await open(tester);

    final brief = find.byKey(const ValueKey('timeline-recap'));
    expect(brief, findsOneWidget);

    // Above the notes, in the slot the sponsor card was built for.
    expect(
      tester.getRect(brief).top,
      lessThan(tester.getRect(find.byType(NoteCard).first).top),
      reason: 'the first card on the page is the app reading the day back',
    );

    // And it grows with its text rather than taking a note card's height:
    // the rule that pins a sponsor card is about a card selling something.
    expect(
      tester.getRect(brief).height,
      lessThan(nexCardHeightFor(tester.element(brief))),
      reason: 'two lines of prose should not occupy a full card',
    );

    unawaited(
      tester
          .state<TimelineScreenState>(find.byType(TimelineScreen))
          .revealSearch(),
    );
    await tester.pumpAndSettle();
    expect(brief, findsNothing, reason: 'search contains only search results');
  });
}
