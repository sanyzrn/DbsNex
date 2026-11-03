import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  for (final kind in [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ]) {
    for (final language in ['en', 'fa']) {
      testWidgets('$language $kind paste fades and returns its entire column', (
        tester,
      ) async {
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
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(tester.widget<TextField>(field).focusNode, same(focus));
        expect(controller.value, value);
        expect(focus.hasFocus, isTrue);
        expect(tester.getSize(slot).width, 0);
        expect(tester.getSize(field).width, closeTo(width + 48, 0.01));
        expect(paste.hitTestable(), findsNothing);
        await tester.enterText(field, ' ');
        await tester.pumpAndSettle();
        expect(tester.getSize(slot).width, 0);
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(tester.getSize(slot).width, 48);
        await tester.tap(paste);
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(
          controller.text,
          kind == CaptureKind.link ? clipboard.trim() : clipboard,
        );
        expect(tester.getSize(slot).width, 0);
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
