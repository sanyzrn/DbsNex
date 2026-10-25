import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app_version.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/whats_new_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// 2.3.0: "What's new" after an update, read from the bundled changelog.
void main() {
  test('a release section becomes titled items', () {
    const raw = '''
## Unreleased

## v9.9.9

- **Bells.** A reminder rings on its card.
- A plain line.

## v9.9.8

- **Old.** Not this one.
''';
    final items = whatsNewItems(raw, '9.9.9');
    expect(items, hasLength(2));
    expect(items.first.title, 'Bells');
    expect(items.first.body, 'A reminder rings on its card.');
    expect(items.last.title, isEmpty);
    expect(items.last.body, 'A plain line.');
  });

  test('this version has notes in both languages', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final file in ['assets/CHANGELOG.md', 'assets/CHANGELOG.fa.md']) {
      final raw = await rootBundle.loadString(file);
      expect(whatsNewItems(raw, nexAppVersion), isNotEmpty, reason: file);
    }
  });

  for (final lang in ['en', 'fa']) {
    testWidgets(
      'shown once after an update, never on a fresh install ($lang)',
      (tester) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await h.preferences.completeOnboarding();
        await h.preferences.setWhatsNewSeen('0.0.1');
        late BuildContext host;
        await tester.pumpWidget(
          MaterialApp(
            theme: nexLightTheme(),
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                host = context;
                return const Scaffold();
              },
            ),
          ),
        );
        await tester.runAsync(
          () => nexMaybeShowWhatsNew(
            host,
            h.preferences,
          ).timeout(const Duration(milliseconds: 300), onTimeout: () {}),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(h.preferences.whatsNewSeen, nexAppVersion);
        await tester.tap(find.byKey(const ValueKey('whats-new-done')));
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewSheet), findsNothing);
      },
    );
  }
}
