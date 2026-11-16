import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/security_tools/secret_math.dart';
import 'package:nex_client/modules/security_tools/link_math.dart';
import 'package:nex_client/modules/security_tools/account_model.dart';

void main() {
  test(
    'the full attributed EFF list has 7776 distinct entries in source order',
    () {
      expect(effWords.length, 7776);
      expect(effWords.toSet().length, 7776);
      expect(effWords.first, 'abacus');
      expect(effWords.last, 'zoom');
      expect(effWords, contains('felt-tip'));
      expect(() => effWords[0] = 'changed', throwsUnsupportedError);
    },
  );
  test('passphrases sample independent full-list indices with replacement', () {
    final bounds = <int>[];
    var i = 0;
    final phrase = makePassphrase(6, (max) {
      bounds.add(max);
      return i++;
    });
    expect(bounds, List.filled(6, 7776));
    expect(phrase.split(' '), effWords.take(6).toList());
    expect(makePassphrase(6, (_) => 0).split(' '), List.filled(6, 'abacus'));
    expect(() => makePassphrase(5, (_) => 0), throwsArgumentError);
  });
  test('passwords include chosen groups and exclude ambiguous characters', () {
    for (final n in [16, 24, 32, 48, 64]) {
      final options = SecretOptions(length: n);
      final text = makePassword(options, Random(n).nextInt);
      expect(text.length, n);
      expect(
        options.groups.every((g) => text.split('').any(g.contains)),
        isTrue,
      );
      expect(RegExp('[IlO01]').hasMatch(text), isFalse);
    }
  });
  test('single-group passwords are sampled without adding hidden character classes', () {
    const options = SecretOptions(
      length: 16,
      upper: false,
      digits: false,
      symbols: false,
    );
    expect(makePassword(options, (_) => 0), 'a' * 16);
  });
  test(
    'invalid options and failed entropy never fall back to another generator',
    () {
      expect(
        () => makePassword(
          const SecretOptions(
            upper: false,
            lower: false,
            digits: false,
            symbols: false,
          ),
          (_) => 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => makePassword(const SecretOptions(length: 4), (_) => 0),
        throwsArgumentError,
      );
      expect(
        () => makePassword(
          const SecretOptions(),
          (_) => throw UnsupportedError('unavailable'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => makePassphrase(6, (_) => throw UnsupportedError('unavailable')),
        throwsUnsupportedError,
      );
      expect(
        () => makePassword(const SecretOptions(), (_) => 0),
        throwsStateError,
      );
    },
  );
  test(
    'textual host inspection never mistakes userinfo or a path for the host',
    () {
      final r = LinkInspection.inspect(
        'https://bank.example@evil.test/bank.example',
        expected: 'bank.example',
      );
      expect(r.host, 'evil.test');
      expect(
        r.findings,
        containsAll([LinkFinding.credentials, LinkFinding.expectedMismatch]),
      );
    },
  );
  test(
    'exact expected-host comparison does not guess a registrable domain',
    () {
      final r = LinkInspection.inspect(
        'HTTPS://EXAMPLE.org:443/path?x=1',
        expected: 'example.org.',
      );
      expect(r.expectedMatch, true);
      expect(r.findings, isEmpty);
      expect(
        LinkInspection.inspect(
          'https://login.example.org',
          expected: 'example.org',
        ).expectedMatch,
        false,
      );
      expect(
        LinkInspection.inspect(
          'https://example.org.evil.test',
          expected: 'example.org',
        ).expectedMatch,
        false,
      );
    },
  );
  test('http, numeric host, nonstandard port, fragment and redirect hints are distinct', () {
    final r = LinkInspection.inspect(
      'http://127.0.0.1:8080/a?next=https%3A%2F%2Fexample.org#part',
    );
    expect(
      r.findings,
      containsAll([
        LinkFinding.http,
        LinkFinding.ipHost,
        LinkFinding.port,
        LinkFinding.redirectHint,
        LinkFinding.fragment,
      ]),
    );
    expect(
      LinkInspection.inspect('https://[::1]').findings,
      contains(LinkFinding.ipHost),
    );
  });
  test(
    'international, punycode and encoded authority are never silently blessed',
    () {
      expect(
        LinkInspection.inspect('https://xn--bcher-kva.example').findings,
        contains(LinkFinding.internationalHost),
      );
      expect(
        LinkInspection.inspect('https://раураl.com').findings,
        contains(LinkFinding.internationalHost),
      );
      expect(
        LinkInspection.inspect('https://%65xample.org').findings,
        contains(LinkFinding.encodedAuthority),
      );
    },
  );
  test('ambiguous controls, unsupported schemes and invalid expected hosts are rejected', () {
    for (final text in [
      'javascript:alert(1)',
      'data:text/html,test',
      'example.org',
      r'https://good.test\@evil.test',
      'https://good.test\nevil.test',
      'https://good.\u202Etest',
      'https://a..b',
      'https://.',
      'https://a.test:99999',
      'https://a.test/%zz',
      'https://a.test/%2',
    ]) {
      expect(
        () => LinkInspection.inspect(text),
        throwsFormatException,
        reason: 'invalid input rejected',
      );
    }
    expect(
      () => LinkInspection.inspect(
        'https://example.org',
        expected: 'https://example.org',
      ),
      throwsFormatException,
    );
    expect(
      () => LinkInspection.inspect(
        'https://example.org',
        expected: '*.example.org',
      ),
      throwsFormatException,
    );
    expect(
      () => LinkInspection.inspect('https://${'a' * 4096}'),
      throwsFormatException,
    );
  });
  test(
    'unknown and unavailable checklist answers do not become completed actions',
    () {
      final a = SecurityAccount('a', {
        'v': 1,
        'label': 'Email',
        'checks': {
          'unique': 'done',
          'mfa': 'future',
          'recovery': 'unavailable',
          'sessions': true,
        },
      });
      expect(a.valid, true);
      expect(a.done, 1);
      expect(a.state('mfa'), 'unknown');
      expect(a.next, 'mfa');
      expect(SecurityAccount('bad', {'checks': 42}).valid, false);
      expect(SecurityAccount('bad', {'checks': 42}).done, 0);
    },
  );
}
