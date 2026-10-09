import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/export_cache.dart';
import 'package:path/path.dart' as p;

/// Android's file picker copies the chosen file into the cache, under a
/// UUID folder, and never removes it (SEC-01). For a password CSV that copy
/// is every password in plain text; for a backup, the whole library.
void main() {
  late Directory cache;
  const uuid = '6f9619ff-8b86-d011-b42d-00c04fc964ff';

  setUp(() => cache = Directory.systemTemp.createTempSync('nex_cache_'));
  tearDown(() => cache.deleteSync(recursive: true));

  File picked(String name) =>
      File(p.join(cache.path, uuid, name))
        ..createSync(recursive: true)
        ..writeAsStringSync('url,username,password\nx,y,secret');

  test('the copy is deleted once it has been read', () async {
    final file = picked('Passwords.csv');
    await discardPickedCopy(file.path, cache);
    expect(Directory(p.join(cache.path, uuid)).existsSync(), isFalse);
  });

  test('a file outside the cache is never touched', () async {
    final outside = Directory.systemTemp.createTempSync('nex_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final own = File(p.join(outside.path, 'Passwords.csv'))
      ..writeAsStringSync('mine');
    await discardPickedCopy(own.path, cache);
    expect(own.existsSync(), isTrue);
  });

  test('a copy left by a crash is swept on the next launch', () async {
    picked('backup.nexfull');
    final other = Directory(p.join(cache.path, 'image_cache'))..createSync();
    await cleanExportCache(
      cache,
      now: DateTime.now().add(const Duration(hours: 2)),
    );
    expect(Directory(p.join(cache.path, uuid)).existsSync(), isFalse);
    expect(other.existsSync(), isTrue, reason: 'only the picker\'s folders');
  });

  test('a copy being read right now is left alone', () async {
    picked('Passwords.csv');
    await cleanExportCache(cache);
    expect(Directory(p.join(cache.path, uuid)).existsSync(), isTrue);
  });
}
