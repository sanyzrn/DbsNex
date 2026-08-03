import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/about_screen.dart';

import 'support/in_process_db.dart';

/// flutter_test registers no plugin for `getApplicationSupportDirectory`,
/// which NexCrashLog.open() calls — without this, tapping "Share
/// diagnostics" would hit a real platform channel that does not exist here.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_about_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tmp.path);
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
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'offers to share diagnostics, and says so when there are none yet',
    (tester) async {
      // The privacy section sits below the fold on the default test surface,
      // and a ListView only mounts what is within (or near) its viewport.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutScreen(services: services, preferences: preferences),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Share diagnostics'), findsOneWidget);

      // No crash has happened in this run, so there is nothing to hand to the
      // share sheet — this is the branch that says so rather than opening it
      // on an empty file.
      await tester.tap(find.text('Share diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to share yet'), findsOneWidget);
    },
  );

  testWidgets(
    'feedback opens a compose sheet, and falls back to the issue tracker '
    'when no feedback server is configured',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // flutter_test ships no default handler for the clipboard channel, so an
      // un-mocked await on Clipboard.getData never resolves — it is not
      // exercised anywhere else in this suite.
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': clipboardText};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AboutScreen(services: services, preferences: preferences),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send feedback'), findsOneWidget);
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'the timeline is great');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // This test build has no NEX_FEEDBACK_API_URL, so sending answers
      // "unavailable" without ever touching the network — the sheet stays
      // open, with the typed text still there, and offers the old link as a
      // fallback rather than a dead end.
      expect(
        find.text("Feedback isn't available in this build yet"),
        findsOneWidget,
      );
      expect(find.text('the timeline is great'), findsOneWidget);

      await tester.tap(find.text('Open a GitHub issue instead'));
      await tester.pumpAndSettle();

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, 'https://github.com/sanyzrn/DbsNex/issues/new');
    },
  );

  testWidgets('the Send button stays above the keyboard, not under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    // A realistic on-screen keyboard height — the field autofocuses, so a
    // real device would already have the keyboard up by the time this sheet
    // is visible.
    const keyboardHeight = 500.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AboutScreen(services: services, preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    final send = tester.getRect(find.text('Send'));
    expect(
      send.bottom,
      lessThanOrEqualTo(1600 / 1 - keyboardHeight),
      reason: 'the Send button must end above the keyboard, not under it',
    );
  });

  testWidgets('the wordmark image swaps with the theme, not just the tint', (
    tester,
  ) async {
    Future<void> pumpWithBrightness(Brightness brightness) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: AboutScreen(services: services, preferences: preferences),
      ),
    );

    await pumpWithBrightness(Brightness.light);
    await tester.pumpAndSettle();
    Image image = tester.widget(find.byType(Image).first);
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/text_logo_light.png',
    );

    await pumpWithBrightness(Brightness.dark);
    await tester.pumpAndSettle();
    image = tester.widget(find.byType(Image).first);
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/text_logo_dark.png',
    );
  });
}
