import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:nex_data/schema/zip_file_writer.dart';
import 'package:path/path.dart' as p;

/// Library/model entries are portable files. The private preferences entry uses
/// authenticated WinZip AES-256 with a generated 256-bit recovery key (not a
/// human password, for which ZIP's inexpensive KDF would be insufficient).
abstract final class FullBackup {
  static String newKey() =>
      base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));

  static void create({
    required String library,
    required String output,
    required Map<String, dynamic> settings,
    required String key,
    String? model,
    String? modelHash,
  }) {
    if (base64Url.decode(key).length != 32) {
      throw const FormatException('Recovery key');
    }
    final privateZip = Archive()
      ..addFile(ArchiveFile.string('settings.json', jsonEncode(settings)));
    final encrypted = ZipEncoder(password: key).encode(privateZip);
    final encoder = ZipFileEncoder();
    final staging = File('$output.partial');
    try {
      encoder.create(staging.path);
      encoder.addArchiveFile(
        ArchiveFile.string(
          'format.json',
          jsonEncode({'version': 1, 'modelSha256': modelHash}),
        ),
      );
      encoder.addArchiveFile(
        ArchiveFile('settings.aes.zip', encrypted.length, encrypted),
      );
      addBoundedZipFile(encoder, File(library), 'library.nexbak');
      if (model != null) {
        addBoundedZipFile(encoder, File(model), 'model.litertlm');
      }
      encoder.closeSync();
      staging.renameSync(output);
    } catch (_) {
      try {
        encoder.closeSync();
      } catch (_) {}
      if (staging.existsSync()) staging.deleteSync();
      rethrow;
    }
  }

  /// Extract into a caller-owned staging directory. No live data is touched
  /// before decryption, entry validation and model verification have succeeded.
  static Map<String, dynamic> unpack(
    String source,
    String directory,
    String key, {
    required String modelHash,
    required int modelBytes,
  }) {
    if (base64Url.decode(key.trim()).length != 32) {
      throw const FormatException('Recovery key');
    }
    final input = InputFileStream(source);
    try {
      final archive = ZipDecoder().decodeStream(input);
      const names = {
        'format.json',
        'settings.aes.zip',
        'library.nexbak',
        'model.litertlm',
      };
      if (archive.length < 3 ||
          archive.length > 4 ||
          archive.files.map((e) => e.name).toSet().length != archive.length ||
          archive.files.any((e) => !e.isFile || !names.contains(e.name))) {
        throw const FormatException('Invalid full backup');
      }
      final meta = archive.findFile('format.json');
      final secret = archive.findFile('settings.aes.zip');
      final library = archive.findFile('library.nexbak');
      if (meta == null ||
          meta.size > 4096 ||
          secret == null ||
          secret.size > 32 * 1024 * 1024 ||
          library == null) {
        throw const FormatException('Invalid full backup entries');
      }
      final format = jsonDecode(utf8.decode(meta.content)) as Map;
      if (format['version'] != 1) {
        throw const FormatException('Unsupported backup');
      }
      final privateZip = ZipDecoder().decodeBytes(
        secret.content,
        password: key.trim(),
      );
      if (privateZip.length != 1 ||
          privateZip.first.name != 'settings.json' ||
          privateZip.first.size > 32 * 1024 * 1024) {
        throw const FormatException('Invalid settings');
      }
      final settings =
          jsonDecode(utf8.decode(privateZip.first.content))
              as Map<String, dynamic>;
      final model = archive.findFile('model.litertlm');
      if (model != null &&
          (format['modelSha256'] != modelHash || model.size != modelBytes)) {
        throw const FormatException('Unsupported model');
      }
      Directory(directory).createSync(recursive: true);
      extractCheckedZipFile(library, p.join(directory, 'library.nexbak'));
      if (model != null) {
        final path = p.join(directory, 'model.litertlm');
        extractCheckedZipFile(model, path);
        final file = File(path).openSync();
        final sink = _HashSink();
        final hash = sha256.startChunkedConversion(sink);
        try {
          while (true) {
            final bytes = file.readSync(64 * 1024);
            if (bytes.isEmpty) break;
            hash.add(bytes);
          }
        } finally {
          file.closeSync();
          hash.close();
        }
        if (sink.value.toString() != modelHash) {
          throw const FormatException('Model checksum mismatch');
        }
      }
      return settings;
    } finally {
      input.closeSync();
    }
  }
}

class _HashSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
