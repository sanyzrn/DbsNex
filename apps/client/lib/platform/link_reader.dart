import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a page says about itself.
class LinkPreview {
  const LinkPreview({this.title, this.excerpt});

  final String? title;
  final String? excerpt;

  bool get isEmpty => title == null && excerpt == null;
}

/// Reads the title and description off a web page, without a headless browser
/// and without a third-party unfurling service.
///
/// A service would be easier and is the wrong trade for this app: it would
/// mean every link anyone saves is also sent to somebody else's server, which
/// is exactly the promise Nex makes about the AI provider being the *only*
/// thing that can see a note. This talks to the page directly, so the only
/// party that learns about the bookmark is the site being bookmarked.
///
/// Deliberately small. It reads the head of the document, pulls Open Graph
/// tags with an HTML `<title>` fallback, and gives up quietly on anything
/// unusual — a link note with no preview is a working link note, and this is
/// decoration on top of something already saved.
class LinkReader {
  LinkReader({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// How much of the document to read before giving up on finding a title.
  ///
  /// Metadata lives in `<head>`, which is near the top by definition. Pages
  /// that bury it past this are pages this was never going to help with, and
  /// the alternative is downloading megabytes of article for two strings.
  static const _maxBytes = 256 * 1024;

  static const _timeout = Duration(seconds: 8);

  Future<LinkPreview> read(String url) async {
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers.addAll({
          // Some sites serve a stub to anything that does not look like a
          // browser. This is the smallest honest thing that gets real HTML.
          'User-Agent': 'Mozilla/5.0 (compatible; Nex/1.0; +link-preview)',
          'Accept': 'text/html,application/xhtml+xml',
        });
      final response = await _client
          .send(request)
          .timeout(_timeout)
          .then(http.Response.fromStream);

      if (response.statusCode != 200) return const LinkPreview();
      final type = response.headers['content-type'] ?? '';
      // Not an error, just not a page: a PDF or an image has no <title>, and
      // trying to parse one as HTML finds nothing slowly.
      if (!type.contains('html')) return const LinkPreview();

      final body = response.bodyBytes.length > _maxBytes
          ? response.bodyBytes.sublist(0, _maxBytes)
          : response.bodyBytes;
      return parseLinkPreview(utf8.decode(body, allowMalformed: true));
    } catch (_) {
      // Offline, DNS failure, a timeout, TLS refusal, malformed URL — all the
      // same outcome here. The note exists; this was the optional part.
      return const LinkPreview();
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

final _ogTitle = _metaPattern('og:title');
final _ogDescription = _metaPattern('og:description');
final _twitterTitle = _metaPattern('twitter:title');
final _twitterDescription = _metaPattern('twitter:description');
final _description = _metaPattern('description');
final _htmlTitle = RegExp(
  r'<title[^>]*>([\s\S]*?)</title>',
  caseSensitive: false,
);

/// Matches a `<meta>` tag for [key] with the attributes in either order.
///
/// Both orders happen in the wild, and `property=` versus `name=` splits along
/// Open Graph versus plain HTML — a single pattern that insists on one shape
/// silently misses half the pages it is pointed at.
RegExp _metaPattern(String key) => RegExp(
  '<meta[^>]+(?:property|name)=["\']${RegExp.escape(key)}["\'][^>]*'
  'content=["\']([^"\']*)["\']'
  '|'
  '<meta[^>]+content=["\']([^"\']*)["\'][^>]*'
  '(?:property|name)=["\']${RegExp.escape(key)}["\']',
  caseSensitive: false,
);

/// Pulls a title and description out of [html].
///
/// Separate from [LinkReader] so it can be tested against real page fragments
/// without a network — which is the half of this worth testing, since the
/// fetch is a `get` and the parsing is where pages disagree.
LinkPreview parseLinkPreview(String html) {
  String? first(RegExp pattern) {
    final match = pattern.firstMatch(html);
    if (match == null) return null;
    final value = match.group(1) ?? match.group(2);
    final cleaned = _decodeEntities(value ?? '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  final title = first(_ogTitle) ?? first(_twitterTitle) ?? first(_htmlTitle);
  final excerpt =
      first(_ogDescription) ??
      first(_twitterDescription) ??
      first(_description);

  return LinkPreview(title: _clamp(title, 200), excerpt: _clamp(excerpt, 400));
}

/// The handful of entities that actually show up in titles. Not a full HTML
/// entity table: a title with `&hellip;` in it is still a usable title, and
/// carrying a lookup of every named entity to improve that would be a lot of
/// bytes for a rounding error.
String _decodeEntities(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String? _clamp(String? value, int max) {
  if (value == null) return null;
  return value.length <= max ? value : '${value.substring(0, max)}…';
}
