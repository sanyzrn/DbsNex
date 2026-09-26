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

  void write(String id, String text) {
    directory.createSync(recursive: true);
    final target = _file(id);
    final staging = File('${target.path}.tmp');
    staging.writeAsStringSync(
      jsonEncode({'id': id, 'text': text}),
      flush: true,
    );
    staging.renameSync(target.path);
  }

  Iterable<({String id, String text})> pending() sync* {
    if (!directory.existsSync()) return;
    for (final file
        in directory.listSync(followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final value = jsonDecode(file.readAsStringSync()) as Map;
        final id = value['id'] as String;
        if (_file(id).path != file.path) continue;
        yield (id: id, text: value['text'] as String);
      } catch (_) {
        // Preserve unreadable drafts; never reset the library.
      }
    }
  }

  void complete(String id) {
    final file = _file(id);
    if (file.existsSync()) file.deleteSync();
  }
}
