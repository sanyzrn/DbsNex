import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/display_date.dart';
import 'package:nex_client/platform/profile_photo.dart';
import 'package:nex_client/screens/profile/profile_header.dart';
import 'package:nex_client/screens/profile_screen.dart';

import 'support/nex_harness.dart';

void main() {
  group('the next birthday', () {
    test('counts down to the day and turns a year older on it', () {
      final born = DateTime(2000, 3, 10);
      expect(profileBirthdayInfo(born, DateTime(2026, 3, 9), solar: false), (
        age: 25,
        daysUntil: 1,
      ));
      expect(
        profileBirthdayInfo(born, DateTime(2026, 3, 10, 18), solar: false),
        (age: 26, daysUntil: 0),
      );
      expect(profileBirthdayInfo(born, DateTime(2026, 3, 11), solar: false), (
        age: 26,
        daysUntil: 364,
      ));
    });

    test('29 February comes round on the 28th in other years', () {
      expect(
        profileBirthdayInfo(
          DateTime(2004, 2, 29),
          DateTime(2027, 2, 27),
          solar: false,
        ),
        (age: 22, daysUntil: 1),
      );
    });

    test('a Persian birthday comes round on its Persian day', () {
      final born = nexGregorianDate(1370, 1, 1);
      final eve = nexGregorianDate(
        1405,
        1,
        1,
      ).subtract(const Duration(days: 1));
      expect(profileBirthdayInfo(born, eve, solar: true), (
        age: 34,
        daysUntil: 1,
      ));
    });
  });

  group('the page', () {
    late NexTestHarness harness;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_profile_');
    });

    tearDown(() => harness.dispose());

    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfileScreen(
            services: harness.services,
            preferences: harness.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the header shows the name while it is typed', (tester) async {
      await show(tester);
      expect(
        find.descendant(
          of: find.byType(ProfileHeader),
          matching: find.text('Your name'),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Sara Rahimi');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ProfileHeader),
          matching: find.text('Sara Rahimi'),
        ),
        findsOneWidget,
      );
      // No picture: the initials stand in for one.
      expect(find.text('S‌R'), findsOneWidget);
    });

    testWidgets('the photo goes only from its own menu', (tester) async {
      final path = nextProfilePhotoPath(harness.services.mediaDir, '.png');
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      await harness.preferences.setProfilePhotoPath(path);
      await show(tester);

      // A tap beside the picture, where the full-width Remove button used
      // to reach, does nothing.
      final avatar = tester.getRect(find.byTooltip('Change profile photo'));
      await tester.tapAt(avatar.centerRight + const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(find.text('Remove photo'), findsNothing);
      expect(harness.preferences.profilePhotoPath, path);

      await tester.tap(find.byTooltip('Change profile photo'));
      await tester.pumpAndSettle();
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Take a photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-photo-remove')));
      await tester.pumpAndSettle();
      expect(harness.preferences.profilePhotoPath, isNull);
      expect(File(path).existsSync(), isFalse);
    });
  });
}
