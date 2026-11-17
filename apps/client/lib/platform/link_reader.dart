import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpOverrides, InternetAddress, InternetAddressType;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// What a page says about itself.
class LinkPreview {
  const LinkPreview({this.title, this.excerpt, this.imageUrl, this.iconUrl});

  final String? title;
  final String? excerpt;

  /// The picture the page offers for a preview (Open Graph), resolved
  /// against the page (2.8.3).
  final Uri? imageUrl;

  /// The page's own icon, resolved against the page (2.8.3).
  final Uri? iconUrl;

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
  /// [resolve] looks a host's addresses up before anything is fetched from
  /// it. Left out, it is the system's own lookup — unless a [client] is
  /// given or HTTP itself is overridden, which is a test talking to no
  /// network, with no names to look up (and a real lookup there would never
  /// answer). The app never overrides HTTP.
  LinkReader({
    http.Client? client,
    Future<List<InternetAddress>> Function(String host)? resolve,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _resolve =
           resolve ??
           (client == null && HttpOverrides.current == null
               ? InternetAddress.lookup
               : null);

  final http.Client _client;
  final bool _ownsClient;
  final Future<List<InternetAddress>> Function(String host)? _resolve;

  /// Whether every address [uri]'s host has is a public one.
  ///
  /// [isPublicWebUrl] can only judge an address it is given. A name — an
  /// intranet host, or any name someone pointed at 192.168.1.1 — passed it
  /// and the preview went to a machine inside the phone's own network
  /// (1.99.96 reviews, SEC-06). So the name is looked up first, and every
  /// address it has must pass the same test.
  Future<bool> _resolvesPublic(Uri uri) async {
    final resolve = _resolve;
    final host = uri.host;
    if (resolve == null || InternetAddress.tryParse(host) != null) return true;
    final addresses = await resolve(host).timeout(_timeout);
    return addresses.isNotEmpty &&
        addresses.every(
          (address) => isPublicWebUrl(uri.replace(host: address.address)),
        );
  }

  /// How much of the document to read before giving up on finding a title.
  ///
  /// Metadata lives in `<head>`, which is near the top by definition. Pages
  /// that bury it past this are pages this was never going to help with, and
  /// the alternative is downloading megabytes of article for two strings.
  static const _maxBytes = 256 * 1024;

  static const _timeout = Duration(seconds: 8);

  /// How many redirects to follow, each checked by [isPublicWebUrl] again.
  static const _maxRedirects = 5;

  Future<LinkPreview> read(String url) async {
    try {
      final opened = await _open(
        Uri.parse(url),
        accept: 'text/html,application/xhtml+xml',
      );
      if (opened == null) return const LinkPreview();
      final (response, at) = opened;
      final type = response.headers['content-type'] ?? '';
      // Not an error, just not a page: a PDF or an image has no <title>, and
      // trying to parse one as HTML finds nothing slowly.
      if (!type.contains('html')) {
        unawaited(response.stream.listen(null).cancel());
        return const LinkPreview();
      }

      // Read the stream only as far as the cap (SEC-03). Collecting the
      // whole response first and cutting it afterwards kept every byte of an
      // endless or enormous page in memory before the cap was ever applied.
      final body = await readCapped(
        response.stream,
        _maxBytes,
      ).timeout(_timeout);
      return parseLinkPreview(
        utf8.decode(body, allowMalformed: true),
        base: at,
      );
    } catch (_) {
      // Offline, DNS failure, a timeout, TLS refusal, malformed URL — all the
      // same outcome here. The note exists; this was the optional part.
      return const LinkPreview();
    }
  }

  /// A picture at [url] — a page's preview image or its icon — of at most
  /// [maxBytes], checked the way a page is (2.8.3). Null for anything that
  /// is not an image, too large, or not to be had.
  Future<Uint8List?> readImage(Uri url, {int maxBytes = 3 << 20}) async {
    try {
      final opened = await _open(url, accept: 'image/*');
      if (opened == null) return null;
      final (response, _) = opened;
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      final icon = url.path.toLowerCase().endsWith('.ico');
      if (!type.startsWith('image/') &&
          !(icon && type.contains('octet-stream'))) {
        unawaited(response.stream.listen(null).cancel());
        return null;
      }
      final length = response.contentLength;
      if (length != null && length > maxBytes) {
        unawaited(response.stream.listen(null).cancel());
        return null;
      }
      final bytes = await readCapped(
        response.stream,
        maxBytes + 1,
      ).timeout(_timeout);
      return bytes.length > maxBytes || bytes.isEmpty
          ? null
          : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// A small JSON answer at [url] (a video's oEmbed), checked the way a
  /// page is (2.8.3).
  Future<Map<String, Object?>?> readJson(Uri url) async {
    try {
      final opened = await _open(url, accept: 'application/json');
      if (opened == null) return null;
      final body = await readCapped(
        opened.$1.stream,
        64 * 1024,
      ).timeout(_timeout);
      final value = jsonDecode(utf8.decode(body, allowMalformed: true));
      return value is Map<String, Object?> ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// The answer at [start], following redirects by hand, every hop checked
  /// as public; with the address it finally came from. Null when refused or
  /// not a 200.
  Future<(http.StreamedResponse, Uri)?> _open(
    Uri start, {
    required String accept,
  }) async {
    var target = start;
    // Redirects are followed by hand so that every hop is checked: a
    // public page that answers with a redirect to 127.0.0.1 would otherwise
    // walk the preview straight onto the phone's own services.
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!isPublicWebUrl(target)) return null;
      if (!await _resolvesPublic(target)) return null;
      final request = http.Request('GET', target)
        ..followRedirects = false
        ..headers.addAll({
          // Some sites serve a stub to anything that does not look like a
          // browser. This is the smallest honest thing that gets real HTML.
          'User-Agent': 'Mozilla/5.0 (compatible; Nex/1.0; +link-preview)',
          'Accept': accept,
        });
      final sent = await _client.send(request).timeout(_timeout);
      final location = sent.headers['location'];
      if (sent.isRedirect ||
          (sent.statusCode ~/ 100 == 3 && location != null)) {
        unawaited(sent.stream.listen(null).cancel());
        if (location == null) return null;
        target = target.resolve(location);
        continue;
      }
      if (sent.statusCode != 200) {
        unawaited(sent.stream.listen(null).cancel());
        return null;
      }
      return (sent, target);
    }
    return null;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Whether [uri] is a web page on the public internet, which is the only
/// thing a link preview may fetch (SEC-04).
///
/// Refused: any scheme but http and https; `localhost` and `.local` names;
/// and literal addresses that are loopback, private (RFC 1918, RFC 6598,
/// IPv6 unique-local), link-local, unspecified or multicast. A saved note can
/// come from anywhere, and a preview of `http://127.0.0.1:8080/...` or of a
/// router at `192.168.1.1` would be a request from inside the phone's
/// network that nobody asked for.
///
/// Names are not resolved here; [LinkReader] looks them up and runs each
/// address they resolve to back through this.
bool isPublicWebUrl(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal')) {
    return false;
  }
  final address = InternetAddress.tryParse(
    host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host,
  );
  if (address == null) return true;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        b[0] >= 224);
  }
  // IPv6: unspecified, unique-local fc00::/7, and IPv4-mapped private ones.
  if (b.every((x) => x == 0)) return false;
  if ((b[0] & 0xfe) == 0xfc) return false;
  final mapped =
      b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
  if (mapped) {
    return isPublicWebUrl(
      uri.replace(host: '${b[12]}.${b[13]}.${b[14]}.${b[15]}'),
    );
  }
  return true;
}

/// The first [limit] bytes of [stream], or all of it if shorter. Stops
/// listening — which closes the connection — as soon as the limit is reached.
Future<List<int>> readCapped(Stream<List<int>> stream, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    final room = limit - bytes.length;
    if (chunk.length >= room) {
      bytes.add(chunk.sublist(0, room));
      break;
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
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
LinkPreview parseLinkPreview(String html, {Uri? base}) {
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

  Uri? resolved(String? value) {
    if (value == null || base == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final full = base.resolveUri(uri);
    return full.scheme == 'https' || full.scheme == 'http' ? full : null;
  }

  String? icon;
  // The largest the page names first: a touch icon is made to be seen at
  // size, a favicon at sixteen pixels.
  for (final rel in _iconRels) {
    for (final tag in _linkTag.allMatches(html)) {
      final whole = tag.group(0)!;
      final relValue = _attr(whole, 'rel')?.toLowerCase();
      if (relValue == null || !relValue.split(RegExp(r'\s+')).contains(rel)) {
        continue;
      }
      final href = _attr(whole, 'href');
      if (href == null || href.toLowerCase().endsWith('.svg')) continue;
      icon = href;
      break;
    }
    if (icon != null) break;
  }

  return LinkPreview(
    title: _clamp(title, 200),
    excerpt: _clamp(excerpt, 400),
    imageUrl: resolved(
      first(_ogImageSecure) ??
          first(_ogImage) ??
          first(_twitterImage) ??
          first(_twitterImageSrc),
    ),
    iconUrl: resolved(icon) ?? base?.resolve('/favicon.ico'),
  );
}

final _ogImage = _metaPattern('og:image');
final _ogImageSecure = _metaPattern('og:image:secure_url');
final _twitterImage = _metaPattern('twitter:image');
final _twitterImageSrc = _metaPattern('twitter:image:src');
final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
const _iconRels = ['apple-touch-icon', 'apple-touch-icon-precomposed', 'icon'];

String? _attr(String tag, String name) {
  final match = RegExp(
    '\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(tag);
  final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
  return value == null ? null : _decodeEntities(value).trim();
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
