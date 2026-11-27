import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

import 'pdf_preview.dart';
import 'video_preview.dart';

/// What a grid tile can show of its note as a picture, filling the tile
/// (2.8.2). [none] keeps the tile's words; [link] is a link's own picture,
/// when its site gave one (2.8.3).
enum NexTileBackdrop { none, photo, collage, video, pdf, link }

/// Which picture [note]'s tile wears.
///
/// A photo note with more pictures on it is a [NexTileBackdrop.collage] when
/// the grid can read its attachments; a file is shown as itself when it is a
/// picture, a video or a PDF; everything else keeps its words.
NexTileBackdrop nexTileBackdropOf(Note note, {bool collages = true}) {
  final uri = note.mediaUri;
  if (uri == null || uri.isEmpty) return NexTileBackdrop.none;
  if (note.type == NoteType.photo) {
    return collages && note.attachmentCount > 0
        ? NexTileBackdrop.collage
        : NexTileBackdrop.photo;
  }
  if (note.type == NoteType.video) return NexTileBackdrop.video;
  if (note.type != NoteType.file) return NexTileBackdrop.none;
  final original = note.originalFilename;
  if (nexIsPdf(uri, note.mimeType) ||
      (original != null && nexIsPdf(original))) {
    return NexTileBackdrop.pdf;
  }
  final kind = NexFileKinds.of(path: original, mimeType: note.mimeType);
  return switch (kind == NexFileKind.other
      ? NexFileKinds.of(path: uri, mimeType: note.mimeType)
      : kind) {
    NexFileKind.image => NexTileBackdrop.photo,
    NexFileKind.video => NexTileBackdrop.video,
    _ => NexTileBackdrop.none,
  };
}

/// Whether [path] (or its [mimeType]) is a PDF.
bool nexIsPdf(String path, [String? mimeType]) =>
    mimeType?.split(';').first.trim().toLowerCase() == 'application/pdf' ||
    NexFileKinds.extensionOf(path) == 'pdf';

/// A PDF's first page as a tile shows it, and how many pages it has.
typedef NexTilePage = ({Uint8List bytes, int pages});

/// Video frames and PDF pages for grid tiles, read once a run (2.8.2).
///
/// Both come from the operating system through the app's channel, which is
/// far too slow to ask on every build of a tile scrolling past. They are
/// kept in memory only, within a byte budget, oldest first out — never on
/// disk: a preview is a copy of a note's contents, and a copy on disk is one
/// more place a deleted note would still be. A failure is remembered too,
/// so a file that has no frame is not asked again and again.
///
/// A request that is out is shared by every tile that asks for the same file
/// while it is out, and is let go of the moment the answer lands — so a tile
/// built mid-flight is answered too, and the next ask about a file that had
/// none is a new question rather than an old, unfinished one.
abstract final class NexTilePreviews {
  static const _budget = 32 * 1024 * 1024;

  static final _frames = <String, Uint8List?>{};
  static final _pages = <String, NexTilePage?>{};

  /// Requests that are out, by what they will answer: one entry per frame or
  /// page, shared by every tile that asks while it is out.
  static final _pending = <String, Future<Object?>>{};
  static var _bytes = 0;

  /// What [path]'s video frame is already known to be: the bytes, null for
  /// "has none", or absent while it has not been asked.
  static ({Uint8List? bytes})? knownFrame(String path) =>
      _frames.containsKey(path) ? (bytes: _frames[path]) : null;

  static ({NexTilePage? page})? knownPage(String path) =>
      _pages.containsKey(path) ? (page: _pages[path]) : null;

  /// A frame of the video at [path], at most [width] device pixels wide.
  static Future<Uint8List?> frame(String path, {int width = 720}) {
    if (_frames.containsKey(path)) {
      return SynchronousFuture(_touch(_frames, path));
    }
    return _ask(
      'f:$path',
      () => NexVideoPreview.poster(path, width: width),
      (bytes) => _store(_frames, path, bytes, bytes?.length ?? 0),
    );
  }

  /// The first page of the PDF at [path], with its page count.
  static Future<NexTilePage?> page(String path, {int width = 720}) {
    if (_pages.containsKey(path)) {
      return SynchronousFuture(_touch(_pages, path));
    }
    return _ask<NexTilePage>(
      'p:$path',
      () async {
        final page = await NexPdfPreview.page(path, width: width);
        return page == null
            ? null
            : (bytes: page.bytes, pages: page.pageCount);
      },
      (value) => _store(_pages, path, value, value?.bytes.length ?? 0),
    );
  }

  /// Asks [key]'s question once, however many tiles ask at the same time, and
  /// lets go of the request as the answer lands — a picture or none.
  ///
  /// The letting go is a `finally` in an async body on purpose. It used to be
  /// `whenComplete(() => _pending.remove(key))`, and `remove` hands back the
  /// value it took out: the very future `whenComplete` was completing. It then
  /// waited for that future to finish before completing its own — a request
  /// waiting on itself, which never finished. Every tile built while the
  /// request was out waited with it, showing its colour and no picture, and
  /// only a card built again (closing and reopening a date group was the
  /// workaround people found) read the frame that had arrived all along.
  static Future<T?> _ask<T>(
    String key,
    Future<T?> Function() read,
    void Function(T? value) store,
  ) {
    final pending = _pending[key];
    if (pending != null) return pending as Future<T?>;
    final flight = _settle(key, read, store);
    _pending[key] = flight;
    return flight;
  }

  static Future<T?> _settle<T>(
    String key,
    Future<T?> Function() read,
    void Function(T? value) store,
  ) async {
    try {
      final value = await read();
      store(value);
      return value;
    } finally {
      // `removeWhere`, not `remove`: `remove` hands the future being completed
      // back to whoever asks, and holding a future nobody awaited is exactly
      // the shape of the bug this replaces (see [_ask]).
      _pending.removeWhere((asking, _) => asking == key);
    }
  }

  static T? _touch<T>(Map<String, T?> map, String key) {
    final value = map.remove(key);
    map[key] = value;
    return value;
  }

  static void _store<T>(Map<String, T?> map, String key, T? value, int size) {
    // A second answer for the same key replaces the room the first took, so
    // the budget keeps describing what is actually held.
    if (map.containsKey(key)) _bytes -= _sizeOf(map[key]);
    map[key] = value;
    _bytes += size;
    while (_bytes > _budget && (_frames.isNotEmpty || _pages.isNotEmpty)) {
      final from = _frames.isNotEmpty ? _frames : _pages;
      final oldest = from.keys.first;
      _bytes -= _sizeOf(from.remove(oldest));
    }
  }

  /// The room [value] takes from the budget.
  static int _sizeOf(Object? value) => switch (value) {
    final Uint8List bytes => bytes.length,
    (bytes: final Uint8List bytes, pages: int _) => bytes.length,
    _ => 0,
  };

  /// Puts a frame or a page in place, as the channel would have answered.
  @visibleForTesting
  static void debugRemember(
    String path, {
    Uint8List? frame,
    NexTilePage? page,
    bool none = false,
  }) {
    if (none) {
      _store(_frames, path, null, 0);
      _store(_pages, path, null, 0);
    }
    if (frame != null) _store(_frames, path, frame, frame.length);
    if (page != null) _store(_pages, path, page, page.bytes.length);
  }

  /// Forgets everything: the library was locked or restored.
  static void clear() {
    _frames.clear();
    _pages.clear();
    _bytes = 0;
  }
}
