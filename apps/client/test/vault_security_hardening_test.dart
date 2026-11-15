import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/app_lock.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/private_clipboard.dart';
import 'package:nex_client/platform/vault_files.dart';
import 'package:nex_client/platform/vault_session.dart';
import 'package:nex_client/platform/vault_store.dart';
import 'package:nex_client/screens/vault_screen.dart';
import 'package:nex_client/widgets/photo_viewer.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// flutter_test registers no plugin for the directories VaultFiles asks
/// for; without this, decrypting an attachment would hit a platform
/// channel that does not exist here.
class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// `Isolate.run` in a widget test's fake-async zone never delivers its
/// reply, so the screen takes its files the way it takes its store and its
/// authentication: injectable. This one answers from memory — what the
/// screen's security behaviour needs is a photo that decrypts, not the
/// encryption itself, which the plain tests below cover against the real
/// thing.
class _TestFiles extends VaultFiles {
  final Map<String, Uint8List> _sealed = {};

  @override
  Future<String> put(Uint8List bytes) async {
    final id = const Uuid().v4();
    _sealed[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List> get(String id) async {
    final bytes = _sealed[id];
    if (bytes == null) {
      throw const FileSystemException('No such attachment');
    }
    return bytes;
  }
}

/// The security fixes this file stands guard over: the vault honouring the
/// "Biometrics only" preference (SEC-01), routes that show decrypted content
/// being veiled and closed with the unlock (SEC-02), one key for concurrent
/// first writes (SEC-03), decrypted photos leaving the image cache with the
/// screen that showed them (SEC-04), a copied secret wiped when the vault
/// hides (SEC-05), the grace period bounded (SEC-06), and a cancelled prompt
/// not presented as a failure (SEC-07).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nex/os_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// A 120×120 PNG: a decodable image with a surface big enough to tap,
  /// because what the cache test looks at is the image cache, and only a
  /// decodable image ever enters it.
  final png = Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    120,
    0,
    0,
    0,
    120,
    8,
    2,
    0,
    0,
    0,
    182,
    6,
    161,
    133,
    0,
    0,
    0,
    234,
    73,
    68,
    65,
    84,
    120,
    156,
    237,
    208,
    1,
    9,
    0,
    32,
    0,
    192,
    48,
    243,
    24,
    213,
    210,
    218,
    66,
    225,
    14,
    30,
    224,
    108,
    204,
    181,
    117,
    161,
    241,
    252,
    224,
    147,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    129,
    6,
    221,
    10,
    52,
    232,
    86,
    160,
    65,
    183,
    2,
    13,
    186,
    21,
    104,
    208,
    173,
    64,
    131,
    110,
    5,
    26,
    116,
    43,
    208,
    160,
    91,
    29,
    115,
    207,
    154,
    82,
    118,
    156,
    129,
    145,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);

  late Directory tmp;
  late _Paths paths;

  setUp(() {
    VaultSession.instance
      ..close()
      ..clock = DateTime.now;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_vault_hardening_');
    paths = _Paths(tmp.path);
    PathProviderPlatform.instance = paths;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  VaultEntry photoMessage(String id) => VaultEntry(
    id: 'photo-message',
    kind: VaultKind.message,
    fields: {
      'text': 'the receipt',
      'file': id,
      'fileKind': 'photo',
      'fileName': 'photo.png',
    },
    updatedAt: DateTime.utc(2026),
  );

  group('the attachment key (SEC-03)', () {
    test('concurrent first writes share one key', () async {
      // Four tools sealing an attachment in the same instant, on a fresh
      // install: each used to read "no key", each made one, and the last
      // write won — the others' files were noise from then on, locked
      // under a key nobody held. One shared flight makes them all readers
      // of the first key.
      final files = [
        for (var i = 0; i < 4; i++) VaultFiles(root: () async => tmp),
      ];
      final ids = await Future.wait([
        for (final f in files) f.put(Uint8List.fromList(png)),
      ]);
      for (final id in ids) {
        expect(await files.first.get(id), png, reason: 'attachment $id');
      }
    });
  });

  group("the lock's grace (SEC-06)", () {
    test('a restored value outside the offered range falls back', () async {
      SharedPreferences.setMockInitialValues({
        'security.lock_grace_seconds': 1 << 30,
      });
      final preferences = await NexPreferences.load();
      // 2^30 seconds is 34 years: kept as written, "lock after a minute"
      // would have read as "never lock", with nothing on screen any the
      // wiser.
      expect(preferences.appLockGraceSeconds, 60);
    });

    test('a value the screen offers stands', () async {
      SharedPreferences.setMockInitialValues({
        'security.lock_grace_seconds': 300,
      });
      final preferences = await NexPreferences.load();
      expect(preferences.appLockGraceSeconds, 300);
    });
  });

  group('copies and the session (SEC-02)', () {
    test('ending the unlock clears the plain copies it made', () async {
      VaultFiles.followSession(VaultSession.instance);
      final files = VaultFiles(root: () async => tmp);
      final id = await files.put(Uint8List.fromList(png));
      VaultSession.instance.open();
      final copy = await files.openCopy(id, 'photo.png');
      expect(copy.existsSync(), isTrue);
      VaultSession.instance.close();
      // The copy a private tool left in the cache does not outlive the
      // unlock that decrypted it — however that unlock ended.
      // Draining the event queue does not wait for real filesystem I/O.
      // Observe the listener's cleanup, without calling it ourselves; a
      // missing or broken listener must still fail this test.
      const cleanupTimeout = Duration(seconds: 5);
      final waiting = Stopwatch()..start();
      while (await copy.exists() && waiting.elapsed < cleanupTimeout) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        await copy.exists(),
        isFalse,
        reason: 'Closing the vault must remove its decrypted temporary copy',
      );
    });
  });

  group('the private clipboard (SEC-05)', () {
    // The clipboard the desktop fallback writes to, as a box the mocks
    // behind it can read and set.
    String? held;
    setUp(() {
      held = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                held = (call.arguments as Map)['text'] as String?;
              case 'Clipboard.getData':
                return held == null ? null : {'text': held};
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('hiding the vault wipes a copy still outstanding', (
      tester,
    ) async {
      await PrivateClipboard.copy('the-password');
      expect(held, 'the-password');
      await PrivateClipboard.sweepNow();
      // The 30-second timer was the only thing that wiped a desktop copy,
      // and it waited its full time even after the vault had hidden
      // everything else.
      expect(held, '');
    });

    testWidgets('a copy the user made since is never touched', (tester) async {
      await PrivateClipboard.copy('the-password');
      await Clipboard.setData(const ClipboardData(text: 'their-own-note'));
      await PrivateClipboard.sweepNow();
      expect(held, 'their-own-note');
    });
  });

  group('the vault screen', () {
    Widget app(
      AppLockService auth, {
      VaultKind kind = VaultKind.password,
      bool biometricOnly = false,
      VaultFiles? files,
    }) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: VaultScreen(
        kind: kind,
        authentication: auth,
        biometricOnly: biometricOnly,
        files: files,
      ),
    );

    /// Unlocks the vault and opens the decrypted photo of `photoMessage`
    /// full screen, the way a person does: tap Unlock, tap the photo.
    Future<Uint8List> openPhotoMessage(WidgetTester tester) async {
      // A taller surface: the messages list is reverse-scrolled and the
      // photo bubble must be on it for the tap to land.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final files = _TestFiles();
      final id = await files.put(png);
      await VaultStore().save(photoMessage(id));
      final auth = _RecordingAuth();
      await tester.pumpWidget(app(auth, kind: VaultKind.message, files: files));
      await tester.tap(find.text('Unlock vault'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      // The bubble's photo is an `Image.memory` that a widget test never
      // decodes, so it lays out at no size and a tap lands on nothing. Its
      // tap handler is what a person's tap runs, so the test runs it.
      final open = find.ancestor(
        of: find.byType(Image),
        matching: find.byType(GestureDetector),
      );
      expect(open, findsWidgets, reason: 'the photo bubble is on screen');
      tester.widget<GestureDetector>(open.first).onTap!();
      await tester.pumpAndSettle();
      // Every case below is about a photo that is really open.
      expect(find.byType(NexPhotoViewer), findsOneWidget);
      return png;
    }

    /// Leaves the app with the vault open and comes back after its unlock
    /// has lapsed — the real way a vault locks under an open photo: the
    /// lock button is under the photo, out of reach.
    Future<void> lapse(WidgetTester tester) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      final later = DateTime.now().add(const Duration(hours: 1));
      VaultSession.instance.clock = () => later;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('honours the Biometrics-only preference (SEC-01)', (
      tester,
    ) async {
      final auth = _RecordingAuth();
      await tester.pumpWidget(app(auth, biometricOnly: true));
      await tester.tap(find.text('Unlock vault'));
      await tester.pumpAndSettle();
      // The Security screen's switch says the device's PIN may never open
      // what is private; the vault used to hand the prompt the opposite
      // answer, always.
      expect(auth.biometricOnly, [true]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('a cancelled prompt is not an error (SEC-07)', (tester) async {
      final auth = _RefusingAuth();
      await tester.pumpWidget(app(auth));
      await tester.tap(find.text('Unlock vault'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Unlock was not completed. Set up a screen lock if needed, then try again.',
        ),
        findsNothing,
      );
      expect(find.text('Unlock vault'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('a real refusal from the phone is said (SEC-07)', (
      tester,
    ) async {
      final auth = _RefusingAuth(failure: NexAuthFailure.lockedOut);
      await tester.pumpWidget(app(auth));
      await tester.tap(find.text('Unlock vault'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Unlock was not completed. Set up a screen lock if needed, then try again.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets(
      'locking closes a decrypted photo that was open full screen (SEC-02)',
      (tester) async {
        await openPhotoMessage(tester);
        expect(find.byType(NexPhotoViewer), findsOneWidget);

        // The lock button on the app bar. Before SEC-02, the photo route
        // stayed above the locked screen: a resumed app opened onto the
        // decrypted photo, no prompt asked.
        await lapse(tester);
        expect(find.byType(NexPhotoViewer), findsNothing);
        expect(find.text('the receipt'), findsNothing);
        expect(find.text('Your vault is locked'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      'the veil covers a decrypted photo pushed above the screen (SEC-02)',
      (tester) async {
        await openPhotoMessage(tester);

        // The shade, the switcher's glance: `inactive` covers. The veil
        // used to be part of the vault screen's own tree, beneath the
        // route — the photo was hit-testable straight through it.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vault-veil')), findsOneWidget);
        expect(find.byType(NexPhotoViewer).hitTestable(), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      'a decrypted photo leaves the image cache with its screen (SEC-04)',
      (tester) async {
        await openPhotoMessage(tester);

        final image = tester.widget<Image>(find.byType(Image).first);
        final provider = image.image;
        expect(
          PaintingBinding.instance.imageCache.containsKey(provider),
          isTrue,
          reason: 'the decrypted photo should be cached while shown',
        );

        // Locking empties the list; the cache used to keep both the bytes
        // and the decoded image for as long as it had room.
        await lapse(tester);
        expect(
          PaintingBinding.instance.imageCache.containsKey(provider),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  });
}

/// Answers for the phone, and remembers what the vault asked of it.
class _RecordingAuth extends AppLockService {
  final List<bool> biometricOnly = [];

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    this.biometricOnly.add(biometricOnly);
    return true;
  }
}

/// The phone saying no — with or without a reason to show.
class _RefusingAuth extends AppLockService {
  _RefusingAuth({this.failure});
  final NexAuthFailure? failure;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    lastFailure = failure;
    return false;
  }
}
