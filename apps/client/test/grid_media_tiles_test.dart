import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/tile_previews.dart';
import 'package:nex_client/widgets/card_audio.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_client/widgets/parallax_image.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Grid tiles that show their notes rather than describe them (2.8.2): a
/// picture from edge to edge, drifting against the scroll; a recording that
/// plays where it is; a checklist ticked where it is seen; a site by its mark.
void main() {
  Note note(
    String id,
    NoteType type, {
    String? content,
    String? uri,
    String? mime,
    String? filename,
    String? title,
    String? caption,
    String? transcript,
    int attachments = 0,
    int? durationMs,
  }) => Note(
    id: id,
    type: type,
    // A file note's name is its content.
    content: content ?? filename,
    title: title,
    caption: caption,
    transcriptText: transcript,
    mediaUri: uri,
    mimeType: mime,
    attachmentCount: attachments,
    durationMs: durationMs,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceId: 'd',
    rev: 1,
    syncState: SyncState.pending,
  );

  group('which picture a tile wears', () {
    test('photos, collages, videos and PDFs; everything else its words', () {
      expect(
        nexTileBackdropOf(note('a', NoteType.photo, uri: '/a.jpg')),
        NexTileBackdrop.photo,
      );
      expect(
        nexTileBackdropOf(
          note('a', NoteType.photo, uri: '/a.jpg', attachments: 2),
        ),
        NexTileBackdrop.collage,
      );
      expect(
        nexTileBackdropOf(
          note('a', NoteType.photo, uri: '/a.jpg', attachments: 2),
          collages: false,
        ),
        NexTileBackdrop.photo,
        reason: 'without a way to read attachments, the first picture alone',
      );
      expect(
        nexTileBackdropOf(
          note('v', NoteType.file, uri: '/t.mp4', mime: 'video/mp4'),
        ),
        NexTileBackdrop.video,
      );
      expect(
        nexTileBackdropOf(note('p', NoteType.file, uri: '/r.PDF')),
        NexTileBackdrop.pdf,
      );
      expect(
        nexTileBackdropOf(
          note('p', NoteType.file, uri: '/stored.bin', filename: 'scan.PDF'),
        ),
        NexTileBackdrop.pdf,
      );
      expect(
        nexTileBackdropOf(
          note(
            'p',
            NoteType.file,
            uri: '/stored.bin',
            mime: 'Application/PDF; charset=binary',
          ),
        ),
        NexTileBackdrop.pdf,
      );
      expect(
        nexTileBackdropOf(
          note('v', NoteType.file, uri: '/stored.bin', filename: 'clip.mp4'),
        ),
        NexTileBackdrop.video,
      );
      expect(
        nexTileBackdropOf(
          note('i', NoteType.file, uri: '/x.png', mime: 'image/png'),
        ),
        NexTileBackdrop.photo,
      );
      for (final words in [
        note('t', NoteType.text, content: 'hi'),
        note('z', NoteType.file, uri: '/x.zip'),
        note('s', NoteType.voice, uri: '/v.m4a'),
        note('n', NoteType.photo),
      ]) {
        expect(nexTileBackdropOf(words), NexTileBackdrop.none);
      }
    });
  });

  Future<void> host(
    WidgetTester tester,
    List<Widget> tiles, {
    double height = 208,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexSoftLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              for (final tile in tiles)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(width: 190, height: height, child: tile),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  File picture(Directory dir, String name) {
    final im = img.Image(width: 30, height: 60);
    img.fill(im, color: img.ColorRgb8(30, 120, 200));
    return File('${dir.path}/$name')..writeAsBytesSync(img.encodePng(im));
  }

  testWidgets(
    'adaptive rows fit captions, recordings and media in their original order',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('nex_grid_rows_');
      addTearDown(() => dir.deleteSync(recursive: true));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1000);
      addTearDown(tester.view.reset);
      final notes = [
        note(
          'short',
          NoteType.text,
          content: 'Coffee run',
          caption: 'For work',
        ),
        note('voice', NoteType.voice, uri: '/silence.m4a', durationMs: 5000),
        note(
          'named',
          NoteType.text,
          title: 'Heading',
          content: 'Body',
          caption: 'Caption',
        ),
        note('plain', NoteType.text, content: '۱۲۳۴', caption: '📌'),
        note(
          'captioned',
          NoteType.voice,
          uri: '/captioned.m4a',
          caption: 'متن جلسه',
          transcript: 'Hidden transcript',
        ),
        note(
          'transcribed',
          NoteType.voice,
          uri: '/transcribed.m4a',
          transcript: 'Voice text',
        ),
        note('paired', NoteType.text, content: 'Print'),
        note('photo', NoteType.photo, uri: picture(dir, 'photo.png').path),
        note('last', NoteType.text, content: 'آخرین کارت'),
      ];
      const strings = NexCardStrings.fallback;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          theme: nexSoftLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final metrics = NexGridMetrics.of(context);
                return CustomScrollView(
                  controller: scroll,
                  slivers: [
                    SliverGrid.builder(
                      gridDelegate: NexGridColumnsDelegate(
                        metrics: metrics,
                        mainAxisExtent: metrics.heightFor(context),
                        rows: NexGridRows(
                          notes,
                          NexGridRowSizing.of(context, strings),
                        ),
                      ),
                      itemCount: notes.length,
                      itemBuilder: (context, index) => NexNoteGridCard(
                        key: ValueKey(notes[index].id),
                        note: notes[index],
                        strings: strings,
                        onTap: () {},
                        onLeadingTap: () {},
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      Rect bounds(String id) => tester.getRect(find.byKey(ValueKey(id)));
      final short = bounds('short');
      final medium = bounds('named');
      final tall = bounds('paired');
      expect(short.height, lessThan(medium.height));
      expect(medium.height, lessThan(tall.height));
      expect(short.height, bounds('voice').height);
      expect(bounds('voice').top, short.top);
      expect(short.left, greaterThan(bounds('voice').left));
      expect(bounds('plain').height, medium.height);
      expect(bounds('captioned').height, medium.height);
      expect(bounds('transcribed').height, medium.height);
      expect(bounds('photo').height, tall.height);
      expect(bounds('last').height, short.height);
      expect(find.text('For work'), findsOneWidget);
      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('۱۲۳۴'), findsOneWidget);
      expect(find.text('📌'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Caption'), findsOneWidget);
      expect(find.text('متن جلسه'), findsOneWidget);
      expect(find.text('Voice text'), findsOneWidget);
      expect(find.text('Hidden transcript'), findsNothing);
      final play = find.byKey(const ValueKey('card-play-voice'));
      expect(tester.getSize(play).height, 44);
      expect(bounds('voice').contains(tester.getCenter(play)), isTrue);

      // Moving to the end uses the real row heights, including a partial row.
      final bottom = bounds('last').bottom;
      tester.view.physicalSize = const Size(400, 450);
      await tester.pump();
      expect(scroll.position.maxScrollExtent, closeTo(bottom - 450, 0.1));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(bounds('last').bottom, closeTo(450, 0.1));

      // The same sentence and caption wrap on a narrow screen and need more
      // room. A character count alone would leave them in the short row.
      scroll.jumpTo(0);
      tester.view.physicalSize = const Size(280, 1000);
      await tester.pump();
      expect(bounds('short').height, greaterThan(short.height));
      expect(find.text('For work'), findsOneWidget);
    },
  );

  testWidgets('a photo fills its tile and drifts by painting, rebuilding '
      'nothing as the list scrolls', (tester) async {
    final dir = Directory.systemTemp.createTempSync('grid_media_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tiles = [
      for (var i = 0; i < 12; i++)
        NexNoteGridCard(
          note: note('p$i', NoteType.photo, uri: picture(dir, 'p$i.png').path),
          strings: NexCardStrings.fallback,
          onTap: () {},
        ),
    ];
    await host(tester, tiles);
    expect(find.byType(NexParallaxImage), findsWidgets);
    expect(find.byType(Flow), findsWidgets);

    final built = <Element>{};
    var counting = false;
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (!built.add(element) && counting) rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await tester.pump();
    counting = true;
    final gesture = await tester.startGesture(const Offset(200, 400));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilds, 0);
  });

  testWidgets('a collage reads its other pictures, and counts what it cannot '
      'show', (tester) async {
    final dir = Directory.systemTemp.createTempSync('grid_collage_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final asked = <String>[];
    final more = [for (var i = 0; i < 4; i++) picture(dir, 'm$i.png').path];
    await host(tester, [
      NexNoteGridCard(
        note: note(
          'c',
          NoteType.photo,
          uri: picture(dir, 'c.png').path,
          attachments: 4,
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
        photos: (n) async {
          asked.add(n.id);
          return more;
        },
      ),
    ]);
    await tester.pump();
    expect(asked, ['c']);
    // Three shown, the first big; two more than shown are counted.
    expect(find.text('+2'), findsOneWidget);
    final widths = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as ResizeImage).width!)
        .toList();
    expect(widths, hasLength(3));
    expect(widths.first, closeTo(widths[1] * 1.5, 1));
    expect(widths[1], widths[2]);
  });

  testWidgets('rebuilding a collage tile does not read its attachments '
      'again', (tester) async {
    final dir = Directory.systemTemp.createTempSync('grid_collage_once_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final more = [for (var i = 0; i < 3; i++) picture(dir, 'm$i.png').path];
    final answer = Completer<List<String>>();
    var reads = 0;

    Widget tile() => NexNoteGridCard(
      note: note(
        'collage-once',
        NoteType.photo,
        uri: picture(dir, 'c.png').path,
        attachments: 3,
      ),
      strings: NexCardStrings.fallback,
      onTap: () {},
      photos: (_) {
        reads++;
        return answer.future;
      },
    );

    await host(tester, [tile()]);
    expect(reads, 1, reason: 'the first build asks once');

    // A rebuild while the read is still out — a pick, a size change, a row
    // arriving above it. Asking the same note's attachments again starts a
    // second read of the same pictures and resets what the tile shows.
    await host(tester, [tile()]);
    await tester.pump();
    expect(reads, 1, reason: 'a rebuild reuses the read that is out');

    answer.complete(more);
    await tester.pumpAndSettle();
    // One photo and three more: three are shown, the fourth is counted.
    expect(find.text('+1'), findsOneWidget);

    // And once the answer is in, a rebuild reads what is already known.
    await host(tester, [tile()]);
    await tester.pumpAndSettle();
    expect(reads, 1, reason: 'a rebuild reads the pictures already read');
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a video with no frame to be had keeps its words', (
    tester,
  ) async {
    NexTilePreviews.clear();
    // What the platform answers for a file it cannot read a frame from.
    NexTilePreviews.debugRemember('/nowhere/clip.mp4', none: true);
    await host(tester, [
      NexNoteGridCard(
        note: note(
          'v',
          NoteType.file,
          uri: '/nowhere/clip.mp4',
          mime: 'video/mp4',
          filename: 'clip.mp4',
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grid-media-caption')), findsNothing);
    expect(find.text('clip.mp4'), findsWidgets);
  });

  testWidgets('a video with a frame wears it, with Play over it', (
    tester,
  ) async {
    NexTilePreviews.clear();
    NexTilePreviews.debugRemember(
      '/clips/trip.mp4',
      frame: Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8))),
    );
    await host(tester, [
      NexNoteGridCard(
        note: note(
          'v',
          NoteType.file,
          uri: '/clips/trip.mp4',
          mime: 'video/mp4',
          filename: 'trip.mp4',
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-media-caption')), findsOneWidget);
  });

  testWidgets('a checklist is ticked from its tile, by the item\'s own place', (
    tester,
  ) async {
    final ticked = <int>[];
    await host(tester, [
      NexNoteGridCard(
        note: note(
          'l',
          NoteType.checklist,
          content: formatChecklist(const [
            ChecklistItem(text: 'Milk', done: true),
            ChecklistItem(text: 'Bread', done: false),
            ChecklistItem(text: 'Eggs', done: false),
          ]),
        ),
        strings: NexCardStrings.fallback,
        onTap: () => fail('the row ticks; it does not open the note'),
        onToggleItem: ticked.add,
      ),
    ]);
    expect(find.byKey(const ValueKey('grid-checklist-ring')), findsOneWidget);
    // Undone first on the tile — Bread and Eggs lead, Milk is below them —
    // but each is told by its own place in the list.
    await tester.tap(find.text('Eggs'));
    await tester.tap(find.text('Bread'));
    expect(ticked, [2, 1]);
  });

  testWidgets('a recording plays from its tile', (tester) async {
    await host(tester, [
      NexNoteGridCard(
        note: note(
          's',
          NoteType.voice,
          uri: '/nowhere/v.m4a',
          durationMs: 63000,
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.byType(NexCardVoice), findsOneWidget);
    expect(find.byKey(const ValueKey('card-play-s')), findsOneWidget);
    expect(find.text('1:03'), findsOneWidget);
  });

  testWidgets('a link is its site\'s mark and name, not its address twice', (
    tester,
  ) async {
    await host(tester, [
      NexNoteGridCard(
        note: note(
          'k',
          NoteType.link,
          content: 'https://www.wikipedia.org/wiki/Isfahan',
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.text('W'), findsOneWidget);
    // Its name, what it is and its title, read from the address (2.8.3).
    expect(find.text('Wikipedia'), findsOneWidget);
    expect(find.text('Article'), findsOneWidget);
    expect(find.text('Isfahan'), findsOneWidget);
    expect(find.text('wikipedia.org'), findsNothing);
  });

  testWidgets('a tile with a reminder keeps its tags\' dots beside it '
      '(2.8.4)', (tester) async {
    final tagged = Note(
      id: 'r',
      type: NoteType.text,
      content: 'Call the plumber',
      dueAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
      tags: [
        Tag(id: 't', name: 'home', color: '#E53935', createdAt: DateTime(2026)),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deviceId: 'd',
      rev: 1,
      syncState: SyncState.pending,
    );
    for (final height in [208.0, 160.0]) {
      await host(tester, [
        NexNoteGridCard(
          note: tagged,
          strings: NexCardStrings.fallback,
          onTap: () {},
        ),
      ], height: height);
      expect(find.byKey(const ValueKey('grid-reminder')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration! as BoxDecoration).color == const Color(0xFFE53935),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('the list card plays a recording, and only a recording', () {
    final voice = note('s', NoteType.voice, uri: '/v.m4a', durationMs: 1000);
    // Every size has two preview rows at least: room for the player.
    expect(NexCardVoicePreview.fits(voice, NexCardDensity.compact), isTrue);
    expect(NexCardVoicePreview.fits(voice, NexCardDensity.standard), isTrue);
    expect(NexCardVoicePreview.fits(voice, NexCardDensity.readable), isTrue);
    expect(
      NexCardVoicePreview.fits(
        note('t', NoteType.text, content: 'x'),
        NexCardDensity.standard,
      ),
      isFalse,
    );
  });
}
