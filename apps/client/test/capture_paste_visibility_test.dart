import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  testWidgets(
    'reduced motion updates the Paste slot without an intermediate state',
    (tester) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': true};
          }
          return null;
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CaptureSheet(
              services: h.services,
              preferences: h.preferences,
              onCamera: () {},
              onGallery: () {},
              onFile: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byType(TextField),
      );
      final slot = find.byKey(const ValueKey('capture-paste-slot'));
      final paste = find.byKey(const ValueKey('capture-paste'));
      final animation = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_CapturePasteSlot',
      );
      final visibleSlot = tester.widget<Widget>(animation);
      await tester.enterText(field, 'text');
      await tester.pumpAndSettle();
      final hiddenSlot = tester.widget<Widget>(animation);
      // Isolate this component from the capture sheet's other transitions.
      Widget reduced(Widget child) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Row(children: [child])),
        ),
      );
      // The column never moves: visible or not, the slot is one touch
      // target wide. Only the icon inside it fades, so there is no size
      // state to catch mid-flight at all.
      await tester.pumpWidget(reduced(visibleSlot));
      await tester.pumpAndSettle();
      await tester.pumpWidget(reduced(hiddenSlot));
      await tester.pump();
      expect(tester.getSize(slot).width, 48);
      expect(paste.hitTestable(), findsNothing);
      await tester.pumpWidget(reduced(visibleSlot));
      await tester.pump();
      expect(tester.getSize(slot).width, 48);
      expect(paste.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ]) {
    for (final language in ['en', 'fa']) {
      testWidgets('$language $kind paste fades in a column that stays put', (
        tester,
      ) async {
        // A link box is the exception this test also pins: its slot never
        // leaves. Empty it is Paste; once words are in, it becomes Clear —
        // the one-tap way out of a paste that missed, in a field whose one
        // line leaves no room to find select-all in. Note and checklist now
        // keep the column too: only the icon fades, because reclaiming the
        // width on the first keystroke moved the field's edge under the
        // words mid-type.
        final isLink = kind == CaptureKind.link;
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        var reads = 0;
        final clipboard = kind == CaptureKind.link
            ? ' https://example.com/new '
            : '  new\nline  ';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              reads++;
              return {'text': clipboard};
            }
            if (call.method == 'Clipboard.hasStrings') {
              return {'value': true};
            }
            return null;
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
            theme: nexLightTheme(),
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
        final field = find.descendant(
          of: find.byType(CaptureSheet),
          matching: find.byType(TextField),
        );
        final paste = find.byKey(const ValueKey('capture-paste'));
        final slot = find.byKey(const ValueKey('capture-paste-slot'));
        final controller = tester.widget<TextField>(field).controller!;
        final focus = tester.widget<TextField>(field).focusNode!;
        final width = tester.getSize(field).width;
        expect(tester.getSize(slot).width, 48);
        expect(reads, 0);
        await tester.enterText(field, 'typed');
        final value = controller.value;
        await tester.pump();
        if (isLink) {
          // The slot stays put and turns into Clear; nothing fades.
          await tester.pump(const Duration(milliseconds: 150));
          expect(tester.getSize(slot).width, 48);
          expect(find.byKey(const ValueKey('capture-clear')), findsOneWidget);
        } else {
          await tester.pump(const Duration(milliseconds: 150));
          // The column stays: only the icon inside it is on its way out.
          expect(tester.getSize(slot).width, 48);
          final fading = find
              .ancestor(of: paste, matching: find.byType(Opacity))
              .first;
          expect(
            tester.widget<Opacity>(fading).opacity,
            allOf(greaterThan(0), lessThan(1)),
          );
        }
        expect(controller.value, value);
        expect(focus.hasFocus, isTrue);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(tester.widget<TextField>(field).focusNode, same(focus));
        expect(controller.value, value);
        expect(focus.hasFocus, isTrue);
        if (isLink) {
          expect(tester.getSize(slot).width, 48);
          expect(tester.getSize(field).width, closeTo(width, 0.01));
          // Clear empties the box and hands the slot back to Paste.
          await tester.tap(paste);
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(tester.getSize(slot).width, 48);
          expect(find.byKey(const ValueKey('capture-clear')), findsNothing);
        } else {
          // Settled: the column is exactly where it was, and the field with
          // it — no width was reclaimed, the icon is simply gone.
          expect(tester.getSize(slot).width, 48);
          expect(tester.getSize(field).width, closeTo(width, 0.01));
          expect(paste.hitTestable(), findsNothing);
        }
        await tester.enterText(field, ' ');
        await tester.pumpAndSettle();
        expect(tester.getSize(slot).width, 48);
        await tester.enterText(field, '');
        await tester.pump();
        if (!isLink) {
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            tester
                .widget<Opacity>(
                  find
                      .ancestor(of: paste, matching: find.byType(Opacity))
                      .first,
                )
                .opacity,
            allOf(greaterThan(0), lessThan(1)),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(slot).width, 48);
        await tester.tap(paste);
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(
          controller.text,
          kind == CaptureKind.link ? clipboard.trim() : clipboard,
        );
        expect(
          tester.getSize(slot).width,
          48,
          reason: 'the column never moves, whatever it holds',
        );
        expect(focus.hasFocus, isTrue);
        expect(controller.selection.isCollapsed, isTrue);
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Paste shows only when the clipboard holds words (asked without reading)',
    (tester) async {
      // `hasStrings` is asked on open and on resume; the words themselves are
      // read only when the button is pressed. An empty clipboard leaves the
      // column reserved but empty, rather than a button that does nothing.
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      var reads = 0;
      var asked = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            reads++;
            return {'text': 'words'};
          }
          if (call.method == 'Clipboard.hasStrings') {
            asked++;
            return {'value': asked > 1};
          }
          return null;
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CaptureSheet(
              services: h.services,
              preferences: h.preferences,
              onCamera: () {},
              onGallery: () {},
              onFile: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paste = find.byKey(const ValueKey('capture-paste'));
      final slot = find.byKey(const ValueKey('capture-paste-slot'));
      // Asked once on open; the clipboard was empty then, so no button.
      expect(asked, 1);
      expect(tester.getSize(slot).width, 48);
      expect(paste.hitTestable(), findsNothing);
      expect(reads, 0);

      // Coming back to the app asks again — this time there are words.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(asked, 2);
      expect(paste.hitTestable(), findsOneWidget);

      await tester.tap(paste);
      await tester.pumpAndSettle();
      expect(reads, 1);
      final field = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller!.text, 'words');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
