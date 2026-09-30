import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';

import 'support/nex_harness.dart';

/// W6.6: one field that finds any setting, and the row it finds is the real
/// row — a switch found here is switched here.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_settings_search_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, {String locale = 'en'}) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SettingsSheet(services: services, preferences: preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder searchField() => find.byType(TextField).first;

  testWidgets('a word from inside a page finds the row that opens it', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(searchField(), 'accent');
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Capture haptics'), findsNothing);
  });

  testWidgets('found rows stay above the keyboard', (tester) async {
    // The report: with a few results the sheet shrank to the bottom of the
    // screen and the keyboard covered them. Opened the way the app opens it,
    // as a modal sheet, because a page body resizes for the keyboard itself.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => nexShowSheet<void>(
                context: context,
                builder: (_) =>
                    SettingsSheet(services: services, preferences: preferences),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(searchField(), 'backup');
    await tester.pumpAndSettle();
    final row = find.text('Taking it with you');
    expect(row, findsWidgets);
    await tester.ensureVisible(row.first);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(row.first).bottom,
      lessThan(2000 - 800),
      reason: 'the row is above the keyboard',
    );
  });

  testWidgets('a switch found by search works where it is found', (
    tester,
  ) async {
    await open(tester);
    final before = preferences.threadSuggestions;
    await tester.enterText(searchField(), 'thread');
    await tester.pumpAndSettle();
    expect(find.byType(NexSwitchTile), findsWidgets);
    await tester.tap(find.text('Suggest threads after a capture'));
    await tester.pumpAndSettle();
    expect(preferences.threadSuggestions, !before);
  });

  testWidgets('a section name brings all of it; nonsense finds nothing', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(searchField(), 'capture');
    await tester.pumpAndSettle();
    expect(find.text('Hold menu'), findsOneWidget);

    await tester.enterText(searchField(), 'zzzqqq');
    await tester.pumpAndSettle();
    expect(find.text('No setting matches that.'), findsOneWidget);

    await tester.enterText(searchField(), '');
    await tester.pumpAndSettle();
    expect(find.text('No setting matches that.'), findsNothing);
  });

  testWidgets('Persian finds Persian, whichever keyboard typed it', (
    tester,
  ) async {
    await preferences.setLocale('fa');
    await open(tester, locale: 'fa');
    // Arabic yeh, as some keyboards type it.
    await tester.enterText(searchField(), 'رنگ تأكيدي');
    await tester.pumpAndSettle();
    expect(find.text('پوسته'), findsWidgets);
  });
}
