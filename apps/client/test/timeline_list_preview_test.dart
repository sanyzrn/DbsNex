import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/platform/link_art.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/tile_previews.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_client/widgets/parallax_image.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  testWidgets('timeline list sizes give captions and media the intended room', (
    tester,
  ) async {
    final h = await NexTestHarness.create(
      preferences: {'appearance.timeline_grid': false},
    );
    addTearDown(h.dispose);
    addTearDown(NexTilePreviews.clear);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 3800);
    addTearDown(tester.view.reset);

    final body = List.generate(16, (index) => 'Line ${index + 1}').join('\n');
    const caption = 'Keep this title small';
    const voiceCaption = 'Recording from the review';
    const transcript = 'Two cover options by Thursday';
    final short = (await h.services.captureText(
      'ایده منو more action دمو اپوس',
    ))!;
    final long = (await h.services.captureText(body))!;
    await h.services.setCaption(long.id, caption);

    final picture = Uint8List.fromList(
      img.encodePng(img.Image(width: 12, height: 14)),
    );
    final imagePath = '${h.mediaDir}/test.png';
    File(imagePath).writeAsBytesSync(picture);
    final photo = await h.services.capturePhoto(
      mediaUri: imagePath,
      mediaHash: 'photo-preview',
    );
    await h.services.setCaption(photo.id, 'Photo caption');
    final pdfPath = '${h.mediaDir}/sample.pdf';
    final pdf = await h.services.captureFile(
      mediaUri: pdfPath,
      mediaHash: 'pdf-preview',
      originalFilename: 'sample.pdf',
      mimeType: 'application/pdf',
    );
    NexTilePreviews.debugRemember(pdfPath, page: (bytes: picture, pages: 8));

    final voice = await h.services.captureVoice(
      mediaUri: '${h.mediaDir}/sample.wav',
      mediaHash: 'voice-preview',
      durationMs: 30000,
    );
    await h.services.setCaption(voice.id, voiceCaption);
    h.db.seedTranscript(voice.id, transcript);
    final checklist = (await h.services.captureChecklist([
      const ChecklistItem(text: 'Check the bleed', done: false),
      const ChecklistItem(text: 'Review the fonts', done: false),
      const ChecklistItem(text: 'Send the final proof', done: false),
    ]))!;
    final videoPath = '${h.mediaDir}/sample.mp4';
    final video = await h.services.captureFile(
      mediaUri: videoPath,
      mediaHash: 'video-preview',
      originalFilename: 'sample.mp4',
      mimeType: 'video/mp4',
    );
    NexTilePreviews.debugRemember(videoPath, frame: picture);
    final link = (await h.services.captureLink('https://example.test/page'))!;
    NexLinkArt.instance.debugRemember(link.id, cover: File(imagePath));
    final noCover = (await h.services.captureLink(
      'https://www.youtube.com/watch?v=video123456',
    ))!;
    final archive = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/archive.zip',
      mediaHash: 'archive',
      originalFilename: 'archive.zip',
      mimeType: 'application/zip',
    );
    final markdown = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/brief.md',
      mediaHash: 'brief-md',
      originalFilename: 'brief.md',
      mimeType: 'text/markdown',
    );
    await h.services.setCaption(markdown.id, 'یادداشت جلسه');
    final plainLink = (await h.services.captureLink(
      'https://example.test/brief',
    ))!;
    final oneItem = (await h.services.captureChecklist([
      const ChecklistItem(text: 'One item', done: false),
    ]))!;
    final unseenPdf = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/unreadable.pdf',
      mediaHash: 'unreadable',
      originalFilename: 'unreadable.pdf',
      mimeType: 'application/pdf',
    );
    NexTilePreviews.debugRemember(unseenPdf.mediaUri!, none: true);
    await h.services.refreshTimeline();
    await h.preferences.setHoldMenuActions([NexHoldAction.expand]);

    await h.preferences.setCardDensity(NexCardDensity.compact);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    Finder card(Note note) => find.byWidgetPredicate(
      (widget) => widget is NoteCard && widget.note.id == note.id,
    );
    double height(Note note) => tester.getSize(card(note)).height;
    Finder wide(Note note) => find.byKey(ValueKey('list-wide-${note.id}'));
    Finder tileMedia(Note note) =>
        find.byKey(ValueKey('grid-media-${note.id}'));
    Finder inside(Finder parent, Finder child) =>
        find.descendant(of: parent, matching: child);
    Finder item(int index) =>
        inside(wide(checklist), find.byKey(ValueKey('grid-item-$index')));
    Finder words(String text) => find.byWidgetPredicate(
      (widget) => widget is NexTextSurface && widget.text == text,
    );

    expect(height(short), height(long));
    expect(wide(photo), findsNothing);
    expect(tileMedia(photo), findsNothing);

    await h.preferences.setCardDensity(NexCardDensity.standard);
    await tester.pumpAndSettle();
    expect(tester.widget<NexTextSurface>(words(body)).maxLines, 2);
    expect(words(caption), findsOneWidget);
    expect(tileMedia(pdf), findsNothing);
    expect(tileMedia(video), findsNothing);
    expect(card(archive), findsOneWidget);
    expect(find.byKey(ValueKey('card-play-${voice.id}')), findsOneWidget);
    expect(item(0), findsNothing);
    expect(words(voiceCaption), findsNothing);
    expect(words(transcript), findsNothing);
    await h.preferences.setNoteExpanded(voice.id, true);
    await tester.pumpAndSettle();
    expect(words(voiceCaption), findsOneWidget);
    expect(words(transcript), findsOneWidget);
    await h.preferences.setNoteExpanded(voice.id, false);
    await tester.pumpAndSettle();

    await h.preferences.setCardDensity(NexCardDensity.readable);
    await tester.pumpAndSettle();
    for (final note in [
      short,
      long,
      photo,
      pdf,
      voice,
      checklist,
      video,
      link,
      noCover,
      archive,
      markdown,
      plainLink,
      oneItem,
    ]) {
      expect(wide(note), findsOneWidget);
      expect(card(note), findsNothing);
      expect(tester.getSize(wide(note)).width, 400 - nexCardInsets.horizontal);
    }
    double wideHeight(Note note) => tester.getSize(wide(note)).height;
    final frame = NexNoteGridCard.heightFor(tester.element(wide(photo)));
    for (final note in [photo, video, pdf, link]) {
      expect(wideHeight(note), frame);
    }
    expect(wideHeight(short), lessThan(frame / 2));
    expect(wideHeight(unseenPdf), lessThan(frame / 2));
    final mark = inside(
      wide(short),
      find.byKey(ValueKey('note-pick-${short.id}')),
    );
    final line = inside(wide(short), find.text(short.content!));
    expect(
      tester.getRect(mark).center.dy,
      closeTo(tester.getRect(line).center.dy, 1),
    );

    expect(wideHeight(markdown), lessThan(frame / 2));
    expect(inside(wide(markdown), find.text('یادداشت جلسه')), findsOneWidget);
    expect(wideHeight(long), greaterThan(wideHeight(short)));
    expect(wideHeight(archive), lessThan(frame / 2));
    expect(wideHeight(plainLink), lessThan(frame));
    expect(wideHeight(voice), lessThan(frame));
    expect(words(voiceCaption), findsOneWidget);
    expect(words(transcript), findsOneWidget);
    expect(wideHeight(oneItem), lessThan(wideHeight(checklist)));
    expect(
      tester.getSize(item(0)).height,
      greaterThanOrEqualTo(nexMinTapTarget),
    );
    NexLinkArt.instance.debugRemember(plainLink.id, cover: File(imagePath));
    await tester.pumpAndSettle();
    expect(wideHeight(plainLink), frame);
    NexLinkArt.instance.debugRemember(plainLink.id);
    await tester.pumpAndSettle();
    expect(wideHeight(plainLink), lessThan(frame));
    for (final note in [photo, video, link]) {
      final picture = inside(wide(note), find.byType(NexParallaxImage));
      expect(picture, findsOneWidget);
      expect(tester.getRect(picture), tester.getRect(wide(note)));
    }
    for (final note in [photo, video, pdf, link]) {
      expect(tileMedia(note), findsOneWidget);
    }
    for (final note in [photo, video, pdf]) {
      expect(
        inside(wide(note), find.byKey(const ValueKey('grid-media-caption'))),
        findsOneWidget,
      );
    }
    expect(
      inside(wide(video), find.byIcon(Icons.play_arrow_rounded)),
      findsOneWidget,
    );
    expect(
      inside(wide(link), find.byKey(const ValueKey('grid-link-site'))),
      findsOneWidget,
    );
    expect(tileMedia(noCover), findsNothing);
    expect(
      inside(wide(noCover), find.byIcon(Icons.play_circle_outline_rounded)),
      findsOneWidget,
    );
    expect(inside(wide(pdf), find.text('8 pages')), findsOneWidget);
    expect(inside(wide(archive), find.text('archive.zip')), findsOneWidget);
    expect(inside(wide(long), find.text(caption)), findsOneWidget);
    expect(find.byKey(ValueKey('card-play-${voice.id}')), findsOneWidget);
    expect(item(0), findsOneWidget);
    expect(item(1), findsOneWidget);
    expect(item(2), findsOneWidget);

    tester.view.physicalSize = const Size(400, 1750);
    await tester.pumpAndSettle();
    final photoCard = wide(photo);
    final photoImage = inside(photoCard, find.byType(Image));
    double imageOffset() =>
        tester.getTopLeft(photoImage).dy - tester.getTopLeft(photoCard).dy;
    await tester.scrollUntilVisible(
      photoCard,
      350,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(photoCard), alignment: 0.5);
    await tester.pumpAndSettle();
    final beforeScroll = imageOffset();
    final scroll = Scrollable.of(
      tester.element(photoCard),
      axis: Axis.vertical,
    ).position;
    final delta = scroll.extentAfter >= 82 ? 82.0 : -82.0;
    scroll.jumpTo(scroll.pixels + delta);
    await tester.pumpAndSettle();
    expect(imageOffset(), isNot(closeTo(beforeScroll, 0.5)));
    scroll.jumpTo(0);
    tester.view.physicalSize = const Size(400, 3800);
    await tester.pumpAndSettle();

    await tester.longPress(wide(long));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show in full'));
    await tester.pumpAndSettle();
    expect(h.preferences.isNoteExpanded(long.id), isTrue);
    expect(words(body), findsOneWidget);
    await h.preferences.setNoteExpanded(long.id, false);
    await tester.pumpAndSettle();

    await tester.tap(item(0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NexNoteGridCard>(wide(checklist))
          .note
          .checklistItems
          .first
          .done,
      isTrue,
    );

    final before = tester.getRect(wide(checklist));
    await tester.tap(find.byKey(ValueKey('note-pick-${checklist.id}')));
    await tester.pumpAndSettle();
    expect(tester.getRect(wide(checklist)), before);
    await tester.tap(item(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<NexNoteGridCard>(wide(checklist))
          .note
          .checklistItems[1]
          .done,
      isFalse,
    );

    await h.preferences.setLocale('fa');
    await h.preferences.setThemeMode(ThemeMode.dark);
    tester.view.physicalSize = const Size(310, 4400);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(wide(checklist))),
      TextDirection.rtl,
    );
    expect(
      Theme.of(tester.element(wide(checklist))).brightness,
      Brightness.dark,
    );
    expect(tileMedia(pdf), findsOneWidget);
    expect(wideHeight(short), lessThan(wideHeight(photo)));
    expect(
      tester.getRect(mark).center.dx,
      greaterThan(tester.getRect(line).center.dx),
    );
    expect(tester.takeException(), isNull);
  });
}
