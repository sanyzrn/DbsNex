import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/tile_previews.dart';
import 'package:nex_client/widgets/parallax_image.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// A video frame and a PDF page are read by the operating system, which takes
/// longer than the frame that builds the tile. The tile is built asking for
/// them; the answer lands later, and the tile that asked has to end up wearing
/// the picture — without anything else on the screen being rebuilt for it.
///
/// Reported symptom: previews, especially videos and PDFs, sometimes stayed
/// blank until a date group was closed and reopened. The request they waited
/// on never finished (see `NexTilePreviews._ask`), so only a card built again
/// read the picture that had been in memory all along.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final picture = Uint8List.fromList(
    img.encodePng(img.Image(width: 12, height: 14)),
  );

  /// Answers a read the way the platform does: later, off the frame that
  /// asked, so the tile has already painted a waiting tile by then.
  List<String> answer({Duration after = const Duration(milliseconds: 120)}) {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call.method);
      await Future<void>.delayed(after);
      return switch (call.method) {
        'videoPreview' || 'pdfPreview' => picture,
        'pdfPage' => {'bytes': picture, 'pageCount': 3},
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return asked;
  }

  test('a frame and a page finish their request and are remembered', () async {
    NexTilePreviews.clear();
    addTearDown(NexTilePreviews.clear);
    final asked = answer(after: const Duration(milliseconds: 20));

    // Bounded: a request that waits on itself never finishes at all.
    final frame = await NexTilePreviews.frame('/clips/trip.mp4')
        .timeout(const Duration(seconds: 2));
    expect(frame, picture);
    expect(NexTilePreviews.knownFrame('/clips/trip.mp4')?.bytes, picture);

    final page = await NexTilePreviews.page('/docs/report.pdf')
        .timeout(const Duration(seconds: 2));
    expect(page?.bytes, picture);
    expect(page?.pages, 3);
    expect(NexTilePreviews.knownPage('/docs/report.pdf')?.page?.pages, 3);
    expect(asked, ['videoPreview', 'pdfPage']);

    // Known now: the same question is answered without asking again.
    expect(await NexTilePreviews.frame('/clips/trip.mp4'), picture);
    expect(await NexTilePreviews.page('/docs/report.pdf'), page);
    expect(asked, ['videoPreview', 'pdfPage']);
  });

  testWidgets('grid tiles wear a frame and a page that arrive after them', (
    tester,
  ) async {
    final h = await NexTestHarness.create(
      preferences: {'appearance.timeline_grid': true},
    );
    addTearDown(h.dispose);
    addTearDown(NexTilePreviews.clear);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1200);
    addTearDown(tester.view.reset);
    final asked = answer();

    final quiet = (await h.services.captureText('a note with no picture'))!;
    final video = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/clip.mp4',
      mediaHash: 'video',
      originalFilename: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    final pdf = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/scan.pdf',
      mediaHash: 'pdf',
      originalFilename: 'scan.pdf',
      mimeType: 'application/pdf',
    );
    await h.services.refreshTimeline();

    await tester.pumpWidget(h.app());
    await tester.pump();

    Finder tile(Note note) => find.byKey(ValueKey('grid-media-${note.id}'));
    Finder inside(Finder parent, Finder child) =>
        find.descendant(of: parent, matching: child);

    // The tiles were built before either picture existed: the first frames
    // asked the platform and painted what they had — no picture yet.
    await tester.pump();
    expect(tile(video), findsOneWidget);
    expect(tile(pdf), findsOneWidget);
    expect(inside(tile(video), find.byType(NexParallaxImage)), findsNothing);
    expect(asked, contains('videoPreview'));

    // The neighbour is a card nobody has touched. A preview landing on the
    // video's tile is one tile's business, not the row's.
    final neighbour = tester.element(find.byKey(ValueKey('grid-${quiet.id}')));
    var neighbourBuilt = 0;
    var counting = true;
    debugOnRebuildDirtyWidget = (element, _) {
      if (counting && identical(element, neighbour)) neighbourBuilt++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    counting = false;

    expect(
      inside(tile(video), find.byType(NexParallaxImage)),
      findsOneWidget,
      reason: 'the frame that arrived after the first build is on its tile',
    );
    expect(
      inside(tile(video), find.byIcon(Icons.play_arrow_rounded)),
      findsOneWidget,
    );
    expect(
      inside(tile(pdf), find.text('3 pages')),
      findsOneWidget,
      reason: 'the page that arrived after the first build is on its tile',
    );
    expect(neighbourBuilt, 0, reason: 'only the tile that asked is rebuilt');
    expect(
      asked.where((method) => method == 'videoPreview'),
      hasLength(1),
      reason: 'the read is shared and never repeated',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a readable list card wears a frame that arrives after it', (
    tester,
  ) async {
    final h = await NexTestHarness.create(
      preferences: {'appearance.timeline_grid': false},
    );
    addTearDown(h.dispose);
    addTearDown(NexTilePreviews.clear);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1200);
    addTearDown(tester.view.reset);
    answer();

    final video = await h.services.captureFile(
      mediaUri: '${h.mediaDir}/clip.mp4',
      mediaHash: 'video',
      originalFilename: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    await h.services.refreshTimeline();
    await h.preferences.setCardDensity(NexCardDensity.readable);

    await tester.pumpWidget(h.app());
    await tester.pump();

    final card = find.byKey(ValueKey('list-wide-${video.id}'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(NexParallaxImage)),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.byType(NexParallaxImage)),
      findsOneWidget,
      reason: 'the frame is on the card that asked for it, not a rebuild later',
    );
    expect(tester.takeException(), isNull);
  });
}
