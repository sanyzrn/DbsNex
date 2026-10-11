import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// The voice notes, photos and files attached to private messages.
///
/// The vault itself lives in the platform's encrypted store, which holds a
/// few megabytes of text and is the wrong place for a photo. So each
/// attachment is a file of its own, encrypted with AES-256 the same way the
/// full backup protects its settings (an authenticated WinZip AES entry),
/// under a key that is generated once and kept in that encrypted store. The
/// file on disk is noise without the key, and the key never leaves it.
///
/// Attachments stay on this phone: they are not part of any backup.
class VaultFiles {
  VaultFiles({
    FlutterSecureStorage? storage,
    Future<Directory> Function()? root,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               storageNamespace: 'nex_private_vault',
               resetOnError: false,
               migrateWithBackup: true,
             ),
           ),
       _root = root ?? getApplicationSupportDirectory;

  static const keyName = 'nex.private_vault.files.v1';

  /// The largest attachment kept. It is encrypted in memory, in one piece.
  static const maxBytes = 25 * 1024 * 1024;

  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _root;

  Future<String> _key() async {
    final existing = await _storage.read(key: keyName);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final key = base64Url.encode([
      for (var i = 0; i < 32; i++) random.nextInt(256),
    ]);
    await _storage.write(key: keyName, value: key);
    if (await _storage.read(key: keyName) != key) {
      throw StateError('Vault file key could not be stored');
    }
    return key;
  }

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _root()).path, 'vault_files'));
    await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw ArgumentError('Invalid attachment id');
    }
    return File(p.join(dir.path, '$id.bin'));
  }

  /// Encrypts [bytes] into the vault and answers its id.
  Future<String> put(Uint8List bytes) async {
    if (bytes.length > maxBytes) throw const FileSystemException('Too large');
    final key = await _key();
    final sealed = await Isolate.run(() {
      final archive = Archive()..addFile(ArchiveFile('a', bytes.length, bytes));
      return Uint8List.fromList(ZipEncoder(password: key).encode(archive));
    });
    final id = const Uuid().v4();
    final target = _file(await _dir(), id);
    final staging = File('${target.path}.tmp');
    await staging.writeAsBytes(sealed, flush: true);
    await staging.rename(target.path);
    return id;
  }

  /// The attachment [id], decrypted.
  Future<Uint8List> get(String id) async {
    final sealed = await _file(await _dir(), id).readAsBytes();
    final key = await _key();
    return Isolate.run(() {
      final archive = ZipDecoder().decodeBytes(sealed, password: key);
      return Uint8List.fromList(archive.first.content);
    });
  }

  Future<void> delete(String id) async {
    final file = _file(await _dir(), id);
    if (await file.exists()) await file.delete();
  }

  /// Every attachment, for "Delete all messages".
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// A plain copy of [id] for another app to open, named [name]. It sits in
  /// the cache until [clearOpenCopies] — run whenever the vault locks and
  /// when the app starts.
  Future<File> openCopy(String id, String name) async {
    final bytes = await get(id);
    final dir = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        openFolder,
        const Uuid().v4(),
      ),
    );
    await dir.create(recursive: true);
    final safe = p.basename(name).replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File(p.join(dir.path, safe.isEmpty ? 'attachment' : safe));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static const openFolder = 'vault_open';

  /// Deletes every plain copy [openCopy] made.
  static Future<void> clearOpenCopies() async {
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, openFolder),
      );
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Busy or gone; the next lock or launch tries again.
    }
  }
}
