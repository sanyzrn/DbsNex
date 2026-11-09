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
      final animation = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_CapturePasteSlot',
      );
      final visibleSlot = tester.widget<Widget>(animation);
      await tester.enterText(field, 'text');
      await tester.pumpAndSettle();
      final hiddenSlot = tester.widget<Widget>(animation);
      // Isolate this component from the capture sheet's other size transitions.
      Widget reduced(Widget child) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Row(children: [child])),
        ),
      );
      await tester.pumpWidget(reduced(visibleSlot));
      await tester.pumpAndSettle();
      await tester.pumpWidget(reduced(hiddenSlot));
      await tester.pump();
      expect(tester.getSize(slot).width, 0);
      await tester.pumpWidget(reduced(visibleSlot));
      await tester.pump();
      expect(tester.getSize(slot).width, 48);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ]) {
    for (final language in ['en', 'fa']) {
      testWidgets('$language $kind paste fades and returns its entire column', (
        tester,
      ) async {
        // A link box is the exception this test also pins: its slot never
        // leaves. Empty it is Paste; once words are in, it becomes Clear —
        // the one-tap way out of a paste that missed, in a field whose one
        // line leaves no room to find select-all in. Note and checklist
        // keep the fade: their field is multiline and carries the editor's
        // own selection tools.
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
          expect(
            tester.getSize(slot).width,
            allOf(greaterThan(0), lessThan(48)),
          );
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
          expect(tester.getSize(slot).width, 0);
          expect(tester.getSize(field).width, closeTo(width + 48, 0.01));
          expect(paste.hitTestable(), findsNothing);
        }
        await tester.enterText(field, ' ');
        await tester.pumpAndSettle();
        if (!isLink) expect(tester.getSize(slot).width, 0);
        await tester.enterText(field, '');
        await tester.pump();
        if (!isLink) {
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            tester.getSize(slot).width,
            allOf(greaterThan(0), lessThan(48)),
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
          isLink ? 48 : 0,
          reason: isLink ? 'a link box keeps its slot as Clear' : 'reclaimed',
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
}
