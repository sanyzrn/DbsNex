import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/card_strings.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// Several files on one note — `docs/14-attachments.md`, as seen in the app.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_attach_'));
  tearDown(() => harness.dispose());

  // Not a real JPEG: the tiles and the viewer only need a path, and an
  // image that fails to decode draws its error placeholder.
  final bytes = Uint8List.fromList(List.filled(32, 7));

  Future<void> openNote(WidgetTester tester, String noteId) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Reduce motion keeps the loading shimmer from asking for frames
        // forever; the rest of the screen's measurements stay real.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: NoteDetailSheet(
            services: harness.services,
            noteId: noteId,
            preferences: harness.preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a text note shows what it carries, and can carry more', (
    tester,
  ) async {
    final services = harness.services;
    late Note note;
    late NoteAttachment first;
    await tester.runAsync(() async {
      note = (await services.captureText('the fridge receipt'))!;
      first = (await services.attachBytes(
        note.id,
        bytes,
        kind: AttachmentKind.photo,
        extension: '.jpg',
      ))!;
      await services.attachBytes(
        note.id,
        bytes,
        kind: AttachmentKind.photo,
        extension: '.jpg',
      );
    });
    await openNote(tester, note.id);

    expect(find.text('Attached'), findsOneWidget);
    expect(find.byKey(ValueKey('attachment-${first.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('attachment-add')), findsOneWidget);
    expect((await services.getById(note.id))!.attachmentCount, 2);
  });

  testWidgets('removing one says so, and Undo puts it back', (tester) async {
    final services = harness.services;
    late Note note;
    late NoteAttachment attachment;
    await tester.runAsync(() async {
      note = (await services.captureText('two angles'))!;
      attachment = (await services.attachBytes(
        note.id,
        bytes,
        kind: AttachmentKind.photo,
        extension: '.jpg',
      ))!;
    });
    await openNote(tester, note.id);

    await tester.longPress(find.byKey(ValueKey('attachment-${attachment.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-remove')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('attachment-${attachment.id}')), findsNothing);
    expect(find.text('Attachment removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('attachment-${attachment.id}')), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('a checklist offers no attachments', (tester) async {
    late Note note;
    await tester.runAsync(() async {
      note = (await harness.services.captureChecklist([
        const ChecklistItem(text: 'milk', done: false),
      ]))!;
    });
    await openNote(tester, note.id);
    expect(find.byKey(const ValueKey('attachment-add')), findsNothing);
  });

  testWidgets('the card says how many more files, in the reader\'s digits', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final note = Note(
      id: 'n',
      type: NoteType.text,
      content: 'receipt',
      createdAt: now,
      updatedAt: now,
      deviceId: 'd',
      rev: 1,
      syncState: SyncState.pending,
      attachmentCount: 3,
    );
    for (final (locale, mark, spoken) in [
      ('en', '+3', '3 more files'),
      ('fa', '+۳', '۳ فایل دیگر'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  NoteCard(note: note, strings: nexCardStrings(context)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(mark), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').contains(spoken),
        ),
        findsOneWidget,
      );
    }
  });
}
