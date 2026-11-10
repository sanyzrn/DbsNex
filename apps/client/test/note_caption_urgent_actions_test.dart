import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  for (final language in ['en', 'fa']) {
    testWidgets('$language text caption and urgency are independent actions', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      final note = (await h.services.captureText(
        'Primary content remains unchanged.',
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          theme: nexLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: h.services,
              preferences: h.preferences,
              noteId: note.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(NoteDetailSheet)),
      );
      await tester.ensureVisible(find.text(l.addCaption));
      await tester.tap(find.text(l.addCaption));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(NoteEditorSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Separate caption needle260.');
      await tester.tap(find.byTooltip(l.save));
      await tester.pumpAndSettle();
      var saved = (await h.services.getById(note.id))!;
      expect(saved.caption, 'Separate caption needle260.');
      expect(saved.content, note.content);
      expect(find.text(l.editCaption), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text(l.markUrgent), findsOneWidget);
      await tester.tap(find.text(l.markUrgent));
      await tester.pumpAndSettle();
      saved = (await h.services.getById(note.id))!;
      expect(saved.isUrgent, isTrue);
      expect(saved.pinnedAt, isNull);
      expect(saved.content, note.content);
      expect(saved.caption, 'Separate caption needle260.');
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text(l.removeUrgent), findsOneWidget);
      await tester.tap(find.text(l.removeUrgent));
      await tester.pumpAndSettle();
      expect((await h.services.getById(note.id))!.isUrgent, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(h.dispose);
    });
  }
}
