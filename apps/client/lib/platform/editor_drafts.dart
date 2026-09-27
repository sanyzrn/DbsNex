import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Per-editor recovery, separate from quick capture's automatic recovery.
/// A draft is removed only by an explicit discard or a successful save.
class EditorDrafts {
  EditorDrafts(this.root);
  final String root;
  File _file(String key) =>
      File(p.join(root, '${sha256.convert(utf8.encode(key))}.json'));
  Map<String, dynamic>? read(String key) {
    try {
      final value = jsonDecode(_file(key).readAsStringSync());
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  void write(String key, Map<String, dynamic> value) {
    final file = _file(key);
    file.parent.createSync(recursive: true);
    final staging = File('${file.path}.tmp');
    staging.writeAsStringSync(jsonEncode(value), flush: true);
    staging.renameSync(file.path);
  }

  Uint8List? readImage(String key) {
    try {
      return File('${_file(key).path}.image').readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  void writeImage(String key, Uint8List bytes) {
    final target = File('${_file(key).path}.image');
    target.parent.createSync(recursive: true);
    final staging = File('${target.path}.tmp');
    staging.writeAsBytesSync(bytes, flush: true);
    staging.renameSync(target.path);
  }

  void clear(String key) {
    final file = _file(key);
    if (file.existsSync()) file.deleteSync();
    final image = File('${file.path}.image');
    if (image.existsSync()) image.deleteSync();
  }
}
