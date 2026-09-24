/// Replacing the live library with a backup, as one step that can be undone.
///
/// A restore swaps two things — the database and the media directory — and
/// both used to be swapped by deleting the live one and renaming the staged
/// one into its place. Between those two operations the library was in a
/// state nobody chose: an exception, a full disk, or the process being killed
/// after the database had been replaced and before the media had followed
/// left the backup's notes installed over the user's newer ones, the old
/// photos still on disk, and a restore that reported failure over a library
/// it had already overwritten. The deletion of the live media directory came
/// before the rename of the new one, so a failure in that gap lost the media
/// outright.
///
/// Nothing live is deleted until the restore has succeeded. Each live file is
/// *moved aside* instead, next to where it was, and a journal file records
/// that a restore is under way. Then:
///
/// - success deletes the journal — the commit point — and only after that the
///   copies set aside;
/// - failure in-process puts every copy back;
/// - failure out of process (the app killed mid-restore) is found the next
///   time the database is opened: the journal is still there, so the copies
///   go back before anything reads the library. [NexDatabase.open] calls
///   [RestoreTransaction.recover] for exactly this reason.
///
/// Every move is a rename between siblings in one directory, so it stays on
/// one filesystem and is atomic.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The files SQLite may keep beside a database and treat as part of it.
///
/// `-journal` belongs here as well as the WAL pair: a crash under an older
/// rollback-journal build can leave one behind, and SQLite would roll its
/// pages back over whatever file is put in place next.
const _sidecars = ['-wal', '-shm', '-journal'];

final class RestoreTransaction {
  RestoreTransaction._(this.liveDbPath, this.mediaDir);

  final String liveDbPath;
  final String? mediaDir;

  static String _journalOf(String liveDbPath) => '$liveDbPath.restore-journal';
  static Directory _dbAsideOf(String liveDbPath) =>
      Directory('$liveDbPath.rollback.d');
  static Directory _mediaAsideOf(String mediaDir) =>
      Directory('$mediaDir.rollback');

  /// Starts a restore of [liveDbPath], and of [mediaDir] if it will be
  /// replaced too.
  ///
  /// Finishes anything a previous restore left first: two interleaved
  /// journals would be two sets of copies, and only one of them is the
  /// user's library.
  static RestoreTransaction begin({
    required String liveDbPath,
    String? mediaDir,
  }) {
    recover(liveDbPath);
    if (mediaDir != null) {
      // Left by a restore that committed and was then interrupted while it
      // tidied up. Garbage by now: `recover` has just established there is
      // no journal it could belong to.
      final stale = _mediaAsideOf(mediaDir);
      if (stale.existsSync()) stale.deleteSync(recursive: true);
    }
    File(_journalOf(liveDbPath)).writeAsStringSync(mediaDir ?? '', flush: true);
    return RestoreTransaction._(liveDbPath, mediaDir);
  }

  /// Moves the live database aside and puts [staged] where it was.
  ///
  /// The sidecars are moved before the database itself, so that an
  /// interruption part way leaves the database file in exactly one of two
  /// places — which is what [recover] reads to decide which way to go.
  void installDatabase(File staged) {
    final aside = _dbAsideOf(liveDbPath)..createSync(recursive: true);
    final name = p.basename(liveDbPath);
    for (final suffix in [..._sidecars, '']) {
      final live = File('$liveDbPath$suffix');
      if (live.existsSync()) {
        live.renameSync(p.join(aside.path, '$name$suffix'));
      }
    }
    staged.renameSync(liveDbPath);
  }

  /// Moves the live media directory aside and puts [staged] where it was.
  void installMedia(Directory staged) {
    final dir = mediaDir;
    if (dir == null) {
      throw StateError('This restore was begun without a media directory');
    }
    final live = Directory(dir);
    if (live.existsSync()) live.renameSync(_mediaAsideOf(dir).path);
    staged.renameSync(dir);
  }

  /// Makes the restore permanent.
  ///
  /// The journal goes first, because its absence is what "committed" means.
  /// If the process dies after that and before the copies are deleted, they
  /// are garbage to be swept up later, not a library to be put back.
  void commit() {
    File(_journalOf(liveDbPath)).deleteSync();
    final dbAside = _dbAsideOf(liveDbPath);
    if (dbAside.existsSync()) dbAside.deleteSync(recursive: true);
    final dir = mediaDir;
    if (dir != null) {
      final mediaAside = _mediaAsideOf(dir);
      if (mediaAside.existsSync()) mediaAside.deleteSync(recursive: true);
    }
  }

  /// Puts back everything this restore moved aside.
  void rollBack() => recover(liveDbPath);

  /// Undoes an unfinished restore of [liveDbPath], or tidies a finished one.
  ///
  /// Safe to call at any time and cheap when there is nothing to do: one
  /// `existsSync` for the journal and one for the set-aside directory.
  static void recover(String liveDbPath) {
    final journal = File(_journalOf(liveDbPath));
    final dbAside = _dbAsideOf(liveDbPath);

    if (!journal.existsSync()) {
      // Committed and interrupted while tidying, or never started. Either
      // way nothing here is anybody's library any more.
      if (dbAside.existsSync()) dbAside.deleteSync(recursive: true);
      return;
    }

    if (dbAside.existsSync()) {
      final name = p.basename(liveDbPath);
      final asideMain = File(p.join(dbAside.path, name));
      if (asideMain.existsSync()) {
        // The original database was moved, so whatever is at the live path
        // now — the staged copy, and the sidecars opening it produced — is
        // the restore's and goes.
        for (final suffix in ['', ..._sidecars]) {
          final live = File('$liveDbPath$suffix');
          if (live.existsSync()) live.deleteSync();
        }
      }
      // Either way, every file that was set aside goes back to where it was.
      // When the database itself was never moved, these are only the
      // sidecars that had been moved before the interruption.
      for (final suffix in [..._sidecars, '']) {
        final aside = File(p.join(dbAside.path, '$name$suffix'));
        if (!aside.existsSync()) continue;
        final live = File('$liveDbPath$suffix');
        if (live.existsSync()) live.deleteSync();
        aside.renameSync(live.path);
      }
      dbAside.deleteSync(recursive: true);
    }

    final mediaDir = journal.readAsStringSync();
    if (mediaDir.isNotEmpty) {
      final mediaAside = _mediaAsideOf(mediaDir);
      if (mediaAside.existsSync()) {
        final live = Directory(mediaDir);
        if (live.existsSync()) live.deleteSync(recursive: true);
        mediaAside.renameSync(mediaDir);
      }
    }

    journal.deleteSync();
  }
}
