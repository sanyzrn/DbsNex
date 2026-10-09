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

  // Identical in both locales on purpose: the product name — including where
  // it stands in for a name Nex does not have, as the daily notification's
  // title does — and URLs, which are not words in any language.
  // Not a translation gap. Each of these is the same string in both
  // catalogues on purpose: a product name, a URL placeholder, a greeting that
  // is the app's own name, or — for `remindRepeatingAt` — a pure layout
  // template whose only content is the two values it joins. `vaultCvv2` is
  // the code as banks print it on Iranian cards too.
  const untranslatable = {
    'appTitle',
    'syncServerHint',
    'nudgeGreetingPlain',
    'remindRepeatingAt',
    'vaultCvv2',
  };

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

  test('no new screen names things outside the catalogue (UX-05)', () {
    // `nexLabel` inlines both languages at the call, past the reviewed .arb
    // vocabulary. The files that already use it may keep it until they are
    // next touched; a new file reaches for AppLocalizations instead.
    const allowed = {
      'lib/platform/hold_menu.dart',
      'lib/platform/theme_presets.dart',
      'lib/screens/about_screen.dart',
      'lib/screens/ai_provider_screen.dart',
      'lib/screens/brief_screen.dart',
      'lib/screens/cycle/cycle_calendar.dart',
      'lib/screens/settings/settings_appearance.dart',
      'lib/screens/settings/settings_gestures.dart',
      'lib/screens/settings/settings_search.dart',
      'lib/screens/settings_sheet.dart',
      'lib/screens/tools_screen.dart',
      'lib/screens/vault/vault_items.dart',
      'lib/screens/vault/vault_pages.dart',
      'lib/screens/vault_editor.dart',
      'lib/screens/vault_screen.dart',
      'lib/widgets/commitments/commitment_editor.dart',
      'lib/widgets/commitments/commitment_rows.dart',
      'lib/widgets/commitments_sheet.dart',
      'lib/widgets/feature_label.dart',
      'lib/widgets/feedback_sheet.dart',
      'lib/widgets/folded_note.dart',
      'lib/widgets/recurring_attachments.dart',
      'lib/widgets/recurring_calendar.dart',
      'lib/widgets/recurring_options.dart',
    };
    final using = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('nexLabel('))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(
      using.where((path) => !allowed.contains(path)),
      isEmpty,
      reason: 'put the words in app_en.arb and app_fa.arb instead',
    );
  });
}
