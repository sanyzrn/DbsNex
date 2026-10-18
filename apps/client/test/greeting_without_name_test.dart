import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/timeline_screen.dart';

/// 2.1.7: with no name set, "What have you got, {name}?" came out as "What
/// have you got, ?" — only a comma at the very end used to be taken off.
void main() {
  for (final language in ['en', 'fa']) {
    test('$language: every greeting reads whole without a name', () async {
      final l10n = await AppLocalizations.delegate.load(Locale(language));
      final phrases = <String Function(String)>[
        l10n.greetingMorning,
        l10n.greetingMorningB,
        l10n.greetingMorningC,
        l10n.greetingAfternoon,
        l10n.greetingAfternoonB,
        l10n.greetingAfternoonC,
        l10n.greetingEvening,
        l10n.greetingEveningB,
        l10n.greetingEveningC,
        l10n.greetingNight,
        l10n.greetingNightB,
        l10n.greetingNightC,
      ];
      for (final phrase in phrases) {
        final text = nexUnnamedGreeting(phrase);
        expect(text, isNot(contains('\u0000')));
        expect(text, isNot(matches(RegExp(r'[,،]\s*[?؟]?$'))), reason: text);
        expect(text, isNot(endsWith(' ')));
        expect(text, isNotEmpty);
      }
    });
  }

  test('the slot and its comma go, the question mark stays', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final fa = await AppLocalizations.delegate.load(const Locale('fa'));
    expect(nexUnnamedGreeting(en.greetingAfternoonC), 'What have you got?');
    expect(nexUnnamedGreeting(en.greetingNight), 'Still up?');
    expect(nexUnnamedGreeting(en.greetingMorning), 'Good morning');
    expect(nexUnnamedGreeting(fa.greetingNight), 'هنوز بیداری؟');
  });
}
