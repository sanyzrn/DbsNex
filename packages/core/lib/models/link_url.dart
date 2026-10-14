/// Turns what someone actually pasted into something openable, or null.
///
/// The permissive half is deliberate: a share sheet, a chat app and a browser
/// address bar all hand over slightly different text for the same page, and
/// `example.com/x` is what a person types. Prefixing `https://` when there is
/// no scheme is the one guess worth making, because a link note that cannot be
/// opened is not a link note.
///
/// The strict half matters more. Only http and https survive: `javascript:`,
/// `data:` and `file:` are all things a URL launcher would happily act on, and
/// none of them are a bookmark. Anything with no host — `https://`, a bare
/// word, a sentence someone pasted by mistake — is not a URL either.
String? normaliseUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  // A pasted link often arrives wrapped by the app that sent it.
  if (text.startsWith('<') && text.endsWith('>')) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (text.contains(RegExp(r'\s'))) return null;

  final withScheme = text.contains('://') ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  // A host has to look like one: at least one dot, or localhost.
  if (!uri.host.contains('.') && uri.host != 'localhost') return null;
  return uri.toString();
}

/// A web address inside ordinary writing. Offsets refer to the original
/// text: recognising a link never rewrites the note or consumes punctuation.
typedef NexTextLink = ({int start, int end, String url});

final _textLinkPattern = RegExp(
  r'''(?<![\w@])(?:https?://|www\.)[^\s<>"\u200B-\u200F\u202A-\u202E\u2066-\u2069]+''',
  caseSensitive: false,
);

Iterable<NexTextLink> nexTextLinks(String text) sync* {
  for (final match in _textLinkPattern.allMatches(text)) {
    var address = match.group(0)!;
    while (address.isNotEmpty) {
      final last = address[address.length - 1];
      final opening = {')': '(', ']': '[', '}': '{'}[last];
      final unbalanced =
          opening != null &&
          last.allMatches(address).length > opening.allMatches(address).length;
      if (unbalanced || '.,!?;:،؛؟۔\u0027'.contains(last)) {
        address = address.substring(0, address.length - 1);
      } else {
        break;
      }
    }
    final url = normaliseUrl(address);
    if (url != null) {
      yield (start: match.start, end: match.start + address.length, url: url);
    }
  }
}

/// The part of a URL worth showing next to a title — `example.com`, not
/// `https://www.example.com/a/very/long/path?utm_source=...`.
///
/// `www.` goes because it is noise on every site that still uses it and tells
/// the reader nothing about which site they are looking at.
String? urlHost(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  final host = uri?.host;
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// The link a share carries, and any words around it, when the share is a
/// link — or null when it is ordinary text.
///
/// Chrome and most browsers share a page as plain text: the bare address, or
/// the page title and the address on two lines. Capturing that as a text note
/// lost the link's preview and its place among links. This recognises a
/// share with exactly one `http`/`https` address and at most a short line or
/// two of words around it; anything longer, or with several addresses, is
/// text that happens to contain a link and stays a text note.
///
/// The words are returned, not dropped: they become the link note's caption,
/// so nothing that was shared is lost.
({String url, String? words})? sharedLink(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 4096) return null;
  final matches = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  ).allMatches(trimmed).toList();
  if (matches.length != 1) return null;
  final match = matches.single;
  final url = normaliseUrl(match.group(0)!);
  if (url == null) return null;
  final words = trimmed.replaceRange(match.start, match.end, '').trim();
  if (words.length > 280 || '\n'.allMatches(words).length > 1) return null;
  return (url: url, words: words.isEmpty ? null : words);
}

/// What someone wrote in a link box, as a link: an address on its own —
/// with or without its scheme, the way people type one — or one address
/// with a short line around it, which becomes the link's caption (see
/// [sharedLink]). Null when it is neither.
({String url, String? words})? writtenLink(String text) {
  final bare = normaliseUrl(text);
  if (bare != null) return (url: bare, words: null);
  return sharedLink(text);
}
