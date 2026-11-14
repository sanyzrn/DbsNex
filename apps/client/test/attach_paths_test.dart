import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/sharing.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/recurring_attachments.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// The share path's photo strip (SEC-08) answers `compute`-style now: null
/// when the photo carries nothing to strip, so the original file is shared
/// as it is with no staged copy at all. And a recording written straight
/// into the media folder — the spool's own answer — attaches under its
/// duration, with no second copy of its bytes anywhere.
void main() {
  /// An APP1 EXIF segment with an orientation entry and a GPS pointer, the
  /// bytes "GPSDATA" standing in for the coordinates — the same shape the
  /// photo-metadata tests build.
  List<int> exif(int orientation) {
    final tiff = ByteData(38)
      ..setUint8(0, 0x49)
      ..setUint8(1, 0x49)
      ..setUint16(2, 42, Endian.little)
      ..setUint32(4, 8, Endian.little)
      ..setUint16(8, 2, Endian.little)
      ..setUint16(10, 0x0112, Endian.little)
      ..setUint16(12, 3, Endian.little)
      ..setUint32(14, 1, Endian.little)
      ..setUint16(18, orientation, Endian.little)
      ..setUint16(22, 0x8825, Endian.little)
      ..setUint16(24, 4, Endian.little)
      ..setUint32(26, 1, Endian.little)
      ..setUint32(30, 0, Endian.little)
      ..setUint32(34, 0, Endian.little);
    final payload = [
      ...'Exif'.codeUnits, 0, 0, //
      ...tiff.buffer.asUint8List(),
      ...'GPSDATA'.codeUnits,
    ];
    final length = payload.length + 2;
    return [0xFF, 0xE1, length >> 8, length & 0xFF, ...payload];
  }

  const jfif = [0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46];
  const quant = [0xFF, 0xDB, 0x00, 0x04, 0x01, 0x02];
  const scan = [0xFF, 0xDA, 0x00, 0x04, 0x00, 0x00, 0x11, 0x22, 0xFF, 0xD9];

  group('nexStrippedPhotoForShare', () {
    test('a photo with nothing to strip answers null, not a copy', () {
      final photo = Uint8List.fromList([
        0xFF, 0xD8, ...jfif, ...quant, ...scan, //
      ]);
      expect(nexStrippedPhotoForShare(photo), isNull);
    });

    test('a photo carrying where it was taken answers bytes without it', () {
      final photo = Uint8List.fromList([
        0xFF, 0xD8, ...jfif, ...exif(6), ...quant, ...scan, //
      ]);
      final clean = nexStrippedPhotoForShare(photo);
      expect(clean, isNotNull);
      expect(String.fromCharCodes(clean!), isNot(contains('GPSDATA')));
      // The image data stays byte for byte.
      expect(clean.sublist(clean.length - scan.length), scan);
    });

    test('anything that is not a JPEG answers null, and goes out as it is', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      expect(nexStrippedPhotoForShare(png), isNull);
    });
  });

  group('attachStored', () {
    late NexTestHarness harness;
    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_attach_paths_');
    });
    tearDown(() => harness.dispose());

    test(
      'a spooled recording attaches with its duration and no copy',
      () async {
        final services = harness.services;
        final note = (await services.captureText('the meeting'))!;
        // What NexVoiceSpool leaves behind on Keep: a file already inside
        // the media folder, the spool's own write.
        final spooled = File(
          '${services.mediaDir}${Platform.pathSeparator}'
          'voice-1999999999999.m4a',
        )..writeAsBytesSync(List.filled(64, 3));

        final attached = await services.attachStored(
          note.id,
          mediaUri: spooled.path,
          mediaHash: sha256OfBytes(spooled.readAsBytesSync()),
          kind: AttachmentKind.voice,
          mimeType: 'audio/mp4',
          durationMs: 65000,
        );

        expect(attached, isNotNull);
        final saved = (await services.attachmentsFor(note.id)).single;
        expect(saved.kind, AttachmentKind.voice);
        expect(saved.durationMs, 65000);
        expect(saved.mediaUri, spooled.path);
        expect(saved.mediaHash, attached!.mediaHash);
        // The file the spool wrote is the file the note keeps: no second
        // copy of the recording exists anywhere.
        expect(spooled.existsSync(), isTrue);
        final mediaFiles = Directory(services.mediaDir)
            .listSync()
            .whereType<File>()
            .map((file) => file.path)
            .toList();
        expect(
          mediaFiles.where((path) => path != spooled.path),
          isEmpty,
          reason: 'a spooled clip must not be copied to attach',
        );
      },
    );

    test('a stored file still attaches without a duration', () async {
      final services = harness.services;
      final note = (await services.captureText('reference'))!;
      final stored = File(
        '${services.mediaDir}${Platform.pathSeparator}media-x.pdf',
      )..writeAsBytesSync(List.filled(16, 9));

      final attached = await services.attachStored(
        note.id,
        mediaUri: stored.path,
        mediaHash: sha256OfBytes(stored.readAsBytesSync()),
        kind: AttachmentKind.file,
        name: 'x.pdf',
        mimeType: 'application/pdf',
      );

      expect(attached, isNotNull);
      final saved = (await services.attachmentsFor(note.id)).single;
      expect(saved.name, 'x.pdf');
      expect(saved.durationMs, isNull);
    });
  });

  group('picking several photos onto a note', () {
    late NexTestHarness harness;
    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_attach_pick_');
    });
    tearDown(() => harness.dispose());

    testWidgets('each lands from its file, and nothing is read into the heap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = harness.services;
      late Note note;
      final sources = <File>[];
      await tester.runAsync(() async {
        note = (await services.captureText('the set'))!;
        for (var i = 0; i < 3; i++) {
          final source = File(
            '${harness.root.path}${Platform.pathSeparator}picked-$i.png',
          )..writeAsBytesSync(List.filled(64 + i, i + 1));
          sources.add(source);
        }
      });
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        if (call.method == 'pickMultiImage') {
          return [for (final source in sources) source.path];
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: services,
              noteId: note.id,
              preferences: harness.preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attach-photos')));
      await tester.pumpAndSettle();

      List<NoteAttachment> saved = const [];
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(() async {
          saved = await services.attachmentsFor(note.id);
        });
        await tester.pumpAndSettle();
        if (saved.length == sources.length) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }

      expect(saved, hasLength(sources.length));
      // File-to-file: every landed copy is byte-identical to its source.
      for (var i = 0; i < sources.length; i++) {
        expect(
          File(saved[i].mediaUri).readAsBytesSync(),
          sources[i].readAsBytesSync(),
          reason: 'attachment ${i + 1} must keep its source bytes',
        );
      }
      // The source copies are still where they were: nothing consumed them.
      for (final source in sources) {
        expect(source.existsSync(), isTrue);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('a receipt photo on a Recurring item', () {
    late NexTestHarness harness;
    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_receipt_pick_');
    });
    tearDown(() => harness.dispose());

    testWidgets('lands as a file-to-file copy under recurring/', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = harness.services;
      final source = File(
        '${harness.root.path}${Platform.pathSeparator}receipt.png',
      )..writeAsBytesSync(List.filled(48, 7));
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        if (call.method == 'pickImage') return source.path;
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        );
      });
      // path_provider, for the picker-copy discard: any folder outside
      // the source's own will do — the discard checks before it deletes.
      final nowhere = Directory(
        '${harness.root.path}${Platform.pathSeparator}not-the-cache',
      )..createSync();
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, (
        call,
      ) async {
        if (call.method == 'getTemporaryDirectory') return nowhere.path;
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        );
      });

      Map<String, dynamic> details = const {};
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RecurringAttachments(
              services: services,
              details: details,
              onChanged: (next) => details = next,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Receipt photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      // Real file I/O runs in runAsync windows; the poll is the same shape
      // the timeline's photo-capture tests use.
      for (
        var i = 0;
        i < 40 && RecurringAttachments.receiptsOf(details).isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }

      final receipts = RecurringAttachments.receiptsOf(details);
      expect(receipts, hasLength(1));
      final landed = File(
        '${services.mediaDir}${Platform.pathSeparator}${receipts.single}',
      );
      expect(landed.existsSync(), isTrue);
      expect(landed.readAsBytesSync(), source.readAsBytesSync());
      // The picker's own copy is untouched: the discard is cache-only, and
      // this source never was in the cache.
      expect(source.existsSync(), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
