import 'dart:async';
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
    if (_soon[key] case final waiting?) return waiting;
    try {
      final value = jsonDecode(_file(key).readAsStringSync());
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  final _soon = <String, Map<String, dynamic>>{};
  Timer? _timer;

  /// [write], at most once per 300 ms: the editors call this on every
  /// keystroke, and a synchronous write and fsync per character was a
  /// dropped frame while typing on slow storage (PERF-03). [read] sees the
  /// waiting value; [flushPending] writes at once, as the app does when it
  /// goes to the background.
  void writeSoon(String key, Map<String, dynamic> value) {
    _soon[key] = value;
    _timer ??= Timer(const Duration(milliseconds: 300), flushPending);
  }

  /// Writes every draft [writeSoon] is still holding.
  void flushPending() {
    _timer?.cancel();
    _timer = null;
    final soon = Map.of(_soon);
    _soon.clear();
    for (final MapEntry(:key, :value) in soon.entries) {
      try {
        write(key, value);
      } catch (_) {
        // A draft that cannot be written leaves the editor's own text
        // untouched; there is nobody to tell from a timer.
      }
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

  final _imageGeneration = <String, int>{};

  /// Keeps a picture for recovery, off the UI thread (PERF-07).
  ///
  /// A photo is megabytes, and writing and flushing it synchronously froze
  /// the frame between picking it and seeing it. Asynchronous file writes
  /// run on Dart's I/O threads. A [clear] that lands while the write is
  /// still going wins: the finished file is dropped instead of published.
  Future<void> writeImage(String key, Uint8List bytes) async {
    final generation = _imageGeneration[key] ?? 0;
    final target = File('${_file(key).path}.image');
    await target.parent.create(recursive: true);
    final staging = File('${target.path}.tmp');
    await staging.writeAsBytes(bytes, flush: true);
    if ((_imageGeneration[key] ?? 0) != generation) {
      if (await staging.exists()) await staging.delete();
      return;
    }
    await staging.rename(target.path);
  }

  void clear(String key) {
    _soon.remove(key);
    _imageGeneration[key] = (_imageGeneration[key] ?? 0) + 1;
    final file = _file(key);
    if (file.existsSync()) file.deleteSync();
    final image = File('${file.path}.image');
    if (image.existsSync()) image.deleteSync();
  }
}
