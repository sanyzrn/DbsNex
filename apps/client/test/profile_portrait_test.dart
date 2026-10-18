import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/profile/profile_portrait.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// 2.1.7: the writing portrait at the foot of the profile. Locked with a
/// goal until there is enough to read, counted on the phone once there is,
/// and written by a model only when the person asks.
void main() {
  late NexTestHarness h;

  setUp(() async => h = await NexTestHarness.create(name: 'nex_portrait_'));
  tearDown(() => h.dispose());

  /// [count] notes, one day apart from today backwards when [spread].
  Future<void> seed(int count, {bool spread = true}) async {
    final now = DateTime.now();
    for (var i = 0; i < count; i++) {
      final note = (await h.db.captureText('note number $i'))!;
      if (spread) h.db.backdate(note.id, now.subtract(Duration(days: i % 10)));
    }
  }

  Future<AppLocalizations> show(
    WidgetTester tester, {
    String lang = 'en',
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePortrait(
              services: h.services,
              preferences: h.preferences,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(ProfilePortrait)));
  }

  testWidgets('locked with how far there is to go', (tester) async {
    await seed(12, spread: false);
    final l10n = await show(tester);
    expect(find.byKey(const ValueKey('profile-portrait-locked')), findsOne);
    expect(find.text('12/30'), findsOneWidget);
    expect(find.text(l10n.portraitLocked(18)), findsOneWidget);
    expect(find.text(l10n.portraitLockedDays(6)), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-portrait-counted')),
      findsNothing,
    );
  });

  testWidgets('the counted half needs no AI; the button says it needs one', (
    tester,
  ) async {
    await seed(30);
    final l10n = await show(tester);
    expect(find.byKey(const ValueKey('profile-portrait-counted')), findsOne);
    expect(find.text(l10n.portraitRhythm), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text(l10n.portraitNeedsAi), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-portrait-write')), findsNothing);
  });

  testWidgets('with a provider, asking says what goes and a failure is said', (
    tester,
  ) async {
    await seed(30);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    final l10n = await show(tester, lang: 'fa');
    expect(find.text(l10n.portraitPrivacy('۸۰')), findsOneWidget);
    expect(find.text('۳۰'), findsOneWidget);
    // flutter_test answers every request with a 400.
    await tester.tap(find.byKey(const ValueKey('profile-portrait-write')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.portraitFailed), findsOneWidget);
    expect(h.preferences.profilePortrait, isNull);
  });

  testWidgets('a kept portrait is shown with its traits and suggestion', (
    tester,
  ) async {
    await seed(30);
    await h.preferences.setProfilePortrait(
      NexPortrait(
        headline: 'A quiet planner',
        portrait: 'You write things down before they can slip.',
        traits: const [
          NexPortraitTrait(name: 'Organised', score: 82, line: 'Lists.'),
          NexPortraitTrait(name: 'Curious', score: 64, line: 'Links.'),
          NexPortraitTrait(name: 'Steady', score: 71, line: 'Every day.'),
        ],
        strengths: const ['Follows through'],
        invitation: 'Try a weekly look back.',
        writtenAt: DateTime.utc(2026, 10, 1),
        basedOn: 30,
      ),
    );
    final l10n = await show(tester);
    expect(find.byKey(const ValueKey('profile-portrait-written')), findsOne);
    expect(find.text('A quiet planner'), findsOneWidget);
    expect(find.text('Organised'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Follows through'), findsOneWidget);
    expect(find.text('Try a weekly look back.'), findsOneWidget);
    expect(find.text(l10n.portraitDisclaimer), findsOneWidget);
    // No provider: nothing to rewrite with.
    expect(
      find.byKey(const ValueKey('profile-portrait-rewrite')),
      findsNothing,
    );
  });
}
