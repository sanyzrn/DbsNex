import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Persian catalogue against the two ways it rotted before:
/// a key added to the template and never translated, and a key "translated"
/// by pasting the English string back in.
void main() {
  Map<String, String> load(String path) {
    final decoded =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        // `@@locale` is metadata and `@key` blocks are per-message metadata.
        if (!entry.key.startsWith('@')) entry.key: entry.value as String,
    };
  }

  final en = load('lib/l10n/app_en.arb');
  final fa = load('lib/l10n/app_fa.arb');

  // Identical in both locales on purpose: the product name, and URLs, which
  // are not words in any language.
  const untranslatable = {'appTitle', 'syncServerHint', 'sendFeedbackSubtitle'};

  test('every English message has a Persian one', () {
    expect(en.keys.toSet().difference(fa.keys.toSet()), isEmpty);
  });

  test('Persian carries no messages the template dropped', () {
    expect(fa.keys.toSet().difference(en.keys.toSet()), isEmpty);
  });

  test('no Persian message is just the English string', () {
    final untranslated = [
      for (final key in en.keys)
        if (!untranslatable.contains(key) && fa[key] == en[key]) key,
    ];
    expect(untranslated, isEmpty);
  });

  test('Persian keeps every placeholder the English message declares', () {
    // The `@key` metadata is authoritative about which names are placeholders.
    // Scraping `{…}` out of the message itself cannot tell a placeholder from
    // an ICU plural or select branch.
    final template =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final key in en.keys) {
      final meta = template['@$key'];
      if (meta is! Map<String, dynamic>) continue;
      final declared = meta['placeholders'];
      if (declared is! Map<String, dynamic>) continue;
      for (final name in declared.keys) {
        expect(
          fa[key],
          contains('{$name'),
          reason: '$key drops the "$name" placeholder in Persian',
        );
      }
    }
  });
}
