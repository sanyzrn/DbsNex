import 'dart:io';
import 'dart:typed_data';

import 'package:nex_data/schema/backup_media_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// On Android the app's own directory is reached through a symlink
/// (/data/user/0 → /data/data). The store's safety check compared a resolved
/// blob path against an unresolved root, so every blob that already existed
/// looked like it lived outside the store — and the second backup, and every
/// export, failed with "Unsafe media blob".
void main() {
  late Directory real;
  late Directory linked;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('nex_media_link_');
    real = Directory(p.join(tmp.path, 'real'))..createSync();
    linked = Directory(p.join(tmp.path, 'linked'));
    Link(linked.path).createSync(real.path);
  });

  tearDown(() => real.parent.deleteSync(recursive: true));

  test('a store reached through a symlink reuses and restores its blobs', () {
    final store = BackupMediaStore(linked.path);
    final source = File(p.join(real.path, 'photo.jpg'))
      ..writeAsBytesSync(Uint8List.fromList(List.generate(4096, (i) => i % 7)));
    final hash = store.retain(source);
    // The second backup finds the blob already there.
    expect(store.retain(source, expectedHash: hash), hash);
    final out = File(p.join(real.path, 'out.jpg'));
    store.restore(hash, out);
    expect(out.readAsBytesSync(), source.readAsBytesSync());
  });

  test('a blob that is a link out of the store is still refused', () {
    final store = BackupMediaStore(linked.path);
    final outside = File(p.join(real.parent.path, 'secret'))
      ..writeAsStringSync('x');
    store.root.createSync(recursive: true);
    const hash =
        '0000000000000000000000000000000000000000000000000000000000000000';
    Link(p.join(store.root.path, hash)).createSync(outside.path);
    expect(() => store.file(hash), throwsFormatException);
  });
}
