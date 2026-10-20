import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/in_process_db.dart';
import '../../support/nex_harness.dart';
import '../../support/add_button.dart';

/// How the parking screen holds up: Persian right to left, dark, large
/// text, a small phone, the paid-time states, the honest words about
/// manual entry, and a write that fails.
void main() {
  group('appearance', () {
    testWidgets('Persian reads right to left, in Persian words', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'parking_fa_');
      addTearDown(h.dispose);
      await _pump(
        tester,
        _fa,
        home: ParkingScreen(store: NexModuleStore(h.services, 'parking')),
      );
      expect(find.text('جای پارک'), findsOneWidget);
      expect(addButton('parking-fab', 'parking-empty-add'), findsOneWidget);
      expect(Directionality.of(_context(tester)), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme holds up', (tester) async {
      final h = await NexTestHarness.create(name: 'parking_dark_');
      addTearDown(h.dispose);
      await _pump(
        tester,
        (context, child) => MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
        home: ParkingScreen(store: NexModuleStore(h.services, 'parking')),
      );
      expect(addButton('parking-fab', 'parking-empty-add'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('twice the text size, no smaller a phone than 320×480', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'parking_scale_');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        (context, child) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: child,
        ),
        home: ParkingScreen(store: NexModuleStore(h.services, 'parking')),
      );
      expect(addButton('parking-fab', 'parking-empty-add'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the paid time, as the screen says it', () {
    testWidgets('a far-off time counts down', (tester) async {
      await _withScreen(tester, (h) async {
        await _create(tester, expiry: '2099/01/01 00:00');
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data!.startsWith('Ends in'),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('a past one says it may have ended', (tester) async {
      await _withScreen(tester, (h) async {
        await _create(tester, expiry: '2020/01/01 00:00');
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.data!.startsWith('May have ended'),
          ),
          findsOneWidget,
        );
      });
    });
  });

  group('honest words', () {
    testWidgets('the editor says the coordinates are typed, not found', (
      tester,
    ) async {
      await _withScreen(tester, (h) async {
        await tester.tap(addButton('parking-fab', 'parking-empty-add'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Only if you know them.'), findsOneWidget);
        // Nothing on this screen offers to find the position.
        expect(find.byIcon(Icons.my_location), findsNothing);
        expect(find.byIcon(Icons.location_searching), findsNothing);
      });
    });
  });

  group('when a write fails', () {
    testWidgets('the person is told, and nothing is faked', (tester) async {
      final root = Directory.systemTemp.createTempSync('parking_failing_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final db = _FailingPutDb(
        dbPath: p.join(root.path, 'nex.sqlite'),
        deviceId: 'test',
      );
      Directory(p.join(root.path, 'media')).createSync(recursive: true);
      Directory(p.join(root.path, 'backups')).createSync(recursive: true);
      final prefs = await NexPreferences.load();
      final services = NexServices.forTest(
        worker: db,
        deviceId: 'test',
        preferences: prefs,
        backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
        dbPath: p.join(root.path, 'nex.sqlite'),
        mediaDir: p.join(root.path, 'media'),
        backupDir: p.join(root.path, 'backups'),
      );
      addTearDown(services.dispose);

      await _pump(
        tester,
        (context, child) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
        home: ParkingScreen(store: NexModuleStore(services, 'parking')),
      );
      await _create(tester);
      expect(
        find.text('Could not save. Nothing was lost — try again.'),
        findsOneWidget,
      );
    });
  });
}

// ------------------------------------------------------------------ helpers

Future<void> _withScreen(
  WidgetTester tester,
  Future<void> Function(NexTestHarness h) body,
) async {
  final h = await NexTestHarness.create(name: 'parking_look_');
  addTearDown(h.dispose);
  await _pump(
    tester,
    (context, child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
    home: ParkingScreen(store: NexModuleStore(h.services, 'parking')),
  );
  await body(h);
}

Future<void> _create(
  WidgetTester tester, {
  String place = 'North lot',
  String expiry = '',
}) async {
  await tester.tap(addButton('parking-fab', 'parking-empty-add'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('parking-field-place')),
    place,
  );
  if (expiry.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-expiry-date')),
      expiry.split(' ').first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-expiry-time')),
      expiry.split(' ').last,
    );
  }
  final save = find.byKey(const ValueKey('parking-save'));
  final sheetList = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; attempt < 10; attempt++) {
    if (save.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(sheetList, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Widget _fa(BuildContext context, Widget? child) => MaterialApp(
  locale: const Locale('fa'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _pump(
  WidgetTester tester,
  Widget Function(BuildContext, Widget?) wrapper, {
  required Widget home,
}) async {
  await tester.pumpWidget(
    Builder(builder: (context) => wrapper(context, home)),
  );
  await tester.pumpAndSettle();
}

BuildContext _context(WidgetTester tester) =>
    tester.state(find.byType(Scaffold)).context;

/// A database whose module writes fail, as a full disk would make them.
class _FailingPutDb extends InProcessDb {
  _FailingPutDb({required super.dbPath, required super.deviceId});

  @override
  Future<ModuleRecord> modulePut(
    String module,
    String kind,
    String id,
    Map<String, Object?> body,
  ) async => throw Exception('no space left');
}
