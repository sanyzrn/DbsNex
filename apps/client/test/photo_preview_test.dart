import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/photo_crop_screen.dart';
import 'package:nex_client/screens/photo_preview_screen.dart';
import 'package:nex_client/widgets/photo_action_bar.dart';

Uint8List _testPng() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(20, 90, 200));
  return Uint8List.fromList(img.encodePng(image));
}

/// Capture used to open the cropper on every photo — an edit in the path of a
/// note that mostly did not need one. The preview is the screen that turns the
/// crop back into a choice.
void main() {
  late Uint8List photo;

  setUp(() => photo = _testPng());

  Future<Uint8List? Function()> pushPreview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Uint8List? result;
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => PhotoPreviewScreen(image: photo),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () {
      expect(popped, isTrue, reason: 'the preview never returned');
      return result;
    };
  }

  testWidgets('saving keeps the photo exactly as it arrived', (tester) async {
    final result = await pushPreview(tester);

    // No cropper on the way in. That is the whole point of the screen.
    expect(find.byType(PhotoCropScreen), findsNothing);
    expect(find.byType(Image), findsWidgets);

    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();

    // Byte-for-byte: a photo that was not edited must not be re-encoded on the
    // way past, which would cost quality for nothing.
    expect(result(), equals(photo));
  });

  testWidgets('the decisions are full-width buttons at the bottom', (
    tester,
  ) async {
    await pushPreview(tester);

    // The controls used to be small icons in the app bar — the far corner of
    // a phone from the hand holding it.
    final bar = find.byType(NexPhotoActionBar);
    expect(bar, findsOneWidget);
    final barBox = tester.getRect(bar);
    expect(barBox.bottom, closeTo(1600, 1));

    for (final label in ['Edit', 'Use photo']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(button, findsOneWidget, reason: '$label is not a button');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('editing goes to the cropper, and backing out of it stays here', (
    tester,
  ) async {
    final result = await pushPreview(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoCropScreen), findsOneWidget);

    // Backing out of the editor is not backing out of the capture: the photo
    // is still there, unedited, waiting for the same two buttons.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoCropScreen), findsNothing);
    expect(find.text('Use photo'), findsOneWidget);

    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();
    expect(result(), equals(photo));
  });

  testWidgets('closing the preview discards the capture', (tester) async {
    final result = await pushPreview(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });
}
