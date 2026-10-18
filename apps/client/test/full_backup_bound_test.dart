import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/full_backup.dart';
import 'package:path/path.dart' as p;

/// 1.99.96 reviews, SEC-11: the outer layer of a complete backup had no size
/// bound, so a hostile `.nexfull` whose library entry claimed gigabytes was
/// written to disk before any of the inner archive's own checks ran.
void main() {
  test(
    'a library entry far larger than its file is refused before unpacking',
    () {
      final root = Directory.systemTemp.createTempSync('nex_full_bound_');
      addTearDown(() => root.deleteSync(recursive: true));
      final library = File(p.join(root.path, 'library.nexbak'))
        ..writeAsBytesSync(List.filled(64, 7));
      final key = FullBackup.newKey();
      final made = p.join(root.path, 'backup.nexfull');
      FullBackup.create(
        library: library.path,
        output: made,
        settings: const {'version': 1, 'preferences': <String, Object?>{}},
        key: key,
      );
      final forged = File(made).readAsBytesSync();
      _claimSize(forged, 'library.nexbak', 0xFFFFFFF0);
      final hostile = File(p.join(root.path, 'hostile.nexfull'))
        ..writeAsBytesSync(forged);
      final out = p.join(root.path, 'out');

      expect(
        () => FullBackup.unpack(
          hostile.path,
          out,
          key,
          modelHash: 'unused',
          modelBytes: 0,
        ),
        throwsA(anything),
      );
      expect(File(p.join(out, 'library.nexbak')).existsSync(), isFalse);
    },
  );
}

/// Rewrites the uncompressed size the central directory records for [name].
void _claimSize(Uint8List zip, String name, int size) {
  final data = ByteData.sublistView(zip);
  for (var i = 0; i + 46 < zip.length; i++) {
    if (data.getUint32(i, Endian.little) != 0x02014b50) continue;
    final nameLength = data.getUint16(i + 28, Endian.little);
    final entry = String.fromCharCodes(
      zip.sublist(i + 46, i + 46 + nameLength),
    );
    if (entry != name) continue;
    data.setUint32(i + 24, size, Endian.little);
    return;
  }
  fail('no central directory entry for $name');
}
