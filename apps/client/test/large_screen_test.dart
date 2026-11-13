import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/large_screen.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// Target API 36 (Android 16): a fixed orientation is honoured on a phone and
/// ignored on a large screen, so a tablet or an unfolded foldable runs Nex at
/// whatever shape it is held in. These are the shapes, and the screens a
/// person reaches first, laid out without an overflow in either language.
void main() {
  test('a phone is not a large screen; a tablet and a foldable are', () {
    expect(nexLargeScreen(const Size(412, 915)), isFalse);
    expect(nexLargeScreen(const Size(915, 412)), isFalse);
    expect(nexLargeScreen(const Size(800, 1280)), isTrue);
    expect(nexLargeScreen(const Size(1280, 800)), isTrue);
    expect(nexLargeScreen(const Size(673, 841)), isTrue);
  });

  const shapes = {
    'tablet landscape': Size(1280, 800),
    'tablet portrait': Size(800, 1280),
    'unfolded foldable': Size(841, 673),
    'small tablet landscape': Size(960, 600),
  };

  Future<NexTestHarness> open(
    WidgetTester tester,
    Size size,
    String locale, {
    bool onboarded = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await NexTestHarness.create(
      onboarded: onboarded,
      preferences: {'appearance.locale': locale},
    );
    addTearDown(h.dispose);
    await h.services.captureText(
      'A first line\n\nAnd a body long enough to wrap on a narrow card, '
      'so the detail has something to lay out.',
    );
    await tester.pumpWidget(h.app());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    return h;
  }

  for (final MapEntry(key: shape, value: size) in shapes.entries) {
    for (final locale in ['en', 'fa']) {
      testWidgets('$shape, $locale: the timeline keeps a reading width', (
        tester,
      ) async {
        await open(tester, size, locale);
        expect(tester.takeException(), isNull);
        // The column of cards does not stretch across a tablet held
        // sideways: a line of a note stays a line someone can read.
        final card = tester.getRect(find.byType(NoteCard).first);
        expect(card.width, lessThanOrEqualTo(760));
        expect(card.center.dx, closeTo(size.width / 2, 1));
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$shape, $locale: capture and a note open in place', (
        tester,
      ) async {
        await open(tester, size, locale);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(EditableText), findsWidgets);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NoteCard).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$shape, $locale: first run and Settings lay out', (
        tester,
      ) async {
        await open(tester, size, locale, onboarded: false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());

        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            theme: nexSoftLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsSheet(
              services: h.services,
              preferences: h.preferences,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
