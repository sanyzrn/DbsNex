import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/attachment_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps real photos and videos and refuses everything else', () async {
    final dir = Directory.systemTemp.createTempSync('nex_media_pick_');
    addTearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> head) =>
        File(p.join(dir.path, name))..writeAsBytesSync(head);

    List<int> ascii(String text) => text.codeUnits;
    List<int> ftyp(String brand) => [
      0,
      0,
      0,
      24,
      ...ascii('ftyp'),
      ...ascii(brand),
      0,
      0,
      0,
      0,
    ];

    final png = write('photo.png', [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
      0,
      13,
    ]);
    // An extensionless cached copy: Android's picker can hand one back.
    final jpeg = write('downloaded', [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]);
    // A PDF that claims to be a photo: the file's own bytes decide.
    final disguised = write('scan.jpg', ascii('%PDF-1.7'));
    final video = write('clip.mp4', ftyp('isom'));
    final archive = write('bundle.zip', [0x50, 0x4B, 0x03, 0x04]);
    final missing = File(p.join(dir.path, 'gone.png'));

    final result = await nexFilterMedia([
      CapturedMedia(path: png.path, name: 'photo.png'),
      CapturedMedia(path: jpeg.path, name: 'downloaded'),
      CapturedMedia(
        path: disguised.path,
        name: 'scan.jpg',
        mimeType: 'image/jpeg',
      ),
      CapturedMedia(path: video.path, name: 'clip.mp4'),
      CapturedMedia(path: archive.path, name: 'bundle.zip'),
      CapturedMedia(path: missing.path, name: 'gone.png'),
    ]);

    expect(
      [for (final media in result.media) (media.name, media.kind)],
      [
        ('photo.png', CapturedMediaKind.image),
        ('downloaded', CapturedMediaKind.image),
        ('clip.mp4', CapturedMediaKind.video),
      ],
    );
    expect(result.rejected, ['scan.jpg', 'bundle.zip', 'gone.png']);
  });
}
