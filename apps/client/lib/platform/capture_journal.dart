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

  /// This journal's file operations, one after another in the order they
  /// were asked for.
  ///
  /// Every write used to be a synchronous create, flush and rename on the
  /// isolate drawing the screen — three syscalls and an fsync during a
  /// typing pause (PERF-03 already settled them to once per pause; the
  /// pause's own write still stopped a frame on slow storage). The writes
  /// now run as file-system events off that isolate, serialized here so the
  /// last one in always lands after the ones before it: a draft written and
  /// then completed leaves nothing behind, exactly as the synchronous
  /// writes did.
  Future<void> _io = Future<void>.value();

  /// Waits for every queued file operation to land. Recovery reads happen at
  /// launch, before anything is queued; this is for tests and for callers
  /// that want to know the backstop is on disk.
  Future<void> flush() => _io;

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

  Future<void> write(String id, String text) {
    final target = _file(id);
    final payload = jsonEncode({
      'id': id,
      'text': text,
      // When this snapshot was taken, so recovery can tell a journal that
      // is behind the database from one that is ahead of it (DATA-05).
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    return _io = _io.then((_) async {
      try {
        await directory.create(recursive: true);
        final staging = File('${target.path}.tmp');
        await staging.writeAsString(payload, flush: true);
        await staging.rename(target.path);
      } catch (_) {
        // The database write behind the same text reports a failure the
        // person can see; a journal that cannot be written is the backstop
        // missing, not the note.
      }
    });
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
    _io = _io.then((_) async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A draft that cannot be removed is a stray file the recovery
        // sweep will report, not a note in place.
      }
    });
  }
}
