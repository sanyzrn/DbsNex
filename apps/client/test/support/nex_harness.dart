import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'in_process_db.dart';

/// The whole service graph a test needs, assembled once (W4.3).
///
/// Every widget test used to build this by hand: a temp directory, the media
/// and backup folders, mock preferences, an [InProcessDb], `forTest` with
/// seven arguments, onboarding marked done, and a teardown that remembered to
/// dispose and delete — thirty-odd copies that drifted apart one argument at a
/// time. This is that setup, once.
///
/// ```dart
/// late NexTestHarness h;
/// setUp(() async => h = await NexTestHarness.create());
/// tearDown(() => h.dispose());
/// ```
///
/// or, inside a single test, [pumpNexApp].
class NexTestHarness {
  NexTestHarness._({
    required this.root,
    required this.db,
    required this.preferences,
    required this.services,
  });

  /// Builds a fresh library in its own temp directory.
  ///
  /// [preferences] seeds SharedPreferences; [onboarded] marks onboarding and
  /// the first-run tour done, which is what almost every test wants — the
  /// onboarding tests say `false`. [readDelay], [captureDelay] and [adapter]
  /// go to the [InProcessDb]; [mediaPicker] to the services.
  static Future<NexTestHarness> create({
    String name = 'nex_test_',
    Map<String, Object> preferences = const {},
    bool onboarded = true,
    Duration? readDelay,
    Duration? captureDelay,
    AIAdapter? adapter,
    MediaPicker? mediaPicker,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final root = Directory.systemTemp.createTempSync(name);
    final dbPath = p.join(root.path, 'nex.sqlite');
    Directory(p.join(root.path, 'media')).createSync(recursive: true);
    Directory(p.join(root.path, 'backups')).createSync(recursive: true);
    final db = InProcessDb(
      dbPath: dbPath,
      deviceId: 'test',
      readDelay: readDelay,
      captureDelay: captureDelay,
      adapter: adapter,
    );
    final prefs = await NexPreferences.load();
    final services = NexServices.forTest(
      worker: db,
      deviceId: 'test',
      preferences: prefs,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      mediaPicker: mediaPicker,
      dbPath: dbPath,
      mediaDir: p.join(root.path, 'media'),
      backupDir: p.join(root.path, 'backups'),
    );
    if (onboarded) {
      await prefs.completeOnboarding();
      await prefs.completeTour();
    }
    return NexTestHarness._(
      root: root,
      db: db,
      preferences: prefs,
      services: services,
    );
  }

  final Directory root;
  final InProcessDb db;
  final NexPreferences preferences;
  final NexServices services;

  String get dbPath => p.join(root.path, 'nex.sqlite');
  String get mediaDir => p.join(root.path, 'media');
  String get backupDir => p.join(root.path, 'backups');

  /// The app itself, over this library.
  Widget app() => NexApp(services: services, preferences: preferences);

  bool _disposed = false;

  /// Hides any capsule still showing, closes the library and deletes it.
  /// Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    nexHideBanner();
    await services.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// Builds a [NexTestHarness], pumps the app over it and settles.
///
/// Torn down with the test. Screen size and text scale are the test's own
/// business; this only puts the app on screen.
Future<NexTestHarness> pumpNexApp(
  WidgetTester tester, {
  String name = 'nex_test_',
  Map<String, Object> preferences = const {},
  bool onboarded = true,
  Duration? readDelay,
  Duration? captureDelay,
  AIAdapter? adapter,
  bool settle = true,
}) async {
  final harness = await NexTestHarness.create(
    name: name,
    preferences: preferences,
    onboarded: onboarded,
    readDelay: readDelay,
    captureDelay: captureDelay,
    adapter: adapter,
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app());
  if (settle) await tester.pumpAndSettle();
  return harness;
}
