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

  /// The longest preview one row carries. The widget's row shows two lines at
  /// 14sp — roughly ninety glyphs each — so 200 keeps both full lines plus
  /// margin while bounding what a note costs the file.
  static const int maxPreviewLength = 200;

  /// How much of the timeline the widget may see.
  ///
  /// The tallest shape the launcher will now give it is six cells, which is
  /// about eight rows under the header, so ten was a ceiling the widget could
  /// actually reach. Fifteen covers it with margin and still keeps the file
  /// flat whatever the library weighs.
  static const int maxNotes = 15;

  /// How far down the timeline the writer looks for [maxNotes] matches.
  ///
  /// Only relevant when a filter is on: with no filter the first fifteen
  /// notes are the answer. With one, the widget shows the newest matches
  /// *within the most recent two hundred notes* rather than searching the
  /// whole library — a bounded read that costs the same on a library of two
  /// hundred notes and one of twenty thousand. Someone whose last photo was
  /// three hundred notes ago is looking at a library where a home-screen
  /// glance is the wrong tool anyway.
  static const int scanDepth = 200;

  /// How many notes can hold a pin at once, from `NoteRepository.pinNote`.
  ///
  /// Here because a widget told to ignore pinning has to read this many rows
  /// further down: the first [maxNotes] rows of a pinned-first query are not
  /// the newest [maxNotes] notes when up to five old pins are sitting on top
  /// of them.
  static const int maxPinned = 5;

  /// Whether the widget must draw its locked state. When it does, [notes] is
  /// always empty — decided at write time, so a locked library's content
  /// never reaches the file at all rather than being hidden after the fact.
  final bool appLock;

  /// Whether a snapshot may carry notes at all.
  ///
  /// Three facts, and the order they are asked in is the whole rule:
  ///
  /// - no lock, nothing to hide from;
  /// - a lock the user has told the widget to ignore, and it is their home
  ///   screen and their decision;
  /// - otherwise the notes are shown exactly while the lock is *open*.
  ///
  /// That last clause is the fix for a lock that closes after an hour: the
  /// widget used to empty itself the moment the lock was switched on and stay
  /// empty for the fifty-nine minutes the library was open, which reads as a
  /// broken widget rather than as a locked one.
  static bool hidesNotes({
    required bool lockEnabled,
    required bool showWhenLocked,
    required bool lockClosed,
  }) => lockEnabled && !showWhenLocked && lockClosed;

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
  /// Keeps only what the widget was asked to show.
  ///
  /// Types are filtered here rather than in SQL because the widget's slice is
  /// small and the timeline's ordering — pinned first, then most recently
  /// touched — is a property of that one query. Re-deriving it in a second
  /// query with a type clause would be two definitions of "the top of the
  /// timeline", and the widget exists to show the same list the app does.
  ///
  /// The tag *is* filtered in SQL, because the timeline query already takes
  /// one and doing it twice would be the invention this avoids.
  /// The same notes with the pins let go, most recently touched first.
  ///
  /// Not a second query. "Pinned first, then most recently touched" is one
  /// SQL ordering, and asking the database for a differently-ordered timeline
  /// would be a second definition of the widget's list — the thing
  /// [filter] exists to avoid. Undoing the pinning in Dart keeps one
  /// definition and one read.
  static List<Note> byRecency(List<Note> notes) =>
      [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  static List<Note> filter(List<Note> notes, Set<String> types) =>
      types.isEmpty
      ? notes
      : notes.where((note) => types.contains(note.type.wireName)).toList();

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
  String? _lastWrittenFilter;
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

  /// Whether the snapshot must go out with no notes in it.
  ///
  /// Not "is the app lock switched on", which is what this used to ask and
  /// was wrong: a lock set to close after an hour left the widget empty for
  /// the fifty-nine minutes the library was open, which is not a lock, it is
  /// a widget that does not work. The question is whether the lock is closed
  /// *now* — the flag the gate writes, and one that survives the process
  /// dying, so a phone that was killed while locked does not come back with
  /// its notes on the home screen.
  bool get _hidden => NexWidgetSnapshot.hidesNotes(
    lockEnabled: preferences.appLockEnabled,
    showWhenLocked: preferences.widgetShowWhenLocked,
    lockClosed: preferences.appLockClosed,
  );

  /// The preferences that change what the widget may show.
  ///
  /// Preferences change for a hundred reasons that have nothing to do with
  /// the widget; only these do, and only when they actually flip. This fires
  /// on every change and writes on the flip.
  ///
  /// The lock *closing* does not arrive here — that write is deliberately
  /// silent, because waking every listener in the app is not the right answer
  /// to a lock state — so the gate calls [refresh] instead.
  void _onPreferencesChanged() {
    if (_disposed) return;
    final lock = _hidden;
    final filter = _filterSignature;
    // The lock is written straight through rather than debounced: content
    // must leave the file the moment it is switched on, and 300ms of a
    // locked library's notes still on disk is 300ms too many.
    if (_lastWrittenLock != null && _lastWrittenLock != lock) {
      _timer?.cancel();
      unawaited(_write());
      return;
    }
    // The filters can wait for the debounce — nothing is exposed by showing
    // the wrong slice for a moment, and the widget settings screen changes
    // them a chip at a time.
    if (_lastWrittenFilter != null && _lastWrittenFilter != filter) _schedule();
  }

  /// What the widget was last told to show, as one comparable string.
  ///
  /// A signature rather than the values themselves: this is asked on every
  /// preference change of any kind, and the only question is whether it
  /// differs from last time.
  String get _filterSignature =>
      '${(preferences.widgetTypes.toList()..sort()).join(',')}'
      '|${preferences.widgetTagId ?? ''}'
      '|${preferences.widgetPinnedFirst}';

  /// Writes now, for a change this bridge cannot see coming.
  ///
  /// The lock closing and opening is the only such change: it is written
  /// without notifying listeners, on purpose, so the gate says so directly.
  /// Straight through rather than debounced — when the lock closes, notes
  /// have to leave the file, and 300ms of a locked library's notes still on
  /// disk is 300ms too many.
  Future<void> refresh() => _write();

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
      final lock = _hidden;
      // Only when the notes may be shown does the snapshot need them; the
      // query is skipped entirely otherwise, so a hidden library's content
      // never reaches the file rather than being filtered out of it later.
      final types = preferences.widgetTypes;
      final pinnedFirst = preferences.widgetPinnedFirst;
      // No filter, no reason to read past what fits: the first rows of the
      // timeline are the answer, and that is the overwhelmingly common case.
      // The exception is a widget ignoring pins, which has to see past the
      // pins it is about to demote.
      final depth = types.isEmpty
          ? NexWidgetSnapshot.maxNotes +
                (pinnedFirst ? 0 : NexWidgetSnapshot.maxPinned)
          : NexWidgetSnapshot.scanDepth;
      final timeline = lock
          ? const <Note>[]
          : await services.timeline(
              limit: depth,
              tagId: preferences.widgetTagId,
            );
      final notes = NexWidgetSnapshot.filter(
        pinnedFirst ? timeline : NexWidgetSnapshot.byRecency(timeline),
        types,
      );
      final snapshot = NexWidgetSnapshot.build(appLock: lock, notes: notes);
      _lastWrittenLock = lock;
      _lastWrittenFilter = _filterSignature;
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
