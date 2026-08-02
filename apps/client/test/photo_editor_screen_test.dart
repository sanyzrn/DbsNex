import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/photo_editor_screen.dart';

/// A real, decodable 4x2 PNG, built with the same codec the editor uses.
/// crop_your_image parses the image bytes for real (including scaling against
/// the viewport), so placeholder bytes like `[1, 2, 3]` throw inside the
/// parser's isolate before the widget ever reaches a testable state. A 4:2
/// shape also makes rotation and aspect assertions meaningful: rotated it is
/// 2x4, cropped 1:1 it is 2x2.
final _testPng = Uint8List.fromList(_buildTestPng());

Uint8List _buildTestPng() {
  final image = img.Image(width: 4, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 40 * (x + y), 90, 200, 255);
    }
  }
  return img.encodePng(image);
}

/// Pushes [PhotoEditorScreen] behind a button so the test can capture
/// whatever value the route is popped with, the same way
/// [TimelineScreenState.capturePhoto] awaits it.
Future<Uint8List? Function()> _pushEditor(WidgetTester tester) async {
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
                builder: (_) => PhotoEditorScreen(image: _testPng),
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
  // Route transition only — never pumpAndSettle here: the editor's busy
  // spinner animates forever until the normalize compute (a real isolate)
  // resolves, which only happens inside runAsync.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return () {
    expect(resultSet, isTrue, reason: 'the pushed route never popped');
    return result;
  };
}

/// The editor normalizes its image (and the Crop view parses it) through
/// `compute()`, which spawns a real isolate — it never resolves inside
/// flutter_test's fake-async pump, so every wait needs runAsync the way
/// crop_your_image's own tests do.
Future<void> _runAsync(WidgetTester tester,
    [Duration duration = const Duration(milliseconds: 400)]) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
}

/// Waits until the confirm button is enabled — i.e. the editor finished
/// normalizing and the Crop view finished parsing.
Future<void> _waitReady(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await _runAsync(tester, const Duration(milliseconds: 100));
    final button = tester.widget<IconButton>(find.byTooltip('Use photo'));
    if (button.onPressed != null) return;
  }
  fail('the editor never became ready');
}

/// Waits until a transform finished: the busy overlay is gone and the crop
/// view has re-parsed the new bytes.
Future<void> _waitIdle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await _runAsync(tester, const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      continue;
    }
    final button = tester.widget<IconButton>(find.byTooltip('Use photo'));
    if (button.onPressed != null) return;
  }
  fail('the editor never finished its transform');
}

void main() {
  testWidgets('discarding the photo pops null, not the original bytes', (
    tester,
  ) async {
    final getResult = await _pushEditor(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(getResult(), isNull);
  });

  testWidgets('confirming without edits pops the normalized photo', (
    tester,
  ) async {
    final getResult = await _pushEditor(tester);
    await _waitReady(tester);

    await tester.tap(find.byIcon(Icons.check));
    await _runAsync(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final result = getResult();
    expect(result, isNotNull);
    final decoded = img.decodeImage(result!)!;
    expect(decoded.width, 4, reason: 'no edits must not change the photo');
    expect(decoded.height, 2);
  });

  testWidgets('rotating 90° swaps the photo dimensions on confirm', (
    tester,
  ) async {
    final getResult = await _pushEditor(tester);
    await _waitReady(tester);

    await tester.tap(find.byIcon(Icons.rotate_right));
    await _waitIdle(tester);

    await tester.tap(find.byIcon(Icons.check));
    await _runAsync(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final decoded = img.decodeImage(getResult()!)!;
    expect(decoded.width, 2);
    expect(decoded.height, 4);
  });

  testWidgets('a 1:1 aspect preset crops to a square', (tester) async {
    final getResult = await _pushEditor(tester);
    await _waitReady(tester);

    await tester.tap(find.byIcon(Icons.aspect_ratio));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await _runAsync(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final decoded = img.decodeImage(getResult()!)!;
    expect(decoded.width, decoded.height, reason: '1:1 crop must be square');
  });

  testWidgets('reset restores the photo after an edit', (tester) async {
    final getResult = await _pushEditor(tester);
    await _waitReady(tester);

    // Reset is disabled until something changed.
    final resetBefore = tester.widget<InkWell>(
      find.ancestor(of: find.text('Reset'), matching: find.byType(InkWell)),
    );
    expect(resetBefore.onTap, isNull);

    await tester.tap(find.byIcon(Icons.rotate_left));
    await _waitIdle(tester);

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await _runAsync(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final decoded = img.decodeImage(getResult()!)!;
    expect(decoded.width, 4);
    expect(decoded.height, 2);
  });
}
