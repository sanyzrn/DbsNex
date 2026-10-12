import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/profile/profile_constellation.dart';
import 'package:nex_client/screens/profile/profile_header.dart';

/// The sky behind the profile's name is drawn across the whole header, from
/// the name, and moves only when animations may.
void main() {
  Widget header(String name, {bool still = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: still),
      child: child!,
    ),
    home: Scaffold(
      body: SizedBox(
        width: 400,
        child: ProfileHeader(
          photo: null,
          name: name,
          bio: 'graphic designer',
          birthdayLine: null,
          onPhoto: () {},
        ),
      ),
    ),
  );

  Finder sky() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ConstellationPainter,
  );

  testWidgets('the sky fills the header, not one point in its middle', (
    tester,
  ) async {
    await tester.pumpWidget(header('Saeed'));
    await tester.pumpAndSettle();
    final painted = tester.getSize(sky());
    final whole = tester.getSize(find.byType(ProfileHeader));
    expect(painted, whole);
    expect(painted.width, greaterThan(300));
  });

  testWidgets('every letter is a star, within bounds', (tester) async {
    expect(ProfileConstellation.starsFor(''), 10);
    expect(ProfileConstellation.starsFor('Saeed'), 13);
    expect(ProfileConstellation.starsFor('سعید'), 12);
    expect(ProfileConstellation.starsFor('a very very long name indeed'), 24);
    expect(
      ProfileConstellation.seedOf('Saeed'),
      ProfileConstellation.seedOf('Saeed'),
    );
    expect(
      ProfileConstellation.seedOf('Saeed'),
      isNot(ProfileConstellation.seedOf('Sara')),
    );
  });

  testWidgets('it moves when it may, and holds still when animations are off', (
    tester,
  ) async {
    ProfileConstellation.enabled = true;
    addTearDown(() => ProfileConstellation.enabled = false);
    await tester.pumpWidget(header('Saeed'));
    final painter =
        tester.widget<CustomPaint>(sky()).painter! as ConstellationPainter;
    final before = painter.sky.value;
    await tester.pump(const Duration(seconds: 2));
    expect(painter.sky.value, isNot(before));

    await tester.pumpWidget(header('Saeed', still: true));
    await tester.pump();
    final quiet =
        tester.widget<CustomPaint>(sky()).painter! as ConstellationPainter;
    expect(quiet.sky.value, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(quiet.sky.value, 0);
    // The repeating sky is gone, so the test can end.
    await tester.pumpWidget(const SizedBox());
  });
}
