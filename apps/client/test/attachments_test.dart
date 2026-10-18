import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:nex_client/widgets/pdf_reader.dart';
import 'package:nex_client/widgets/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/card_strings.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_client/widgets/photo_viewer.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/screens/photo_crop_screen.dart';
import 'package:path/path.dart' as p;

import 'support/nex_harness.dart';

/// Several files on one note — `docs/14-attachments.md`, as seen in the app.
/// A hold let go where it was: the tile flies home, then its menu opens.
Future<void> settleHold(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

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

  for (final save in [false, true]) {
    testWidgets(
      'attached image editor ${save ? "saves a separate image" : "cancels unchanged"}',
      (tester) async {
        final services = harness.services;
        final original = Uint8List.fromList(
          img.encodePng(img.Image(width: 40, height: 30)),
        );
        final edited = Uint8List.fromList(
          img.encodePng(img.Image(width: 20, height: 10)),
        );
        late Note note;
        late NoteAttachment attachment;
        await tester.runAsync(() async {
          note = (await services.captureText('keep my words'))!;
          attachment = (await services.attachBytes(
            note.id,
            original,
            kind: AttachmentKind.photo,
            extension: '.png',
          ))!;
          await services.setAttachmentCaption(attachment.id, 'keep my caption');
        });
        await openNote(tester, note.id);
        await tester.longPress(
          find.byKey(ValueKey('attachment-${attachment.id}')),
        );
        await settleHold(tester);
        expect(find.byKey(const ValueKey('attachment-edit')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('attachment-edit')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 12 && find.byType(PhotoCropScreen).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }
        expect(find.byType(PhotoCropScreen), findsOneWidget);
        // PhotoCropScreen's crop/annotation processing has its own pixel tests;
        // here exercise its real returned bytes through the attachment save path.
        Navigator.of(
          tester.element(find.byType(PhotoCropScreen)),
        ).pop<Uint8List>(save ? edited : null);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(find.byType(PhotoCropScreen), findsNothing);
        if (save) {
          for (var i = 0; i < 40; i++) {
            if ((await services.attachmentsFor(note.id)).single.mediaUri !=
                attachment.mediaUri) {
              break;
            }
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();
          }
        }
        final now = (await services.attachmentsFor(note.id)).single;
        expect(now.id, attachment.id);
        expect(now.position, attachment.position);
        expect(now.caption, 'keep my caption');
        expect((await services.getById(note.id))!.content, 'keep my words');
        expect(File(attachment.mediaUri).readAsBytesSync(), original);
        if (save) {
          expect(now.mediaUri, isNot(attachment.mediaUri));
          final decoded = img.decodeImage(
            File(now.mediaUri).readAsBytesSync(),
          )!;
          expect((decoded.width, decoded.height), (20, 10));
        } else {
          expect(now.mediaUri, attachment.mediaUri);
          expect(now.mediaHash, attachment.mediaHash);
        }
        expect(tester.takeException(), isNull);
      },
    );
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
    await settleHold(tester);
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

  testWidgets('a held tile moves where it is dropped, or by its menu', (
    tester,
  ) async {
    final services = harness.services;
    late Note note;
    late List<NoteAttachment> made;
    await tester.runAsync(() async {
      note = (await services.captureText('three angles'))!;
      made = [
        for (var i = 0; i < 3; i++)
          (await services.attachBytes(
            note.id,
            bytes,
            kind: AttachmentKind.photo,
            extension: '.jpg',
          ))!,
      ];
    });
    await openNote(tester, note.id);
    Future<List<String>> order() async {
      late List<NoteAttachment> now;
      await tester.runAsync(
        () async => now = await services.attachmentsFor(note.id),
      );
      return [for (final a in now) a.id];
    }

    // Picked up and carried past the next two.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('attachment-${made[0].id}'))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(await order(), [made[1].id, made[2].id, made[0].id]);
    expect(
      find.byKey(const ValueKey('attachment-remove')),
      findsNothing,
      reason: 'a hold that moved is not a question',
    );

    // Held and let go where it was: the menu, with a step to the end.
    await tester.longPress(find.byKey(ValueKey('attachment-${made[1].id}')));
    await settleHold(tester);
    expect(find.byKey(const ValueKey('attachment-earlier')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('attachment-later')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(await order(), [made[2].id, made[1].id, made[0].id]);
  });

  testWidgets('photos open as a gallery that says where you are', (
    tester,
  ) async {
    final services = harness.services;
    late Note note;
    late List<NoteAttachment> made;
    await tester.runAsync(() async {
      note = (await services.captureText('three angles'))!;
      made = [
        for (var i = 0; i < 3; i++)
          (await services.attachBytes(
            note.id,
            bytes,
            kind: AttachmentKind.photo,
            extension: '.jpg',
          ))!,
      ];
    });
    await openNote(tester, note.id);
    expect(find.byKey(const ValueKey('attachments-summary')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('attachment-${made[1].id}')));
    await tester.pumpAndSettle();
    expect(find.byType(NexPhotoGallery), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('one becomes a note of its own from its menu', (tester) async {
    final services = harness.services;
    late Note note;
    late NoteAttachment file;
    await tester.runAsync(() async {
      note = (await services.captureText('contract'))!;
      final source = File(p.join(harness.mediaDir, 'annex.pdf'));
      await source.writeAsBytes(bytes);
      file = (await services.attachFile(
        note.id,
        source.path,
        kind: AttachmentKind.file,
        name: 'annex.pdf',
        mimeType: 'application/pdf',
      ))!;
    });
    await openNote(tester, note.id);

    await tester.longPress(find.byKey(ValueKey('attachment-${file.id}')));
    await settleHold(tester);
    for (final action in ['share', 'save', 'rename', 'detach']) {
      expect(find.byKey(ValueKey('attachment-$action')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('attachment-main')),
      findsNothing,
      reason: 'only a photo on a photo note can be its photo',
    );
    await tester.tap(find.byKey(const ValueKey('attachment-detach')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('attachment-${file.id}')), findsNothing);
    late List<Note> all;
    await tester.runAsync(
      () async => all = await services.worker.timeline(limit: 10, offset: 0),
    );
    expect(all.where((n) => n.type == NoteType.file), hasLength(1));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets('a voice clip shows its length and plays in a sheet', (
    tester,
  ) async {
    final services = harness.services;
    late Note note;
    late NoteAttachment clip;
    await tester.runAsync(() async {
      note = (await services.captureText('meeting'))!;
      final source = File(p.join(harness.mediaDir, 'clip.m4a'));
      await source.writeAsBytes(bytes);
      clip = (await services.attachFile(
        note.id,
        source.path,
        kind: AttachmentKind.voice,
        mimeType: 'audio/mp4',
        durationMs: 65000,
      ))!;
    });
    await openNote(tester, note.id);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('attachment-${clip.id}')),
        matching: find.text('1:05'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a link offers Attach and retains its files without changing the URL',
    (tester) async {
      late Note note;
      await tester.runAsync(() async {
        note = (await harness.services.captureLink(
          'https://example.com/reference',
        ))!;
      });
      await openNote(tester, note.id);
      await tester.tap(find.byKey(const ValueKey('attachment-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-file')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('attach-file'))),
      ).pop();
      await tester.pumpAndSettle();
      late NoteAttachment file;
      await tester.runAsync(() async {
        final source = File(p.join(harness.mediaDir, 'reference.pdf'))
          ..writeAsBytesSync(bytes);
        file = (await harness.services.attachFile(
          note.id,
          source.path,
          kind: AttachmentKind.file,
          name: 'reference.pdf',
          mimeType: 'application/pdf',
        ))!;
        final saved = (await harness.services.getById(note.id))!;
        expect(saved.type, NoteType.link);
        expect(saved.linkUrl, 'https://example.com/reference');
        expect(
          (await harness.services.attachmentsFor(note.id)).single.id,
          file.id,
        );
      });
      // Reopen from storage, rather than relying on the detail sheet's state.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await openNote(tester, note.id);
      expect(find.byKey(ValueKey('attachment-${file.id}')), findsOneWidget);
    },
  );

  for (final extension in ['pdf', 'mp4']) {
    testWidgets(
      '$extension attachment opens inside the existing details and closes in place',
      (tester) async {
        late Note note;
        late NoteAttachment file;
        await tester.runAsync(() async {
          note = (await harness.services.captureText('meeting'))!;
          final source = File(p.join(harness.mediaDir, 'reference.$extension'))
            ..writeAsBytesSync(bytes);
          file = (await harness.services.attachFile(
            note.id,
            source.path,
            kind: AttachmentKind.file,
            name: 'reference.$extension',
            mimeType: extension == 'pdf' ? 'application/pdf' : 'video/mp4',
          ))!;
        });
        await openNote(tester, note.id);
        await tester.tap(find.byKey(ValueKey('attachment-${file.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(NoteDetailSheet), findsOneWidget);
        expect(
          find.byType(extension == 'pdf' ? NexPdfReader : NexVideoPlayer),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('attachment-preview-close')),
        );
        await tester.tap(
          find.byKey(const ValueKey('attachment-preview-close')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(extension == 'pdf' ? NexPdfReader : NexVideoPlayer),
          findsNothing,
        );
        expect(find.byKey(ValueKey('attachment-${file.id}')), findsOneWidget);
      },
    );
  }

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
