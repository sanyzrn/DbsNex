import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

import 'support/nex_harness.dart';

void main() {
  for (final kind in [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ]) {
    testWidgets('${kind.name}: paste keeps the editor\'s focus', (
      tester,
    ) async {
      // The capture box's empty Send is a Paste: the clipboard's words go
      // straight into the field, typed by nobody. The paste is a write into
      // the controller from outside, and the editor — one the framework owns
      // — must come out of it with its focus and its selection intact.
      final h = await NexTestHarness.create();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'https://example.com'};
        }
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': true};
        }
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        await h.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
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
      final editor = find.descendant(
        of: find.byType(NexTextField),
        matching: find.byType(EditableText),
      );
      expect(editor, findsOneWidget);
      await tester.tap(editor);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('capture-send')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<NexTextField>(find.byType(NexTextField)).controller.text,
        'https://example.com',
      );
      expect(
        tester.state<EditableTextState>(editor).widget.focusNode.hasFocus,
        isTrue,
        reason: 'the paste must not leave the editor without its focus',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
