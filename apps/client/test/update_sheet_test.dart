import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app_version.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_update.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/update_service.dart';
import 'package:nex_client/screens/update_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reports a fixed [UpdateCheck] without ever touching the network, a
/// platform channel, or a Timer — [UpdateService] itself always drives its
/// `available`/`downloaded` state through a real HTTP check and a real
/// download, and standing those up (even against a [http.testing.MockClient])
/// pulled in enough machinery that this test hung indefinitely rather than
/// exercising what it actually cares about: how [UpdateSheet] renders notes
/// it already has.
class _FixedUpdateService extends UpdateService {
  _FixedUpdateService(this._check, {required super.preferences});

  final UpdateCheck _check;

  @override
  UpdateCheck? get available => _check;

  @override
  UpdateCheck? get last => _check;
}

void main() {
  testWidgets(
    'CHANGELOG bullets render as a real list, not one run-on paragraph',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await NexPreferences.load();
      final service = _FixedUpdateService(
        UpdateCheck.available(
          version: NexVersion.tryParse(nexAppVersion)!,
          downloadUrl: 'https://example.invalid/Nex.apk',
          notes: '- first change\n- second change\n- third change',
        ),
        preferences: preferences,
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdateSheet(haptics: false, service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('first change'), findsOneWidget);
      expect(find.text('second change'), findsOneWidget);
      expect(find.text('third change'), findsOneWidget);
      // The raw markdown dash must not leak into the rendered text.
      expect(find.textContaining('- first change'), findsNothing);
    },
  );

  testWidgets(
    'the changelog link is there whether or not an update is pending',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await NexPreferences.load();
      final service = _FixedUpdateService(
        const UpdateCheck.upToDate(),
        preferences: preferences,
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdateSheet(haptics: false, service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "What have I missed" is a fair question even when there is nothing
      // new to install right now.
      expect(find.text('See what changed in past versions'), findsOneWidget);
    },
  );
}
