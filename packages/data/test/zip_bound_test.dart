import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nex_data/schema/zip_file_writer.dart';
import 'package:test/test.dart';

/// A backup entry is never written past the size it declares (SEC-06).
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('nex-zip-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('an entry that inflates past its declared size is refused', () {
    final entry = ArchiveFile('library.nexbak', 10, Uint8List(1 << 20));
    final path = '${root.path}/out';
    expect(
      () => extractCheckedZipFile(entry, path),
      throwsA(isA<FormatException>()),
    );
    expect(File(path).lengthSync(), lessThanOrEqualTo(10));
  });

  test('an honest entry is extracted whole', () {
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final entry = ArchiveFile.bytes('library.nexbak', bytes);
    final path = '${root.path}/out';
    extractCheckedZipFile(entry, path);
    expect(File(path).readAsBytesSync(), bytes);
  });
}
