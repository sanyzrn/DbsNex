/// What a link is, read from its address alone (2.8.3).
///
/// No network: the site's name and colour when it is one people know, what
/// kind of thing the address points at, and a title when the address spells
/// one out — a Wikipedia article, a GitHub repository, an article's slug.
/// A link saved with no connection, or to a site that is filtered, still
/// says what it is.
library;

/// What a link points at.
enum NexLinkKind { page, video, post, profile, repo, article, place, file }

/// A site people know: its name and colour, never its logo.
class _Brand {
  const _Brand(this.name, this.color);
  final String name;
  final int color;
}

const _brands = <String, _Brand>{
  'youtube.com': _Brand('YouTube', 0xFFE62117),
  'youtu.be': _Brand('YouTube', 0xFFE62117),
  'aparat.com': _Brand('Aparat', 0xFFDF0F50),
  'instagram.com': _Brand('Instagram', 0xFFD62976),
  't.me': _Brand('Telegram', 0xFF229ED9),
  'telegram.me': _Brand('Telegram', 0xFF229ED9),
  'x.com': _Brand('X', 0xFF1F2328),
  'twitter.com': _Brand('X', 0xFF1F2328),
  'github.com': _Brand('GitHub', 0xFF24292F),
  'wikipedia.org': _Brand('Wikipedia', 0xFF5A5C5F),
  'linkedin.com': _Brand('LinkedIn', 0xFF0A66C2),
  'digikala.com': _Brand('Digikala', 0xFFEF394E),
  'divar.ir': _Brand('Divar', 0xFFA62626),
  'snapp.ir': _Brand('Snapp', 0xFF00A651),
  'balad.ir': _Brand('Balad', 0xFF0F7EF0),
  'neshan.org': _Brand('Neshan', 0xFF2C7BE5),
  'spotify.com': _Brand('Spotify', 0xFF1DB954),
  'reddit.com': _Brand('Reddit', 0xFFFF4500),
  'medium.com': _Brand('Medium', 0xFF242424),
  'stackoverflow.com': _Brand('Stack Overflow', 0xFFF48024),
  'virgool.io': _Brand('Virgool', 0xFF2BB673),
  'zoomit.ir': _Brand('Zoomit', 0xFF1E88E5),
  'netlify.com': _Brand('Netlify', 0xFF00AD9F),
  'google.com': _Brand('Google', 0xFF4285F4),
};

const _fileEndings = {
  'pdf', 'zip', 'rar', '7z', 'apk', 'doc', 'docx', 'xls', 'xlsx', 'ppt',
  'pptx', 'mp3', 'mp4', 'mkv', 'csv', 'txt', 'epub', //
};

class NexLinkFace {
  const NexLinkFace({
    required this.host,
    required this.name,
    required this.kind,
    this.brandColor,
    this.title,
    this.youTubeId,
  });

  /// The address's host, without `www.`.
  final String host;

  /// The site as people call it: its name when it is one people know, the
  /// host otherwise.
  final String name;

  final NexLinkKind kind;

  /// The site's own colour (ARGB), when it is one people know.
  final int? brandColor;

  /// A title the address spells out; null when it does not.
  final String? title;

  /// The video's id, for a YouTube video.
  final String? youTubeId;

  static NexLinkFace of(String url) {
    final uri = Uri.tryParse(url.trim());
    final host = (uri?.host ?? '').toLowerCase().replaceFirst(
      RegExp(r'^(www|m|mobile)\.'),
      '',
    );
    if (uri == null || host.isEmpty) {
      return NexLinkFace(host: host, name: host, kind: NexLinkKind.page);
    }
    final brandKey = _brands.keys.firstWhere(
      (key) => host == key || host.endsWith('.$key'),
      orElse: () => '',
    );
    final brand = _brands[brandKey];
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    var kind = NexLinkKind.page;
    String? title;
    String? youTube;

    switch (brandKey) {
      case 'youtube.com' || 'youtu.be':
        youTube = _youTubeId(uri, host);
        kind = youTube != null
            ? NexLinkKind.video
            : segments.isNotEmpty && segments.first.startsWith('@')
            ? NexLinkKind.profile
            : NexLinkKind.page;
        if (kind == NexLinkKind.profile) title = segments.first;
      case 'aparat.com':
        if (segments.length >= 2 && segments.first == 'v') {
          kind = NexLinkKind.video;
        }
      case 'instagram.com':
        if (segments.isNotEmpty &&
            const {'p', 'reel', 'reels', 'tv'}.contains(segments.first)) {
          kind = segments.first == 'p' ? NexLinkKind.post : NexLinkKind.video;
        } else if (segments.length == 1) {
          kind = NexLinkKind.profile;
          title = '@${segments.first}';
        }
      case 't.me' || 'telegram.me':
        if (segments.isNotEmpty) {
          title = '@${segments.first}';
          kind = segments.length >= 2 ? NexLinkKind.post : NexLinkKind.profile;
        }
      case 'x.com' || 'twitter.com':
        if (segments.isNotEmpty) {
          title = '@${segments.first}';
          kind = segments.contains('status')
              ? NexLinkKind.post
              : NexLinkKind.profile;
        }
      case 'github.com':
        if (segments.length >= 2) {
          kind = NexLinkKind.repo;
          title = '${segments[0]}/${segments[1]}';
        } else if (segments.length == 1) {
          kind = NexLinkKind.profile;
          title = segments.first;
        }
      case 'wikipedia.org':
        if (segments.length >= 2 && segments.first == 'wiki') {
          kind = NexLinkKind.article;
          title = _words(segments[1], keepCase: true);
        }
      case 'balad.ir' || 'neshan.org':
        kind = NexLinkKind.place;
      case 'google.com':
        if (segments.isNotEmpty && segments.first == 'maps') {
          kind = NexLinkKind.place;
        }
    }
    if (host == 'maps.app.goo.gl' || host.startsWith('maps.google.')) {
      kind = NexLinkKind.place;
    }
    final last = segments.isEmpty ? '' : segments.last;
    final ending = last.contains('.') ? last.split('.').last.toLowerCase() : '';
    if (kind == NexLinkKind.page && _fileEndings.contains(ending)) {
      kind = NexLinkKind.file;
      title = _decode(last);
    }
    if (title == null && kind == NexLinkKind.page && brand == null) {
      title = _slugTitle(segments);
      if (title != null) kind = NexLinkKind.article;
    }
    return NexLinkFace(
      host: host,
      name: brand?.name ?? host,
      kind: kind,
      brandColor: brand?.color,
      title: title,
      youTubeId: youTube,
    );
  }

  static String? _youTubeId(Uri uri, String host) {
    final id = RegExp(r'^[A-Za-z0-9_-]{11}$');
    String? pick(String? value) =>
        value != null && id.hasMatch(value) ? value : null;
    if (host == 'youtu.be') {
      return pick(uri.pathSegments.isEmpty ? null : uri.pathSegments.first);
    }
    final segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'watch') {
      return pick(uri.queryParameters['v']);
    }
    if (segments.length >= 2 &&
        const {'shorts', 'live', 'embed', 'v'}.contains(segments.first)) {
      return pick(segments[1]);
    }
    return null;
  }

  /// A title out of an article's address: its last readable segment, words
  /// for dashes, without the number some sites put in front.
  static String? _slugTitle(List<String> segments) {
    for (final segment in segments.reversed) {
      final title = _words(segment);
      if (title != null) return title;
    }
    return null;
  }

  static String? _words(String segment, {bool keepCase = false}) {
    var text = _decode(
      segment,
    ).replaceFirst(RegExp(r'\.(html?|php|aspx?)$', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^\d+[-_]'), '');
    if (!RegExp(r'[-_+ ]').hasMatch(text) && !keepCase) return null;
    text = text
        .replaceAll(RegExp(r'[-_+]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = text.split(' ');
    // An id, not words: no letters, or a single run of hex.
    if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(text)) return null;
    if (words.length < 2 && !keepCase) return null;
    if (words.every((w) => RegExp(r'^[0-9a-f]{6,}$').hasMatch(w))) return null;
    if (text.length > 90) text = '${text.substring(0, 89)}…';
    if (keepCase || !RegExp(r'^[a-z]').hasMatch(text)) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  static String _decode(String text) {
    try {
      return Uri.decodeComponent(text);
    } catch (_) {
      return text;
    }
  }
}
