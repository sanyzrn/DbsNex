import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:nex_core/nex_core.dart';

/// Writes the JSON the Android home-screen widgets read.
///
/// The widget providers run inside the app's own process and can read the
/// app's private files, but they cannot run Dart — so the app hands them a
/// tiny, versioned snapshot of what a home screen could possibly want: the
/// newest notes, in timeline order, with just enough text to preview.
///
/// The write is throttled (a capture bursts several timeline refreshes) and
/// never throws: the snapshot is an optimization for the home screen, and it
/// must never be able to disturb the capture path it serves.
class WidgetSnapshotStore {
  WidgetSnapshotStore({
    required this.filePath,
    this.onPublished,
    this.minInterval = const Duration(milliseconds: 1200),
  });

  final String filePath;

  /// Called after a write lands, so the caller can ask Android to repaint
  /// its widgets. Null in tests.
  final VoidCallback? onPublished;

  /// How close two writes may be. A trailing write is scheduled when a
  /// publish arrives inside the window, so the last state always lands.
  final Duration minInterval;

  DateTime? _lastWrite;
  Timer? _trailing;
  List<Note>? _pending;

  static const _snapshotVersion = 1;

  /// How many notes the widgets may show. The notes widget's list is
  /// scrollable, so this is a size cap for the file, not a limit on reach.
  static const maxNotes = 12;

  /// The longest preview line a widget row carries.
  static const maxPreviewLength = 90;

  Future<void> publish(List<Note> notes) async {
    final now = DateTime.now();
    final last = _lastWrite;
    if (last != null && now.difference(last) < minInterval) {
      _pending = notes;
      _trailing ??= Timer(minInterval, () {
        final pending = _pending;
        _pending = null;
        _trailing = null;
        if (pending != null) unawaited(publish(pending));
      });
      return;
    }
    _lastWrite = now;
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_build(notes)), flush: true);
      onPublished?.call();
    } catch (_) {
      // Fail open: the library is intact, only the home screen is stale.
    }
  }

  Map<String, Object?> _build(List<Note> notes) => {
    'v': _snapshotVersion,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
    'notes': [
      for (final note in notes.take(maxNotes))
        {
          'id': note.id,
          'type': note.type.wireName,
          'text': _preview(note),
          'ts': note.createdAt.millisecondsSinceEpoch,
          'pinned': note.pinnedAt != null,
        },
    ],
  };

  /// The line a widget row shows: the same fallback chain the timeline card
  /// uses, trimmed to one row.
  static String _preview(Note note) {
    final text = note.displayText?.trim() ?? '';
    if (text.isEmpty) return '';
    return text.length <= maxPreviewLength
        ? text
        : '${text.substring(0, maxPreviewLength)}…';
  }
}
