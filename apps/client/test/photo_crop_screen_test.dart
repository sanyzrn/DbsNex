import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:nex_client/l10n/app_localizations.dart';
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
                builder: (_) => PhotoCropScreen(image: image ?? _testPng),
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

/// Waits for a `compute()`-backed operation to finish and settles the tree
/// against it, all inside one `runAsync` zone — the pattern crop_your_image's
/// own tests use. Doing the delay and the settle as two separate top-level
/// awaits (delay in one `runAsync`, `pumpAndSettle` after it returns) works
/// for a single pending isolate, but a chained second one — like the
/// re-parse `_controller.image = ...` kicks off right after rotation's own
/// `compute()` resolves — needs the settle to happen inside the same real
/// zone to actually observe it.
Future<void> _waitAndSettle(WidgetTester tester) async {
  // One plain pump first: a rebuild that remounts `Crop` under a new key (as
  // a rotation does) only actually happens on this next frame, and the
  // isolate call inside its `didChangeDependencies` only starts once that
  // remount does — waiting in real time before this pump would wait for
  // nothing.
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}

void main() {
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

    // The parser and cropper both run through compute(), which spawns a real
    // isolate — it never resolves inside flutter_test's fake-async pump, so
    // both waits need runAsync the way crop_your_image's own tests do.
    await _waitAndSettle(tester);

    await tester.tap(find.byIcon(Icons.check));
    await _waitAndSettle(tester);

    final result = getResult();
    expect(result, isNotNull);
    expect(result, isNot(equals(_testPng)));
  });

  testWidgets('rotating changes what gets cropped, not just a no-op tap', (
    tester,
  ) async {
    final asymmetric = _asymmetricTestPng();

    // Baseline: the same source, cropped without ever touching rotate.
    final baselineResult = await _pushCropScreen(tester, image: asymmetric);
    await _waitAndSettle(tester);
    await tester.tap(find.byIcon(Icons.check));
    await _waitAndSettle(tester);
    final baseline = baselineResult();
    expect(baseline, isNotNull);

    // Same source again, this time rotated once before confirming.
    final rotatedResult = await _pushCropScreen(tester, image: asymmetric);
    await _waitAndSettle(tester);
    await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw_outlined));
    // Two separate real-time windows, not one: the first lets rotation's
    // own `compute()` finish and the remount it triggers happen; only once
    // that remount has actually built does the new `Crop` instance's own
    // `didChangeDependencies` kick off *its* `compute()` re-parse, which
    // needs a real-time window of its own to finish and be observed.
    await _waitAndSettle(tester);
    await _waitAndSettle(tester);
    await tester.tap(find.byIcon(Icons.check));
    await _waitAndSettle(tester);
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
      await _waitAndSettle(tester);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await _waitAndSettle(tester);

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
}
