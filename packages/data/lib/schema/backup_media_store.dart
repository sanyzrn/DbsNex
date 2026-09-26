import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Immutable content-addressed copies shared by local backup manifests.
/// Readers verify their digest, so a missing/corrupt blob fails before restore.
class BackupMediaStore {
  BackupMediaStore(String backupDir)
    : root = Directory(p.join(backupDir, '.media'));
  final Directory root;

  String retain(File source, {String? expectedHash}) {
    root.createSync(recursive: true);
    final partial = File(
      p.join(root.path, '.part-${DateTime.now().microsecondsSinceEpoch}'),
    );
    final before = source.statSync();
    try {
      if (expectedHash != null &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash) &&
          file(expectedHash).existsSync()) {
        if (copyAndHash(source, null) != expectedHash ||
            copyAndHash(file(expectedHash), null) != expectedHash) {
          throw StateError('Media checksum mismatch');
        }
        file(expectedHash).setLastModifiedSync(DateTime.now());
        return expectedHash;
      }
      final hash = copyAndHash(source, partial);
      final after = source.statSync();
      if (before.size != after.size ||
          before.modified != after.modified ||
          (expectedHash != null &&
              expectedHash.isNotEmpty &&
              expectedHash != hash)) {
        throw StateError('Media changed during backup');
      }
      final target = file(hash);
      if (target.existsSync()) {
        if (copyAndHash(target, null) != hash) {
          throw StateError('Stored media checksum mismatch');
        }
      } else {
        partial.renameSync(target.path);
      }
      target.setLastModifiedSync(DateTime.now());
      return hash;
    } finally {
      if (partial.existsSync()) partial.deleteSync();
    }
  }

  File file(String hash) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid media digest');
    }
    final result = File(p.join(root.path, hash));
    if (result.existsSync() &&
        !p.isWithin(root.absolute.path, result.resolveSymbolicLinksSync())) {
      throw const FormatException('Unsafe media blob');
    }
    return result;
  }

  void restore(String hash, File destination) {
    final source = file(hash);
    destination.parent.createSync(recursive: true);
    if (copyAndHash(source, destination) != hash) {
      throw const FormatException('Backup media checksum mismatch');
    }
  }

  static String copyAndHash(File source, File? destination) {
    final input = source.openSync();
    RandomAccessFile? output;
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      output = destination?.openSync(mode: FileMode.write);
      while (true) {
        final bytes = input.readSync(64 * 1024);
        if (bytes.isEmpty) break;
        hash.add(bytes);
        output?.writeFromSync(bytes);
      }
      output?.flushSync();
    } finally {
      input.closeSync();
      output?.closeSync();
      hash.close();
    }
    return digest.value.toString();
  }
}
