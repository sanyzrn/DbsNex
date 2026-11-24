import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  group('what a file header says it is', () {
    List<int> ascii(String text) => text.codeUnits;

    List<int> ftyp(String brand) => [
      0, 0, 0, 24, // box length
      ...ascii('ftyp'),
      ...ascii(brand),
      0, 0, 0, 0,
    ];

    test('photos', () {
      expect(
        NexFileSignatures.of([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        NexFileKind.image,
      );
      expect(
        NexFileSignatures.of([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]),
        NexFileKind.image,
      );
      expect(NexFileSignatures.of(ascii('GIF89a')), NexFileKind.image);
      expect(
        NexFileSignatures.of([...ascii('RIFF'), 0, 0, 0, 0, ...ascii('WEBP')]),
        NexFileKind.image,
      );
      expect(NexFileSignatures.of(ftyp('heic')), NexFileKind.image);
      expect(NexFileSignatures.of(ftyp('heif')), NexFileKind.image);
      expect(NexFileSignatures.of(ftyp('mif1')), NexFileKind.image);
    });

    test('videos, including the phone formats the picker returns', () {
      expect(NexFileSignatures.of(ftyp('isom')), NexFileKind.video);
      expect(NexFileSignatures.of(ftyp('mp42')), NexFileKind.video);
      expect(NexFileSignatures.of(ftyp('qt  ')), NexFileKind.video);
      expect(NexFileSignatures.of(ftyp('3gp4')), NexFileKind.video);
      expect(
        NexFileSignatures.of([0x1A, 0x45, 0xDF, 0xA3, 0x9F]),
        NexFileKind.video,
      );
      expect(
        NexFileSignatures.of([...ascii('RIFF'), 0, 0, 0, 0, ...ascii('AVI ')]),
        NexFileKind.video,
      );
    });

    test('audio is not media for a photo pick', () {
      expect(NexFileSignatures.of(ftyp('M4A ')), NexFileKind.audio);
      expect(NexFileSignatures.of(ascii('OggS')), NexFileKind.audio);
      expect(NexFileSignatures.of(ascii('ID3')), NexFileKind.audio);
    });

    test('a document is a document whatever its name claims', () {
      expect(NexFileSignatures.of(ascii('%PDF-1.7')), NexFileKind.document);
      expect(NexFileSignatures.of([0x50, 0x4B, 0x03, 0x04]), NexFileKind.other);
      expect(NexFileSignatures.of([0x1F, 0x8B, 0x08]), NexFileKind.other);
    });

    test('an unknown or short header says nothing', () {
      expect(NexFileSignatures.of(const []), isNull);
      expect(NexFileSignatures.of([1, 2, 3]), isNull);
      expect(NexFileSignatures.of(ascii('plain writing')), isNull);
      expect(NexFileSignatures.of([0, 0, 0, 24, ...ascii('fty')]), isNull);
    });
  });
}
