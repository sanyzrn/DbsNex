import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:nex_core/nex_core.dart';
import 'package:path_provider/path_provider.dart';

import 'link_face.dart';
import 'link_reader.dart';

/// A link's picture and its site's icon, kept on the phone (2.8.3).
typedef NexLinkPictures = ({File? cover, File? icon});

/// The pictures that make a link's card look like what it points at.
///
/// Fetched the way the page's title is — straight from the site, never
/// through a service — when a link is saved, and once later for a link that
/// was saved without them (offline, or a site that was out of reach). A
/// picture is taken only from the page's own site, or the one a known site
/// serves its pictures from (YouTube's thumbnails), so no one but the site
/// learns what was bookmarked.
///
/// Kept small, re-encoded (nothing of the original file's metadata comes
/// along), outside backups — they can always be fetched again — and removed
/// with the note: a deleted note's picture is not left behind.
class NexLinkArt extends ChangeNotifier {
  NexLinkArt._();

  static final instance = NexLinkArt._();

  /// Where the pictures live; set by [debugUse] in tests.
  Directory? _dir;
  Future<Directory?>? _opening;
  final _known = <String, NexLinkPictures>{};

  /// Notes whose site had nothing to give, as the day they were last asked.
  final _empty = <String, DateTime>{};

  /// Asked this run already: a site out of reach is not asked again until
  /// the next one.
  final _asked = <String>{};
  final _queue = <(String, String, bool)>[];
  bool _running = false;

  static const _coverWidth = 720;
  static const _iconSize = 96;

  /// How long a site that had no picture is left alone.
  static const _askAgainAfter = Duration(days: 7);

  /// What is known of [noteId]'s pictures, read without waiting.
  NexLinkPictures? of(String noteId) => _known[noteId];

  Future<Directory?> _folder() => _opening ??= () async {
    if (_dir != null) return _dir;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/link_art');
      await dir.create(recursive: true);
      _load(dir);
      return _dir = dir;
    } catch (_) {
      return null;
    }
  }();

  void _load(Directory dir) {
    for (final entry in dir.listSync().whereType<File>()) {
      final name = entry.uri.pathSegments.last;
      final dot = name.indexOf('.');
      if (dot <= 0) continue;
      final id = name.substring(0, dot);
      final kind = name.substring(dot + 1);
      final known = _known[id] ?? (cover: null, icon: null);
      if (kind == 'cover.jpg') {
        _known[id] = (cover: entry, icon: known.icon);
      } else if (kind == 'icon.png') {
        _known[id] = (cover: known.cover, icon: entry);
      } else if (kind == 'none') {
        _empty[id] = entry.lastModifiedSync();
      }
    }
  }

  /// Opens the folder, so [of] knows what is there before the first tile.
  Future<void> open() async {
    await _folder();
    notifyListeners();
  }

  /// Called with a page's title and description when a later fetch finds
  /// words a note saved without them is missing (2.8.3). The app saves them
  /// on the note, as reading the page at capture would have.
  Future<void> Function(String noteId, String? title, String? excerpt)?
  onPageWords;

  /// Fetches [noteId]'s pictures for [url], using what reading the page
  /// already found in [page]. [wantWords] asks for the page's title too, for
  /// a note that was saved without one.
  Future<void> fetch(
    String noteId,
    String url, {
    LinkPreview? page,
    bool wantWords = false,
  }) async {
    final dir = await _folder();
    if (dir == null) return;
    _asked.add(noteId);
    final face = NexLinkFace.of(url);
    final reader = LinkReader();
    try {
      Uri? cover;
      Uri? icon;
      // Whether the site answered at all: one out of reach (offline,
      // filtered) is asked again later, one that answered with nothing is
      // left alone for a week.
      var reached = false;
      if (face.youTubeId case final id?) {
        cover = Uri.parse('https://i.ytimg.com/vi/$id/hqdefault.jpg');
        if (wantWords) {
          final about = await reader.readJson(
            Uri.https('www.youtube.com', '/oembed', {
              'url': 'https://www.youtube.com/watch?v=$id',
              'format': 'json',
            }),
          );
          final title = about?['title'];
          final channel = about?['author_name'];
          if (title is String && title.trim().isNotEmpty) {
            await onPageWords?.call(
              noteId,
              title.trim(),
              channel is String ? channel.trim() : null,
            );
          }
        }
      } else {
        final found = page ?? await reader.read(url);
        // A page that was read has an icon address at least (its
        // /favicon.ico); one that was not has nothing at all.
        reached = found.iconUrl != null || !found.isEmpty;
        if (page == null && wantWords && !found.isEmpty) {
          await onPageWords?.call(noteId, found.title, found.excerpt);
        }
        final pageUri = Uri.tryParse(url);
        if (found.imageUrl case final image?
            when pageUri != null && nexSameSite(pageUri, image)) {
          cover = image;
        }
        if (found.iconUrl case final i?
            when pageUri != null && nexSameSite(pageUri, i)) {
          icon = i;
        }
      }
      final coverBytes = cover == null ? null : await reader.readImage(cover);
      final iconBytes = icon == null
          ? null
          : await reader.readImage(icon, maxBytes: 256 << 10);
      if (face.youTubeId != null) reached = coverBytes != null;
      final shrunk = await compute(_shrink, (
        cover: coverBytes,
        icon: iconBytes,
        youTube: face.youTubeId != null,
      ));
      File? coverFile;
      File? iconFile;
      if (shrunk.cover case final bytes?) {
        coverFile = await _write(dir, '$noteId.cover.jpg', bytes);
      }
      if (shrunk.icon case final bytes?) {
        iconFile = await _write(dir, '$noteId.icon.png', bytes);
      }
      if (coverFile == null && iconFile == null) {
        if (reached) {
          await _write(dir, '$noteId.none', const []);
          _empty[noteId] = DateTime.now();
        }
        return;
      }
      _empty.remove(noteId);
      _known[noteId] = (cover: coverFile, icon: iconFile);
      notifyListeners();
    } catch (_) {
      // A link card without a picture is still a link card.
    } finally {
      reader.close();
    }
  }

  static Future<File> _write(
    Directory dir,
    String name,
    List<int> bytes,
  ) async {
    final file = File('${dir.path}/$name');
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    return part.rename(file.path);
  }

  /// Asks once, in the background and one at a time, for the pictures of
  /// the links among [notes] that have none yet.
  void fillIn(Iterable<Note> notes, {int most = 24}) {
    // Nowhere to keep them yet (or ever, in a test): nothing is asked.
    if (_dir == null) return;
    for (final note in notes) {
      if (_queue.length >= most) break;
      final url = note.linkUrl;
      if (note.type != NoteType.link || url == null) continue;
      if (_known.containsKey(note.id) || _asked.contains(note.id)) continue;
      if (_empty[note.id] case final asked?
          when DateTime.now().difference(asked) < _askAgainAfter) {
        continue;
      }
      if (_queue.any((q) => q.$1 == note.id)) continue;
      final titled =
          (note.title ?? '').trim().isNotEmpty &&
          note.title!.trim() != url.trim();
      _queue.add((note.id, url, !titled));
    }
    if (_running || _queue.isEmpty) return;
    _running = true;
    unawaited(() async {
      try {
        // After the screen has settled, never in the way of opening it.
        await Future<void>.delayed(const Duration(seconds: 3));
        while (_queue.isNotEmpty) {
          final (id, url, words) = _queue.removeAt(0);
          await fetch(id, url, wantWords: words);
        }
      } finally {
        _running = false;
      }
    }());
  }

  /// Lets go of [noteId]'s pictures: the note is gone.
  ///
  /// Never opens the folder for it: deleting a note must not wait on its
  /// pictures. A folder not opened yet this run is swept when it is.
  Future<void> forget(String noteId) async {
    final dir = _dir;
    final had = _known.remove(noteId) != null;
    _empty.remove(noteId);
    if (dir == null) return;
    for (final name in ['cover.jpg', 'icon.png', 'none']) {
      try {
        await File('${dir.path}/$noteId.$name').delete();
      } catch (_) {}
    }
    if (had) notifyListeners();
  }

  /// Lets go of the pictures of every note [exists] no longer finds.
  Future<void> sweep(Future<bool> Function(String noteId) exists) async {
    await _folder();
    for (final id in {..._known.keys, ..._empty.keys}.toList()) {
      if (!await exists(id)) await forget(id);
    }
  }

  /// Forgets everything: the library was replaced.
  Future<void> clear() async {
    final dir = await _folder();
    _known.clear();
    _empty.clear();
    _asked.clear();
    _queue.clear();
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Uses [dir], and nothing on disk the app would use (tests).
  @visibleForTesting
  void debugUse(Directory dir) {
    _known.clear();
    _empty.clear();
    _asked.clear();
    _queue.clear();
    _dir = dir;
    _opening = Future.value(dir);
    _load(dir);
  }

  /// Puts pictures in place for [noteId], as a fetch would have (tests).
  @visibleForTesting
  void debugRemember(String noteId, {File? cover, File? icon}) {
    _known[noteId] = (cover: cover, icon: icon);
    notifyListeners();
  }
}

/// Whether [picture] comes from [page]'s own site: the same registered
/// name, or the one a known site keeps its pictures on.
bool nexSameSite(Uri page, Uri picture) {
  final a = _siteOf(page.host);
  final b = _siteOf(picture.host);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return _pictureHosts[a]?.contains(b) ?? false;
}

const _pictureHosts = <String, Set<String>>{
  'youtube.com': {'ytimg.com', 'ggpht.com'},
  'youtu.be': {'ytimg.com'},
  'github.com': {'githubassets.com', 'githubusercontent.com'},
  'wikipedia.org': {'wikimedia.org'},
  'x.com': {'twimg.com'},
  'twitter.com': {'twimg.com'},
  'instagram.com': {'cdninstagram.com', 'fbcdn.net'},
  't.me': {'telesco.pe'},
  'reddit.com': {'redd.it', 'redditmedia.com', 'redditstatic.com'},
  'aparat.com': {'aparat.cloud', 'aparatcdn.com'},
};

/// The registered part of [host]: `news.bbc.co.uk` → `bbc.co.uk`.
String _siteOf(String host) {
  final parts = host.toLowerCase().split('.')..removeWhere((p) => p.isEmpty);
  if (parts.length < 2) return '';
  final second = parts[parts.length - 2];
  final shared =
      parts.length >= 3 &&
      parts.last.length == 2 &&
      const {
        'co',
        'com',
        'org',
        'net',
        'ac',
        'gov',
        'edu',
        'id',
      }.contains(second);
  return parts.sublist(parts.length - (shared ? 3 : 2)).join('.');
}

/// The pictures re-encoded small, off the main isolate. A cover too small or
/// too oddly shaped to be a picture of the page — a tracking pixel, a
/// banner — is dropped; YouTube's thumbnail loses its letterbox bars.
({Uint8List? cover, Uint8List? icon}) _shrink(
  ({Uint8List? cover, Uint8List? icon, bool youTube}) input,
) {
  Uint8List? cover;
  Uint8List? icon;
  try {
    if (input.cover case final bytes?) {
      var image = img.decodeImage(bytes);
      if (image != null &&
          input.youTube &&
          image.height * 4 >= image.width * 3) {
        // 4:3 with the video's 16:9 between bars.
        final h = (image.width * 9 / 16).round();
        image = img.copyCrop(
          image,
          x: 0,
          y: (image.height - h) ~/ 2,
          width: image.width,
          height: h,
        );
      }
      if (image != null &&
          image.width >= 200 &&
          image.height >= 100 &&
          image.width / image.height <= 3.2 &&
          image.height / image.width <= 2) {
        final small = image.width > NexLinkArt._coverWidth
            ? img.copyResize(image, width: NexLinkArt._coverWidth)
            : image;
        cover = img.encodeJpg(small, quality: 82);
      }
    }
  } catch (_) {}
  try {
    if (input.icon case final bytes?) {
      final image = img.decodeImage(bytes);
      if (image != null && image.width >= 16 && image.height >= 16) {
        final small = image.width > NexLinkArt._iconSize
            ? img.copyResize(
                image,
                width: NexLinkArt._iconSize,
                height: NexLinkArt._iconSize,
              )
            : image;
        icon = img.encodePng(small);
      }
    }
  } catch (_) {}
  return (cover: cover, icon: icon);
}
