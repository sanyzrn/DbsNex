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
