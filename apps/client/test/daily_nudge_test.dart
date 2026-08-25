import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/assistant_screen.dart';
import 'package:nex_client/screens/settings_sheet.dart';

import 'support/in_process_db.dart';

/// The once-a-day notification (its settings, and the recap it carries), and
/// the assistant's context size — the two halves of "read more of my notes,
/// and tell me about them in the morning".
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_nudge_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    Directory(p.join(tmp.path, 'media')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: p.join(tmp.path, 'media'),
      backupDir: p.join(tmp.path, 'backups'),
    );
    preferences = await NexPreferences.load();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SettingsSheet(services: services, preferences: preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  group('the daily nudge', () {
    test('the recap only counts on the day it was written for', () async {
      final today = NexPreferences.daySummaryDateKey(DateTime.now());
      await preferences.setAiDaySummary(text: 'three notes', dateKey: today);
      expect(preferences.todaysRecap, 'three notes');

      // Yesterday's summary delivered as this morning's would describe a day
      // that is over — worse than the notification admitting it has nothing.
      await preferences.setAiDaySummary(
        text: 'three notes',
        dateKey: NexPreferences.daySummaryDateKey(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      expect(preferences.todaysRecap, isNull);
    });

    test('off by default, and nine in the morning when turned on', () {
      expect(preferences.dailyNudge, isFalse);
      expect(preferences.dailyNudgeMinutes, 9 * 60);
    });

    testWidgets('the time row appears only once the nudge is on', (
      tester,
    ) async {
      await openSettings(tester);
      await scrollTo(tester, find.text('Daily nudge'));
      expect(find.text('Time'), findsNothing);

      await tester.tap(
        find.ancestor(
          of: find.text('Daily nudge'),
          matching: find.byType(SwitchListTile),
        ),
      );
      await tester.pumpAndSettle();

      expect(preferences.dailyNudge, isTrue);
      await scrollTo(tester, find.text('Time'));
      // The default, shown the way the phone writes it.
      expect(find.text('9:00 AM'), findsOneWidget);
    });
  });

  group('how much the assistant reads', () {
    test('a hundred notes and two hundred are offered', () {
      expect(NexPreferences.aiNotesContextChoices, contains(100));
      expect(NexPreferences.aiNotesContextChoices, contains(200));
      expect(NexPreferences.aiNotesContextIsSlow(50), isFalse);
      expect(NexPreferences.aiNotesContextIsSlow(100), isTrue);
    });

    testWidgets('the slow warning waits for a size that is actually slow', (
      tester,
    ) async {
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AssistantScreen(preferences: preferences),
          ),
        );
        await tester.pumpAndSettle();
      }

      final warning = find.textContaining('makes every question slower');
      await open();
      expect(warning, findsNothing);

      await preferences.setAiNotesContextCount(200);
      await open();
      await tester.scrollUntilVisible(
        warning,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(warning, findsOneWidget);
    });
  });
}
