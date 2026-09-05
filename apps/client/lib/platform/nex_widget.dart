import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'nex_preferences.dart';
import 'nex_services.dart';

/// One row of the widget snapshot: what a home-screen glance may see of a
/// note, and not one field more.
class NexWidgetNotePreview {
  const NexWidgetNotePreview({
    required this.id,
    required this.type,
    required this.preview,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String preview;
  final int updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'preview': preview,
    'updatedAt': updatedAt,
  };
}

/// The denormalized picture the home-screen widgets render from.
///
/// The widget must never read the library database. SQLite is opened inside
/// [NexDbWorker]'s isolate, its schema is a Dart-side contract, and a second
/// reader — one that runs across a process boundary, wakes whenever the
/// launcher pleases, and cannot be recompiled in step with a migration —
/// would quietly become the app's most fragile database client. Instead the
/// app writes this one small file, and the widget reads that.
///
/// The whole model fits in a couple of kilobytes: a version marker, whether
/// the app lock is on, and the first rows of the timeline in the order the
/// timeline itself shows them. Nothing that is not already on the timeline's
/// first screen is here — no tags, no media paths, no bodies beyond the
/// preview the timeline card would show.
class NexWidgetSnapshot {
  const NexWidgetSnapshot({
    required this.appLock,
    required this.generatedAt,
    required this.notes,
  });

  /// Bumped only when the field set changes in a way the Android reader must
  /// notice. An unknown version is treated as no snapshot at all: the widget
  /// falls back to its empty state rather than rendering half a schema.
  static const int version = 1;

  /// The longest preview one row carries. The widget's row shows one line at
  /// 14sp — roughly ninety glyphs — so 160 keeps the full line plus margin
  /// while bounding what a note costs the file.
  static const int maxPreviewLength = 160;

  /// How much of the timeline the widget may see. The largest useful shape
  /// (four cells tall) shows about six rows under its header; ten covers it
  /// with margin and keeps the file flat whatever the library weighs.
  static const int maxNotes = 10;

  /// Whether the app lock is on. When it is, [notes] is always empty — this
  /// is decided here, at write time, so a locked library's content never
  /// reaches the file at all rather than being hidden after the fact.
  final bool appLock;

  final DateTime generatedAt;
  final List<NexWidgetNotePreview> notes;

  /// The pure part of the job, so the rules below are testable without a
  /// device, a database or a platform channel.
  ///
  /// The notes arrive already in timeline order (pinned first, then most
  /// recently touched — the order [NexServices.timeline] answers in), and
  /// they stay in that order: the widget shows the top of the timeline, not
  /// a re-sorted copy of it.
  ///
  /// The preview is the same text a timeline card shows as the note's own
  /// line — [Note.displayText], whose precedence (title over caption over
  /// body over machine-read text) is the product's decision to make, not
  /// this file's. Whitespace collapses so a multi-line note costs one row,
  /// and the cut is hard at [maxPreviewLength]: the widget ellipsizes at
  /// its own edge, and a snapshot is not the place to carry a whole note.
  static NexWidgetSnapshot build({
    required bool appLock,
    required List<Note> notes,
    DateTime? now,
  }) {
    if (appLock) {
      // No content leaves the app while the lock is on. Not an empty-looking
      // widget with the data still inside — the file itself holds none.
      return NexWidgetSnapshot(
        appLock: true,
        generatedAt: now ?? DateTime.now(),
        notes: const [],
      );
    }
    return NexWidgetSnapshot(
      appLock: false,
      generatedAt: now ?? DateTime.now(),
      notes: [
        for (final note in notes.take(maxNotes))
          NexWidgetNotePreview(
            id: note.id,
            type: note.type.wireName,
            preview: _previewOf(note),
            updatedAt: note.updatedAt.millisecondsSinceEpoch,
          ),
      ],
    );
  }

  static String _previewOf(Note note) {
    final raw = note.displayText ?? '';
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxPreviewLength) return collapsed;
    return collapsed.substring(0, maxPreviewLength);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'appLock': appLock,
    'generatedAt': generatedAt.millisecondsSinceEpoch,
    'notes': [for (final note in notes) note.toJson()],
  };
}

/// Keeps the widgets fed: writes the snapshot whenever widget-visible data
/// moves, then nudges Android to re-render.
///
/// "Whenever it moves" is not a matter of hooking every mutation — every
/// path that changes what the timeline shows already calls
/// [NexServices.refreshTimeline], which emits on [NexServices.timelineStream].
/// Listening there covers capture, edit, delete, tag, pin, restore and
/// purge with one subscription and none of them have to know a widget
/// exists. The two events that stream does not carry get their own lines:
/// the app-lock toggle (content must vanish from the file the moment the
/// lock is switched on) and the write at bootstrap, which is what a freshly
/// placed widget finds when the app has been running a while.
///
/// The nudge is a `pushWidgets` call on `nex/os_capture` — the channel
/// Android side already hosts, and whose comment explains why a second
/// channel would be one more thing to forget to register. Android answers by
/// broadcasting an update to each provider, which re-renders from the file.
/// If the channel is missing (a platform with no native half) there is
/// nothing to nudge, and the write still happened, which is what a widget
/// placed later will read.
class NexWidgetBridge {
  NexWidgetBridge({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  static const _channel = MethodChannel('nex/os_capture');

  static const _debounce = Duration(milliseconds: 300);

  File? _file;
  Timer? _timer;
  StreamSubscription<List<Note>>? _subscription;
  bool? _lastWrittenLock;
  bool _disposed = false;

  /// Writes the first snapshot and subscribes for the rest of the app's run.
  Future<void> start() async {
    // Same directory the database lives in: `getApplicationSupportDirectory`
    // is `context.filesDir` on Android, which is where the Kotlin reader
    // looks. App-private storage, same UID as the widget provider, and no
    // content provider for anything else to reach.
    final support = await getApplicationSupportDirectory();
    _file = File(p.join(support.path, NexWidgetSnapshotCache.fileName));
    preferences.addListener(_onPreferencesChanged);
    _subscription = services.timelineStream.listen((_) => _schedule());
    await _write();
  }

  /// The one preference that changes what the widget may show.
  ///
  /// Preferences change for a hundred reasons that have nothing to do with
  /// the widget; only the lock's on/off does, and only when it actually
  /// flips. This fires on every change and writes on the flip.
  void _onPreferencesChanged() {
    if (_disposed) return;
    final lock = preferences.appLockEnabled;
    if (_lastWrittenLock != null && _lastWrittenLock != lock) {
      _timer?.cancel();
      unawaited(_write());
    }
  }

  /// Coalesces a burst of refreshes (a capture fires several: commit,
  /// enrichment, receipt) into one file write and one broadcast.
  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_write()));
  }

  Future<void> _write() async {
    if (_disposed) return;
    try {
      final file = _file;
      if (file == null) return;
      final lock = preferences.appLockEnabled;
      // Only when unlocked does the snapshot need notes; the query is
      // skipped entirely for a locked library, so unlocking is the only way
      // content ever reaches the file.
      final notes = lock
          ? const <Note>[]
          : await services.timeline(limit: NexWidgetSnapshot.maxNotes);
      final snapshot = NexWidgetSnapshot.build(appLock: lock, notes: notes);
      _lastWrittenLock = lock;
      // Atomic swap. The reader runs whenever the launcher pleases; a
      // half-written file must never be the thing it finds.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await temp.rename(file.path);
      await _push();
    } catch (_) {
      // The snapshot is a copy, not the library: any failure here leaves the
      // notes untouched and the widget showing whatever it last had. Nothing
      // in the app should break because its home screen could not refresh.
    }
  }

  Future<void> _push() async {
    try {
      await _channel.invokeMethod<void>('pushWidgets');
    } on MissingPluginException {
      // No native half on this platform — nothing to refresh.
    } on PlatformException {
      // An engine that is already tearing down. The next write re-asks.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    preferences.removeListener(_onPreferencesChanged);
  }
}

/// Where the Android side looks for the file, kept beside the writer so the
/// two halves of one path cannot drift apart.
abstract final class NexWidgetSnapshotCache {
  static const fileName = 'nex_widget_snapshot.json';
}
