import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/platform/ai_provider.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// The recap has to survive a cold launch, and it was not surviving one.
///
/// Reported as: the card comes back open, saying there is nothing to
/// summarise, on a library full of notes — and then minutes later the
/// previous recap appears by itself.
///
/// The cause is a race nothing on screen made visible. `timelineStream` is a
/// broadcast controller, so an event fired with nobody listening is gone
/// rather than queued, and `NexServices.bootstrap` fires one before this
/// screen is built. The notes were never at risk — `_loadTimeline` fetches
/// them itself — but the recap's trigger hung off the stream alone, so it
/// waited for the *next* event: a capture, or leaving the app and coming
/// back. Whatever happened first, minutes later.
void main() {
  late Directory tmp;
  late InProcessDb db;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarding.complete': true,
      'onboarding.tour_complete': true,
    });
    tmp = Directory.systemTemp.createTempSync('nex_recap_launch_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    db = InProcessDb(dbPath: dbPath, deviceId: 'test');
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('a cold launch shows the recap it already has', (tester) async {
    // A provider, so the card exists at all.
    await preferences.setAiEnabled(true);
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    // Yesterday evening's work: a recap was made and filed under today.
    const recap = 'The plumber has not called back and the bread is still on '
        'the list.';
    await preferences.setAiDaySummary(
      text: recap,
      dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
    );
    await services.captureText('something already here');

    // And now the app starts. Deliberately nothing after this point emits on
    // the timeline stream: that is the whole of the cold-launch case, and a
    // `refreshTimeline()` here would hide the bug by handing the screen the
    // event it was waiting for.
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The notes were never the problem — they arrive by their own fetch.
    expect(find.text('something already here'), findsOneWidget);
    // The recap is what was missing. No model is reached for this: the cache
    // is filed under today, so the card is restored from it.
    expect(find.text(recap), findsOneWidget);
  });
}
