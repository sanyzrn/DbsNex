import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:typed_data';

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

  /// How many redirects to follow, each checked by [isPublicWebUrl] again.
  static const _maxRedirects = 5;

  Future<LinkPreview> read(String url) async {
    try {
      var target = Uri.parse(url);
      http.StreamedResponse? response;
      // Redirects are followed by hand so that every hop is checked: a
      // public page that answers with a redirect to 127.0.0.1 would otherwise
      // walk the preview straight onto the phone's own services.
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        if (!isPublicWebUrl(target)) return const LinkPreview();
        final request = http.Request('GET', target)
          ..followRedirects = false
          ..headers.addAll({
            // Some sites serve a stub to anything that does not look like a
            // browser. This is the smallest honest thing that gets real HTML.
            'User-Agent': 'Mozilla/5.0 (compatible; Nex/1.0; +link-preview)',
            'Accept': 'text/html,application/xhtml+xml',
          });
        final sent = await _client.send(request).timeout(_timeout);
        final location = sent.headers['location'];
        if (sent.isRedirect ||
            (sent.statusCode ~/ 100 == 3 && location != null)) {
          if (location == null) return const LinkPreview();
          unawaited(sent.stream.listen(null).cancel());
          target = target.resolve(location);
          continue;
        }
        response = sent;
        break;
      }
      if (response == null) return const LinkPreview();

      if (response.statusCode != 200) return const LinkPreview();
      final type = response.headers['content-type'] ?? '';
      // Not an error, just not a page: a PDF or an image has no <title>, and
      // trying to parse one as HTML finds nothing slowly.
      if (!type.contains('html')) return const LinkPreview();

      // Read the stream only as far as the cap (SEC-03). Collecting the
      // whole response first and cutting it afterwards kept every byte of an
      // endless or enormous page in memory before the cap was ever applied.
      final body = await readCapped(
        response.stream,
        _maxBytes,
      ).timeout(_timeout);
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
/// Names are not resolved here, so a public name that resolves to a private
/// address is not caught; the request still goes nowhere the user did not
/// type, and nothing it returns leaves the device.
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
