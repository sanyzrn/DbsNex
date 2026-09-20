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
/// Both are the same move: the chrome that used to be drawn as objects — a
/// gear in a corner a thumb cannot reach, a grey card with three buttons on
/// it — became four fixed places and a paragraph. What is pinned here is the
/// part of that which is a promise rather than a taste: where the four places
/// are, that they do not move when the language does, and that the recap has
/// nothing filled behind it.
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

      expect(recurring, lessThan(assistant), reason: 'recurring is first, $locale');
      expect(assistant, lessThan(capture), reason: 'assistant is second, $locale');
      expect(capture, lessThan(library), reason: 'capture is middle, $locale');
      expect(library, lessThan(settings), reason: 'settings is last, $locale');
    }
  });

  testWidgets('the capsules and capture sit on one line', (tester) async {
    await open(tester);

    final capture = tester.getRect(find.byType(FloatingActionButton));
    expect(capture.height, closeTo(nexCaptureFabSize, 1));

    final capsules = find.byType(NexGlassCapsule);
    expect(capsules, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      final rect = tester.getRect(capsules.at(i));
      expect(
        rect.height,
        closeTo(NexGlassCapsule.height, 1),
        reason: "Apple's toolbar pill is 48 and so is this one",
      );
      expect(
        rect.center.dy,
        closeTo(capture.center.dy, 1),
        reason: 'a capsule that is 8 off centre reads as a mistake',
      );
    }
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
          matching: find.byType(NexCapsuleAction),
        ),
      );
      // The kit draws a 36pt symbol. A 36pt *button* is under every
      // platform's floor, so the slot is 48 and the glyph inside it is 22 —
      // which lands the centres exactly where the kit puts them anyway.
      expect(slot.width, greaterThanOrEqualTo(nexMinTapTarget));
      expect(slot.height, greaterThanOrEqualTo(nexMinTapTarget));
    }
  });

  testWidgets('the assistant keeps its place with nothing to answer it', (
    tester,
  ) async {
    // Nothing is configured in this file's setUp, which is the state most
    // installs are in. The button used to vanish there, leaving the left
    // capsule half the width of the right one.
    await open(tester);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    final capsules = find.byType(NexGlassCapsule);
    expect(
      tester.getRect(capsules.at(0)).width,
      closeTo(tester.getRect(capsules.at(1)).width, 1),
      reason: 'two pairs, so two capsules of the same width',
    );

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
  });
}
