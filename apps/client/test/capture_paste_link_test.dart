import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// An address pasted into an empty note is a link someone is saving: the box
/// becomes a link box, so it is kept as a link note with the page's title,
/// rather than as a line of text that happens to be a URL.
void main() {
  Future<void> open(
    WidgetTester tester,
    String clipboard, {
    CaptureKind kind = CaptureKind.note,
    String language = 'en',
  }) async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': clipboard},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        theme: nexSoftLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: h.services,
            preferences: h.preferences,
            initialKind: kind,
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture-paste')));
    await tester.pumpAndSettle();
  }

  TextEditingController field(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byType(CaptureSheet),
          matching: find.byType(TextField),
        ),
      )
      .controller!;

  // Clear is the link box's own slot: it is there only when the box is one.
  final linkBox = find.byKey(const ValueKey('capture-clear'));

  for (final language in ['en', 'fa']) {
    testWidgets('$language: a pasted address turns the note into a link', (
      tester,
    ) async {
      await open(tester, '  https://example.com/article  ', language: language);
      expect(linkBox, findsOneWidget);
      expect(field(tester).text, 'https://example.com/article');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an address without a scheme counts too', (tester) async {
    await open(tester, 'example.com/x');
    expect(linkBox, findsOneWidget);
    expect(field(tester).text, 'example.com/x');
  });

  testWidgets('words, or an address among words, stay a note', (tester) async {
    await open(tester, 'read https://example.com later');
    expect(linkBox, findsNothing);
    expect(field(tester).text, 'read https://example.com later');
  });

  testWidgets('a checklist keeps the address as an item', (tester) async {
    await open(tester, 'https://example.com', kind: CaptureKind.checklist);
    expect(linkBox, findsNothing);
    expect(field(tester).text, 'https://example.com');
  });

  testWidgets('the Note chip turns it back, address and all', (tester) async {
    await open(tester, 'https://example.com');
    expect(linkBox, findsOneWidget);
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.captureKindNote));
    await tester.pumpAndSettle();
    expect(linkBox, findsNothing);
    expect(field(tester).text, 'https://example.com');
  });
}
