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
  if (note.type != NoteType.file) return NexTileBackdrop.none;
  if (nexIsPdf(uri, note.mimeType)) return NexTileBackdrop.pdf;
  return switch (NexFileKinds.of(path: uri, mimeType: note.mimeType)) {
    NexFileKind.image => NexTileBackdrop.photo,
    NexFileKind.video => NexTileBackdrop.video,
    _ => NexTileBackdrop.none,
  };
}

/// Whether [path] (or its [mimeType]) is a PDF.
bool nexIsPdf(String path, String? mimeType) =>
    mimeType == 'application/pdf' || path.toLowerCase().endsWith('.pdf');

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
abstract final class NexTilePreviews {
  static const _budget = 32 * 1024 * 1024;

  static final _frames = <String, Uint8List?>{};
  static final _pages = <String, NexTilePage?>{};
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
    return (_pending['f:$path'] ??= NexVideoPreview.poster(path, width: width)
            .then((bytes) {
              _store(_frames, path, bytes, bytes?.length ?? 0);
              return bytes;
            })
            .whenComplete(() => _pending.remove('f:$path')))
        as Future<Uint8List?>;
  }

  /// The first page of the PDF at [path], with its page count.
  static Future<NexTilePage?> page(String path, {int width = 720}) {
    if (_pages.containsKey(path)) {
      return SynchronousFuture(_touch(_pages, path));
    }
    return (_pending['p:$path'] ??= NexPdfPreview.page(path, width: width)
            .then((page) {
              final value = page == null
                  ? null
                  : (bytes: page.bytes, pages: page.pageCount);
              _store(_pages, path, value, page?.bytes.length ?? 0);
              return value;
            })
            .whenComplete(() => _pending.remove('p:$path')))
        as Future<NexTilePage?>;
  }

  static T? _touch<T>(Map<String, T?> map, String key) {
    final value = map.remove(key);
    map[key] = value;
    return value;
  }

  static void _store<T>(Map<String, T?> map, String key, T? value, int size) {
    map[key] = value;
    _bytes += size;
    while (_bytes > _budget && (_frames.isNotEmpty || _pages.isNotEmpty)) {
      final from = _frames.isNotEmpty ? _frames : _pages;
      final oldest = from.keys.first;
      final gone = from.remove(oldest);
      _bytes -= switch (gone) {
        final Uint8List bytes => bytes.length,
        (bytes: final Uint8List bytes, pages: int _) => bytes.length,
        _ => 0,
      };
    }
  }

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
