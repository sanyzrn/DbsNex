import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/tile_previews.dart';
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
    tester.view.physicalSize = const Size(400, 1700);
    addTearDown(tester.view.reset);

    const body = 'First line\nSecond line\nThird line\nFourth line\nLast line';
    const caption = 'Keep this title small';
    const voiceCaption = 'Recording from the review';
    const transcript = 'Two cover options by Thursday';
    final short = (await h.services.captureText('Coffee'))!;
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
    await h.services.refreshTimeline();

    await h.preferences.setCardDensity(NexCardDensity.compact);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();

    Finder card(Note note) => find.byWidgetPredicate(
      (widget) => widget is NoteCard && widget.note.id == note.id,
    );
    double height(Note note) => tester.getSize(card(note)).height;
    Finder item(int index) =>
        find.byKey(ValueKey('list-checklist-${checklist.id}-$index'));
    Finder words(String text) => find.byWidgetPredicate(
      (widget) => widget is NexTextSurface && widget.text == text,
    );

    expect(height(short), height(long));
    expect(find.byKey(const ValueKey('list-photo-preview')), findsNothing);

    await h.preferences.setCardDensity(NexCardDensity.standard);
    await tester.pumpAndSettle();
    expect(tester.widget<NexTextSurface>(words(body)).maxLines, 2);
    expect(words(caption), findsOneWidget);
    expect(find.byKey(const ValueKey('list-pdf-preview')), findsNothing);
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
    expect(tester.widget<NexTextSurface>(words(body)).maxLines, 4);
    expect(height(short), lessThan(height(long)));
    expect(height(photo), greaterThan(height(short)));
    expect(height(pdf), greaterThan(height(short)));
    expect(find.byKey(const ValueKey('list-photo-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('list-pdf-preview')), findsOneWidget);
    expect(find.text('8 pages'), findsOneWidget);
    expect(words(voiceCaption), findsOneWidget);
    expect(words(transcript), findsOneWidget);
    expect(find.byKey(ValueKey('card-play-${voice.id}')), findsOneWidget);
    expect(item(0), findsOneWidget);
    expect(item(1), findsOneWidget);
    expect(item(2), findsNothing);
    expect(
      tester.getSize(item(0)).height,
      greaterThanOrEqualTo(nexMinTapTarget),
    );

    await tester.tap(item(0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoteCard>(card(checklist)).note.checklistItems.first.done,
      isTrue,
    );

    final before = tester.getRect(card(checklist));
    await tester.tap(find.byKey(ValueKey('note-pick-${checklist.id}')));
    await tester.pumpAndSettle();
    expect(tester.getRect(card(checklist)), before);
    await tester.tap(item(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoteCard>(card(checklist)).note.checklistItems[1].done,
      isFalse,
    );

    await h.preferences.setLocale('fa');
    await h.preferences.setThemeMode(ThemeMode.dark);
    tester.view.physicalSize = const Size(310, 1700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(card(checklist))),
      TextDirection.rtl,
    );
    expect(
      Theme.of(tester.element(card(checklist))).brightness,
      Brightness.dark,
    );
    expect(find.byKey(const ValueKey('list-pdf-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
