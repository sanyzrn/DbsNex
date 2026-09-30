import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/library_screen.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/tools_screen.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// W6.1: the screens people spend their time on clear Flutter's own
/// accessibility guidelines — every tappable thing has a name a screen reader
/// can say, is big enough to hit, and its text can be read against what is
/// behind it — in both directions and at the largest text size.
void main() {
  Future<void> audit(
    WidgetTester tester,
    Widget Function(NexTestHarness harness) screen, {
    String locale = 'en',
    double textScale = 1,
    bool dark = false,
    bool seed = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final harness = await NexTestHarness.create(name: 'nex_a11y_');
    addTearDown(harness.dispose);
    if (seed) {
      await harness.services.captureText(
        locale == 'fa' ? 'یادداشتی برای آزمون' : 'A note to test with',
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: nexLightTheme(),
        darkTheme: nexDarkTheme(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen(harness),
      ),
    );
    // Some screens keep a gentle animation running (a loading shimmer), so
    // settle for a bounded time rather than until nothing moves.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  }

  final screens = <String, Widget Function(NexTestHarness)>{
    'timeline': (h) => h.app(),
    'note details': (h) => Scaffold(
      body: FutureBuilder(
        future: h.db.timeline(limit: 1),
        builder: (context, snapshot) => snapshot.hasData
            ? NoteDetailSheet(
                services: h.services,
                noteId: snapshot.data!.first.id,
                preferences: h.preferences,
              )
            : const SizedBox.shrink(),
      ),
    ),
    'settings': (h) => Scaffold(
      body: SettingsSheet(services: h.services, preferences: h.preferences),
    ),
    'library': (h) =>
        LibraryScreen(services: h.services, preferences: h.preferences),
    'tools': (_) => const ToolsScreen(),
    'recurring': (h) => Scaffold(body: CommitmentsSheet(services: h.services)),
    'capture': (h) => Scaffold(
      body: CaptureSheet(
        services: h.services,
        preferences: h.preferences,
        onVoice: () {},
        onCamera: () {},
        onGallery: () {},
        onFile: () {},
        onChecklist: () {},
        onLink: () {},
      ),
    ),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key}: English, light', (tester) async {
      await audit(tester, entry.value);
    });
    testWidgets('${entry.key}: Persian, dark, largest text', (tester) async {
      await audit(tester, entry.value, locale: 'fa', dark: true, textScale: 2);
    });
  }
}
