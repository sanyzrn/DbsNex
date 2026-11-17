enum LinkFinding {
  http,
  credentials,
  internationalHost,
  ipHost,
  port,
  encodedAuthority,
  redirectHint,
  fragment,
  expectedMismatch,
}

class LinkInspection {
  LinkInspection._(this.host, this.scheme, this.findings, this.expectedMatch);
  final String host, scheme;
  final List<LinkFinding> findings;
  final bool? expectedMatch;

  /// Conservative textual inspection, not a browser parser or reputation scan.
  static LinkInspection inspect(String input, {String expected = ''}) {
    final text = input.trim();
    if (text.isEmpty ||
        text.length > 4096 ||
        RegExp(
          r'[\x00-\x1f\x7f\u061c\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff\\]',
        ).hasMatch(input) ||
        RegExp(r'\s').hasMatch(text)) {
      throw const FormatException('ambiguous input');
    }
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(text)) {
      throw const FormatException('invalid percent escape');
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        !text.toLowerCase().startsWith('${uri.scheme.toLowerCase()}://') ||
        uri.host.isEmpty) {
      throw const FormatException('explicit web URL required');
    }
    final authority = text
        .substring(text.indexOf('://') + 3)
        .split(RegExp(r'[/\?#]'))
        .first;
    final host = uri.host.toLowerCase();
    if (host.isEmpty ||
        host == '.' ||
        host.startsWith('.') ||
        host.contains('..') ||
        (uri.hasPort && (uri.port < 0 || uri.port > 65535)) ||
        host.contains(RegExp(r'[\s/@\\]'))) {
      throw const FormatException('invalid host');
    }
    final wanted = expected.trim().toLowerCase();
    final hostPattern = RegExp(
      r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\.?$',
    );
    if (wanted.isNotEmpty &&
        (wanted.length > 253 || !hostPattern.hasMatch(wanted))) {
      throw const FormatException('expected host must be an ASCII domain');
    }
    String canonical(String h) =>
        h.endsWith('.') ? h.substring(0, h.length - 1) : h;
    final match = wanted.isEmpty ? null : canonical(host) == canonical(wanted);
    // Intentionally do not guess a registrable domain without a public suffix list.
    final findings = <LinkFinding>[
      if (uri.scheme == 'http') LinkFinding.http,
      if (authority.contains('@')) LinkFinding.credentials,
      if (host.split('.').any((label) => label.startsWith('xn--')) ||
          RegExp(r'[^\x00-\x7f]').hasMatch(Uri.decodeComponent(host)))
        LinkFinding.internationalHost,
      if (host.contains(':') ||
          RegExp(r'^(?:[0-9.]+|0x[0-9a-f]+)$').hasMatch(host))
        LinkFinding.ipHost,
      if (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))
        LinkFinding.port,
      if (authority.contains('%')) LinkFinding.encodedAuthority,
      if (uri.queryParameters.keys.any(
        (k) => const {
          'url',
          'next',
          'redirect',
          'redirect_uri',
          'redirect_url',
          'target',
          'continue',
          'return',
          'returnurl',
        }.contains(k.toLowerCase()),
      ))
        LinkFinding.redirectHint,
      if (uri.hasFragment) LinkFinding.fragment,
      if (match == false) LinkFinding.expectedMismatch,
    ];
    return LinkInspection._(host, uri.scheme, findings, match);
  }
}
