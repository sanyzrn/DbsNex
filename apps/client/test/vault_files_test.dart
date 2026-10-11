import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/vault_files.dart';

/// Attachments in private messages are sealed on disk (1.99.9).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late VaultFiles files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nex_vault_files_');
    files = VaultFiles(
      storage: const FlutterSecureStorage(),
      root: () async => root,
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'an attachment comes back as it went in, and is not plain on disk',
    () async {
      final secret = Uint8List.fromList('a private voice note'.codeUnits);
      final id = await files.put(secret);

      expect(await files.get(id), secret);
      final sealed = File('${root.path}/vault_files/$id.bin').readAsBytesSync();
      expect(String.fromCharCodes(sealed).contains('private voice'), isFalse);
    },
  );

  test('deleted, it is gone; delete all empties the folder', () async {
    final one = await files.put(Uint8List.fromList([1, 2, 3]));
    final two = await files.put(Uint8List.fromList([4, 5, 6]));
    await files.delete(one);
    expect(File('${root.path}/vault_files/$one.bin').existsSync(), isFalse);
    expect(await files.get(two), [4, 5, 6]);

    await files.deleteAll();
    expect(Directory('${root.path}/vault_files').existsSync(), isFalse);
  });

  test('too large is refused before anything is written', () async {
    expect(
      () => files.put(Uint8List(VaultFiles.maxBytes + 1)),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('an id cannot reach outside the folder', () async {
    expect(() => files.get('../../etc/passwd'), throwsArgumentError);
  });
}
