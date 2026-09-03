import 'dart:io';

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
  _FixedUpdateService(
    this._check, {
    required super.preferences,
    bool downloading = false,
    double? progress,
    Object? error,
  }) : _downloading = downloading,
       _progress = progress,
       _error = error;

  final UpdateCheck _check;
  final bool _downloading;
  final double? _progress;
  final Object? _error;

  /// How many times the screen asked for the transfer to be picked up.
  int ensureCalls = 0;

  @override
  UpdateCheck? get available => _check;

  @override
  UpdateCheck? get last => _check;

  @override
  bool get isDownloading => _downloading;

  @override
  double? get downloadProgress => _progress;

  @override
  Object? get downloadError => _error;

  @override
  Future<void> ensureDownloaded() async => ensureCalls++;
}

void main() {
  Future<void> pumpSheet(WidgetTester tester, UpdateService service) async {
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
  }

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

  testWidgets('the update screen offers one version, not a history', (
    tester,
  ) async {
    // It used to carry the whole bundled CHANGELOG under the offer. On a
    // screen whose question is "do you want this build", every release before
    // it is somebody else's question.
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    final service = _FixedUpdateService(
      UpdateCheck.available(
        version: NexVersion.tryParse(nexAppVersion)!,
        downloadUrl: 'https://example.invalid/Nex.apk',
        notes: '- the only change worth reading here',
      ),
      preferences: preferences,
    );
    addTearDown(service.dispose);

    await pumpSheet(tester, service);

    expect(find.text('the only change worth reading here'), findsOneWidget);
    expect(find.text('Changelog'), findsNothing);
  });

  testWidgets('opening on a download already running shows the download', (
    tester,
  ) async {
    // The screen never owned the transfer, but it read only "is there a file
    // yet" — so coming back to it mid-download put a Download button in front
    // of a download that was already running.
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    final service = _FixedUpdateService(
      UpdateCheck.available(
        version: NexVersion.tryParse(nexAppVersion)!,
        downloadUrl: 'https://example.invalid/Nex.apk',
      ),
      preferences: preferences,
      downloading: true,
      progress: 0.4,
    );
    addTearDown(service.dispose);

    await pumpSheet(tester, service);

    expect(find.text('Downloading…'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Download and install'), findsNothing);
  });

  testWidgets('a stopped download says so under its own bar, and resumes', (
    tester,
  ) async {
    // Not a full-page "could not reach the server" with a button that starts
    // the check again: the partial file is on disk, and what is on offer is
    // picking it up from there.
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    final service = _FixedUpdateService(
      UpdateCheck.available(
        version: NexVersion.tryParse(nexAppVersion)!,
        downloadUrl: 'https://example.invalid/Nex.apk',
      ),
      preferences: preferences,
      progress: 0.4,
      error: const SocketException('connection closed'),
    );
    addTearDown(service.dispose);

    await pumpSheet(tester, service);

    expect(find.text('Download stopped'), findsOneWidget);
    // The bar is still there, still showing where the transfer got to.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(service.ensureCalls, 1);
  });

  testWidgets('running out of space says that, not "it stopped"', (
    tester,
  ) async {
    // The one stop the user has to go and do something about.
    SharedPreferences.setMockInitialValues({});
    final preferences = await NexPreferences.load();
    final service = _FixedUpdateService(
      UpdateCheck.available(
        version: NexVersion.tryParse(nexAppVersion)!,
        downloadUrl: 'https://example.invalid/Nex.apk',
      ),
      preferences: preferences,
      progress: 0.9,
      error: const FileSystemException(
        'write failed',
        '',
        OSError('No space left on device', 28),
      ),
    );
    addTearDown(service.dispose);

    await pumpSheet(tester, service);

    expect(
      find.text('There is not enough free space to download the update.'),
      findsOneWidget,
    );
    expect(find.text('Download stopped'), findsNothing);
  });
}
