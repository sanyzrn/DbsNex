import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/timeline_screen.dart';

import 'support/nex_harness.dart';

/// 2.1.6: with no name set, "What have you got, {name}?" came out as "What
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
    expect(nexUnnamedGreeting(en.greetingAfternoonB), "How's your day going?");
    // The slot in the middle of a phrase (2.4.0): the space before it goes.
    expect(nexUnnamedGreeting(fa.greetingMorningB), 'سلام، روزت قشنگ');
    expect(nexUnnamedGreeting(en.greetingNight), 'Still up?');
    expect(nexUnnamedGreeting(en.greetingMorning), 'Good morning');
    expect(nexUnnamedGreeting(fa.greetingNight), 'هنوز بیداری؟');
  });

  // 2.4.0: the greeting is in the app's language, whatever script the name
  // is written in — "صبحت بخیر، Saeed", not a whole English line in a
  // Persian app.
  for (final (language, name, script) in [
    ('fa', 'Saeed', r'[\u0600-\u06FF]'),
    ('en', 'سعید', r'[A-Za-z]{3}'),
  ]) {
    testWidgets('$language with the name "$name" greets in $language', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setLocale(language);
      await h.preferences.setDisplayName(name);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final line = find.textContaining(name);
      expect(line, findsWidgets);
      final text = (tester.widget<Text>(line.first)).data!;
      expect(text.replaceAll(name, ''), matches(RegExp(script)), reason: text);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
