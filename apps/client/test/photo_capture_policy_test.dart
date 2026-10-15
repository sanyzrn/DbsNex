import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/screens/photo_preview_screen.dart';

import 'support/nex_harness.dart';

void main() {
  for (final source in ImageSource.values) {
    for (final edit in [false, true]) {
      testWidgets('${source.name}: editing before capture is $edit', (
        tester,
      ) async {
        final h = await NexTestHarness.create();
        final original = File('${h.root.path}/picked.png');
        final bytes = img.encodePng(img.Image(width: 12, height: 8));
        original.writeAsBytesSync(bytes);
        const picker = MethodChannel('plugins.flutter.io/image_picker');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
          call,
        ) async {
          if (call.method == 'pickMultiImage') return [original.path];
          if (call.method == 'pickImage') return original.path;
          return null;
        });
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          );
          await h.dispose();
        });
        expect(h.preferences.editPhotoBeforeCapture, isFalse);
        if (edit) await h.preferences.setEditPhotoBeforeCapture(true);
        await tester.pumpWidget(
          NexApp(services: h.services, preferences: h.preferences),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byTooltip(source == ImageSource.camera ? 'Camera' : 'Gallery'),
        );
        if (edit) {
          for (
            var i = 0;
            i < 30 && find.byType(PhotoPreviewScreen).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(find.byType(PhotoPreviewScreen), findsOneWidget);
          expect(await h.services.timeline(), isEmpty);
          await tester.tap(find.text('Use photo'));
          await tester.pumpAndSettle();
        }
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pumpAndSettle();
          if ((await h.services.timeline()).isNotEmpty) break;
        }
        expect(find.byType(PhotoPreviewScreen), findsNothing);
        final notes = await h.services.timeline();
        expect(notes, hasLength(1));
        expect(
          File(notes.single.mediaUri!).readAsBytesSync(),
          bytes,
          reason: 'unedited photos must retain the original bytes',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
