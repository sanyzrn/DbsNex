import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/editor_drafts.dart';
import 'package:nex_client/screens/photo_annotate_screen.dart';
import 'package:nex_client/screens/photo_crop_screen.dart';

/// A real, decodable 100x100 solid-color PNG. crop_your_image parses the
/// image bytes for real (including scaling against the viewport), so
/// placeholder bytes like `[1, 2, 3]` throw inside the parser's isolate
/// before the widget ever reaches a testable state.
final _testPng = Uint8List.fromList(
  base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAAAoUlEQVR42u3QMQ0AAAgDsGmafwHI'
    'wgIfT5MqaKblKApkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIgS5YsWbJk'
    'KZAlS5YsWbIUyJIlS5YsWQpkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIg'
    'S5YsWbJkKZAlS5YsWbIUyJIlS5YsWQpkyfq2ZknJZEUYbWQAAAAASUVORK5CYII=',
  ),
);

/// A non-square PNG with one corner painted a distinct colour, built fresh
/// rather than reusing [_testPng] — that fixture is a solid, uniform colour,
/// so a 90° turn of it leaves every pixel exactly as it was and could never
/// tell an applied rotation apart from a silent no-op.
/// A picture that cannot be rotated without the difference showing.
///
/// It was one red pixel in a corner, which made the rotation test depend on
/// whether the crop rectangle happened to include that corner — and it stopped
/// including it the moment the screen's chrome changed shape. Half the frame
/// filled instead: every crop of this that is not empty differs from the same
/// crop of its rotation.
Uint8List _asymmetricTestPng() {
  final image = img.Image(width: 12, height: 8);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 6; x++) {
      image.setPixelRgb(x, y, 255, 0, 0);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Pushes [PhotoCropScreen] behind a button so the test can capture whatever
/// value the route is popped with, the same way [TimelineScreenState.capturePhoto]
/// awaits it.
Future<Uint8List? Function()> _pushCropScreen(
  WidgetTester tester, {
  Uint8List? image,
  EditorDrafts? drafts,
}) async {
  // Pinned rather than left at the default. What `Crop` selects depends on
  // the shape of the box it is given, and that box is the screen minus the
  // app bar and the action bar — so a change to the chrome silently changed
  // which pixels the rotation test was comparing. Fixing the surface makes
  // the geometry the test's own, instead of the layout's.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Uint8List? result;
  var resultSet = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute(
                builder: (_) =>
                    PhotoCropScreen(image: image ?? _testPng, drafts: drafts),
              ),
            );
            resultSet = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () {
    expect(resultSet, isTrue, reason: 'the pushed route never popped');
    return result;
  };
}

/// The native codec, the raster thread and Crop's isolate complete outside
/// fake time. Pump frames until the editor exposes the next action.
Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    final timeout = Stopwatch()..start();
    while (!ready() && timeout.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  });
  expect(ready(), isTrue, reason: 'the photo editor did not finish its work');
  await tester.pumpAndSettle();
}

Future<void> _waitForCrop(WidgetTester tester) => _waitFor(tester, () {
  final save = find.ancestor(
    of: find.byIcon(Icons.check),
    matching: find.byType(FilledButton),
  );
  return save.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(save).onPressed != null;
});

Future<void> _waitForResult(WidgetTester tester) => _waitFor(
  tester,
  () => find.byType(PhotoCropScreen, skipOffstage: false).evaluate().isEmpty,
);

void main() {
  for (final edge in EdgeAlignment.values) {
    testWidgets('${edge.name} crop handle has a real enlarged drag target', (
      tester,
    ) async {
      await _pushCropScreen(tester);
      await _waitForCrop(tester);
      final dot = find.byKey(ValueKey('crop-dot-${edge.name}'));
      final target = find.byKey(ValueKey('crop-target-${edge.name}'));
      final before = tester.getCenter(dot);
      final box = tester.getRect(target);
      expect(box.size, const Size(48, 48));
      expect(
        before,
        box.topLeft + const Offset(24, 24),
        reason: 'the visible handle keeps its original anchor',
      );
      final opposite = EdgeAlignment.values[3 - edge.index];
      final other = find.byKey(ValueKey('crop-dot-${opposite.name}'));
      final fixed = tester.getCenter(other);
      // Inside the viewport, beyond the visible dot and original 32dp slot.
      final left =
          edge == EdgeAlignment.topLeft || edge == EdgeAlignment.bottomLeft;
      final start = before + Offset(left ? 22 : -22, 0);
      final dx =
          edge == EdgeAlignment.topLeft || edge == EdgeAlignment.bottomLeft
          ? 50.0
          : -50.0;
      final dy = edge == EdgeAlignment.topLeft || edge == EdgeAlignment.topRight
          ? 40.0
          : -40.0;
      await tester.dragFrom(start, Offset(dx, dy));
      await tester.pumpAndSettle();
      expect((tester.getCenter(dot) - before).distance, greaterThan(20));
      expect(
        tester.getCenter(other),
        fixed,
        reason: 'resize the chosen corner, without panning the photo',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('discarding the photo pops null, not the original bytes', (
    tester,
  ) async {
    final getResult = await _pushCropScreen(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(getResult(), isNull);
  });

  testWidgets('confirming the crop pops the cropped bytes', (tester) async {
    final getResult = await _pushCropScreen(tester);

    await _waitForCrop(tester);

    await tester.tap(find.byIcon(Icons.check));
    await _waitForResult(tester);

    final result = getResult();
    expect(result, isNotNull);
    expect(result, isNot(equals(_testPng)));
  });

  testWidgets('a JPEG crop stays a JPEG', (tester) async {
    // It was turned into a PNG here — seconds of work on a camera photo and
    // a file several times the size — for the save step to turn back.
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 100, height: 100)),
    );
    final getResult = await _pushCropScreen(tester, image: jpeg);
    await _waitForCrop(tester);
    await tester.tap(find.byIcon(Icons.check));
    await _waitForResult(tester);

    final result = getResult();
    expect(result, isNotNull);
    expect(result!.sublist(0, 2), [0xff, 0xd8]);
  });

  testWidgets('drawing on a JPEG exports the mark directly as JPEG', (
    tester,
  ) async {
    final jpeg = img.encodeJpg(img.Image(width: 640, height: 640));
    final result = await _pushCropScreen(tester, image: jpeg);
    await _waitForCrop(tester);
    await tester.tap(find.byIcon(Icons.draw_outlined));
    final canvas = find.byKey(const ValueKey('annotate-canvas'));
    final done = find.widgetWithText(FilledButton, 'Done');
    await _waitFor(
      tester,
      () =>
          done.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(done).onPressed != null,
    );
    final center = tester.getCenter(canvas);
    await tester.dragFrom(center - const Offset(50, 0), const Offset(100, 0));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed,
      isNotNull,
    );
    await tester.tap(done);
    await _waitForResult(tester);

    final edited = img.decodeJpg(result()!)!;
    final y = edited.height ~/ 2;
    final centerStrip = [
      for (var row = y - 3; row <= y + 3; row++)
        for (var x = 0; x < edited.width; x++) edited.getPixel(x, row).r,
    ];
    expect(centerStrip, anyElement(greaterThan(96)));
    expect(edited.getPixel(2, 2).r, lessThan(20));
  });

  testWidgets(
    'editing a legacy annotation preserves its crop on another recovery',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'nex_legacy_photo_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final drafts = EditorDrafts(directory.path);
      final jpeg = img.encodeJpg(img.Image(width: 320, height: 240));
      const annotationKey = 'photo-new-annotation';
      drafts.write(annotationKey, {
        'image': 'legacy-draft',
        'marks': <Object>[],
      });

      Future<void> openAnnotation() async {
        await _pushCropScreen(tester, image: jpeg, drafts: drafts);
        await _waitForCrop(tester);
        await tester.tap(find.byIcon(Icons.draw_outlined));
        final done = find.widgetWithText(FilledButton, 'Done');
        await _waitFor(
          tester,
          () =>
              done.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(done).onPressed != null,
        );
      }

      await openAnnotation();
      final first = tester.widget<PhotoAnnotateScreen>(
        find.byType(PhotoAnnotateScreen),
      );
      await tester.tap(find.byKey(const ValueKey('annotate-canvas')));
      await tester.pump();
      drafts.flushPending();
      expect(drafts.read(annotationKey)?['legacyCrop'], isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await openAnnotation();
      final restored = tester.widget<PhotoAnnotateScreen>(
        find.byType(PhotoAnnotateScreen),
      );
      expect(restored.image, orderedEquals(first.image));
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('rotating changes what gets cropped, not just a no-op tap', (
    tester,
  ) async {
    final asymmetric = _asymmetricTestPng();

    // Baseline: the same source, cropped without ever touching rotate.
    final baselineResult = await _pushCropScreen(tester, image: asymmetric);
    await _waitForCrop(tester);
    await tester.tap(find.byIcon(Icons.check));
    await _waitForResult(tester);
    final baseline = baselineResult();
    expect(baseline, isNotNull);

    // Same source again, this time rotated once before confirming.
    final rotatedResult = await _pushCropScreen(tester, image: asymmetric);
    await _waitForCrop(tester);
    await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw_outlined));
    await tester.pump();
    await _waitForCrop(tester);
    await tester.tap(find.byIcon(Icons.check));
    await _waitForResult(tester);
    final rotated = rotatedResult();
    expect(rotated, isNotNull);

    // Comparing against the un-rotated crop of the exact same source,
    // rather than asserting an exact width/height, sidesteps crop_your_image's
    // own default inset — which is its detail to own, not this feature's.
    expect(rotated, isNot(equals(baseline)));
  });

  testWidgets(
    'the annotate detour is optional — no marks means the plain crop comes back',
    (tester) async {
      final getResult = await _pushCropScreen(tester);

      // The crop widget's own initial parse is async — the pencil action is
      // disabled until it finishes.
      await _waitForCrop(tester);

      await tester.tap(find.byIcon(Icons.draw_outlined));
      await _waitFor(
        tester,
        () => find.byType(PhotoAnnotateScreen).evaluate().isNotEmpty,
      );

      // Now on the annotate screen, having added nothing: Done pops it with
      // null, and the crop screen falls back to the crop it already made.
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final result = getResult();
      expect(result, isNotNull);
      expect(result, isNot(equals(_testPng)));
    },
  );

  testWidgets('leaving without touching anything is not an unsaved change', (
    tester,
  ) async {
    final getResult = await _pushCropScreen(tester);
    // Fully loaded and ready — the state that used to count "ready" as an
    // edit and ask "discard changes?" of somebody who had only waited.
    await _waitForCrop(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // No discard question: nothing was changed, nothing is pending.
    expect(find.text('Discard'), findsNothing);
    expect(getResult(), isNull);
  });
}
