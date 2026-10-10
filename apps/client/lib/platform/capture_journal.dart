import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Durable text snapshots independent of the database worker's command queue.
class CaptureJournal {
  CaptureJournal(String root) : directory = Directory(p.join(root, 'drafts'));
  final Directory directory;

  File _file(String id) {
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid draft id');
    }
    return File(p.join(directory.path, '$id.json'));
  }

  /// How long a keystroke's snapshot waits for the next one.
  static const settle = Duration(milliseconds: 300);

  final _soon = <String, String>{};
  Timer? _timer;

  /// [write], at most once per [settle] (PERF-03).
  ///
  /// Every keystroke used to write and fsync this file on the UI isolate —
  /// three syscalls and a flush per character, which on the eMMC storage of
  /// a 3–4 GB phone is a dropped frame while typing. The database write
  /// behind the same keystrokes already waits 300 ms; the journal now waits
  /// as long, and [flushPending] writes at once when the sheet closes or the
  /// app goes to the background. What a process death can lose is the same
  /// last 300 ms the database write could.
  void writeSoon(String id, String text) {
    _file(id);
    _soon[id] = text;
    _timer ??= Timer(settle, flushPending);
  }

  /// Writes every snapshot [writeSoon] is still holding.
  void flushPending() {
    _timer?.cancel();
    _timer = null;
    final soon = Map.of(_soon);
    _soon.clear();
    for (final MapEntry(key: id, value: text) in soon.entries) {
      try {
        write(id, text);
      } catch (_) {
        // The database write behind the same text reports a failure the
        // person can see; a journal that cannot be written is the backstop
        // missing, not the note.
      }
    }
  }

  void write(String id, String text) {
    directory.createSync(recursive: true);
    final target = _file(id);
    final staging = File('${target.path}.tmp');
    staging.writeAsStringSync(
      jsonEncode({
        'id': id,
        'text': text,
        // When this snapshot was taken, so recovery can tell a journal that
        // is behind the database from one that is ahead of it (DATA-05).
        'at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    staging.renameSync(target.path);
  }

  Iterable<({String id, String text, DateTime at})> pending() sync* {
    if (!directory.existsSync()) return;
    for (final file
        in directory.listSync(followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final value = jsonDecode(file.readAsStringSync()) as Map;
        final id = value['id'] as String;
        if (_file(id).path != file.path) continue;
        // Older journals carry no time; the file's own is the same moment.
        final at =
            DateTime.tryParse(value['at'] as String? ?? '') ??
            file.lastModifiedSync();
        yield (id: id, text: value['text'] as String, at: at.toUtc());
      } catch (_) {
        // Preserve unreadable drafts; never reset the library.
      }
    }
  }

  void complete(String id) {
    _soon.remove(id);
    final file = _file(id);
    if (file.existsSync()) file.deleteSync();
  }
}
