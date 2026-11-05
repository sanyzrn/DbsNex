import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:nex_data/nex_data.dart' show NexBackupArchive;
import 'package:nex_data/schema/zip_file_writer.dart';

import 'vault_store.dart';
import 'authenticated_zip.dart';

/// The voice notes, photos and files attached to private messages.
///
/// The vault itself lives in the platform's encrypted store, which holds a
/// few megabytes of text and is the wrong place for a photo. So each
/// attachment is a file of its own, encrypted with AES-256 the same way the
/// full backup protects its settings (an authenticated WinZip AES entry),
/// under a key that is generated once and kept in that encrypted store. The
/// file on disk is noise without the key, and the key never leaves it.
///
/// Full backups include them only with the explicitly selected private vault.
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
    return Isolate.run(() => _decrypt(sealed, key));
  }

  static Uint8List _decrypt(Uint8List sealed, String key) {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(
      sealed,
      verify: true,
      throwOnError: true,
      password: key,
    );
    assertAuthenticatedZip(decoder);
    if (archive.length != 1 ||
        archive.first.name != 'a' ||
        !archive.first.isFile ||
        archive.first.size > maxBytes) {
      throw const FormatException('Invalid vault attachment');
    }
    return Uint8List.fromList(archive.first.content);
  }

  static Set<String> _references(VaultSnapshot snapshot) => {
    for (final entry in [
      ...snapshot.entries,
      if (snapshot.draft != null) snapshot.draft!,
    ])
      if (entry.value('file').isNotEmpty) entry.value('file'),
  };

  /// The files remain individually encrypted. Their key travels only inside
  /// the full backup's authenticated, encrypted settings entry.
  Future<({String path, String key, String sha256})?> exportBackup(
    VaultSnapshot snapshot,
    String output,
  ) async {
    final ids = _references(snapshot);
    if (ids.isEmpty) return null;
    final key = await _storage.read(key: keyName);
    if (key == null || base64Url.decode(key).length != 32) {
      throw const FormatException('Missing vault attachment key');
    }
    final dir = await _dir();
    final files = {for (final id in ids) id: _file(dir, id).path};
    await Isolate.run(() {
      final zip = ZipFileEncoder();
      try {
        zip.create(output);
        for (final entry in files.entries) {
          final file = File(entry.value);
          if (file.lengthSync() > maxBytes + 1024 * 1024) {
            throw const FormatException('Vault attachment too large');
          }
          addBoundedZipFile(zip, file, '${entry.key}.bin');
        }
      } finally {
        zip.closeSync();
      }
    });
    final digest = await sha256.bind(File(output).openRead()).first;
    return (path: output, key: key, sha256: '$digest');
  }

  /// Re-encrypt under this installation's key and fresh ids. Existing files
  /// and their key are never replaced, so the normal restore undo journal
  /// can still recover the original vault after any interruption.
  Future<VaultSnapshot> restoreBackup(
    VaultSnapshot snapshot,
    String source,
    String key,
  ) async {
    if (base64Url.decode(key).length != 32) {
      throw const FormatException('Invalid vault attachment key');
    }
    final input = InputFileStream(source);
    final installed = <String, String>{};
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      final ids = _references(snapshot);
      final names = {for (final id in ids) '$id.bin'};
      if (archive.length != names.length ||
          archive.files.any(
            (entry) =>
                !entry.isFile ||
                !names.remove(entry.name) ||
                entry.size > maxBytes + 1024 * 1024,
          )) {
        throw const FormatException('Invalid vault file backup');
      }
      NexBackupArchive.assertReasonableSize(archive, File(source).lengthSync());
      for (final entry in archive) {
        final id = p.basenameWithoutExtension(entry.name);
        _file(await _dir(), id);
        final sealed = Uint8List.fromList(entry.content);
        final bytes = await Isolate.run(() => _decrypt(sealed, key));
        installed[id] = await put(bytes);
      }
      VaultEntry remap(VaultEntry entry) => VaultEntry.fromJson({
        ...entry.toJson(),
        'fields': {
          ...entry.fields,
          if (installed.containsKey(entry.value('file')))
            'file': installed[entry.value('file')]!,
        },
      });
      return VaultSnapshot(
        snapshot.entries.map(remap).toList(),
        snapshot.draft == null ? null : remap(snapshot.draft!),
      );
    } catch (_) {
      for (final id in installed.values) {
        try {
          await delete(id);
        } catch (_) {
          /* Retry with normal cleanup. */
        }
      }
      rethrow;
    } finally {
      input.closeSync();
    }
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
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, openFolder, id),
    );
    _file(await _dir(), id); // Validate before using an id as a folder.
    await dir.create(recursive: true);
    final safe = p.basename(name).replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final file = File(p.join(dir.path, safe.isEmpty ? 'attachment' : safe));
    if (!await file.exists()) {
      await file.writeAsBytes(await get(id), flush: true);
    }
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
