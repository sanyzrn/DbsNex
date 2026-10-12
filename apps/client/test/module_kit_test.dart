import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:path/path.dart' as p;

import 'module_kit/tally/module.dart';
import 'support/nex_harness.dart';

/// The module kit's gate — `docs/18-module-kit.md`.
///
/// A module written somewhere else is one folder, `lib/modules/<id>/`, and
/// it is only allowed in if everything here passes: it imports the module
/// API and nothing that reaches past it, it does not take over the parts
/// the platform does for it, its words are complete in both languages, it
/// has its own tests and a README, and it is registered.
void main() {
  group('the gate', () {
    final modulesDir = Directory(p.join('lib', 'modules'));
    final folders = modulesDir.listSync().whereType<Directory>().toList();

    for (final folder in folders) {
      final id = p.basename(folder.path);
      test('module "$id" stays inside the module API', () {
        expect(moduleKitProblems(folder), isEmpty);
      });
      test('module "$id" has its README, tests and registry line', () {
        expect(File(p.join(folder.path, 'README.md')).existsSync(), isTrue);
        final tests = Directory(p.join('test', 'modules', id));
        expect(
          tests.existsSync() &&
              tests
                  .listSync(recursive: true)
                  .any((f) => f.path.endsWith('_test.dart')),
          isTrue,
          reason: 'test/modules/$id/ holds its tests',
        );
        expect(
          File(
            p.join('lib', 'modules', 'module_registry.dart'),
          ).readAsStringSync(),
          contains("'$id/module.dart'"),
        );
        expect(nexModules.map((m) => m.id), contains(id));
      });
    }

    test('the worked example passes it', () {
      expect(
        moduleKitProblems(Directory(p.join('test', 'module_kit', 'tally'))),
        isEmpty,
      );
    });

    test('and a module that reaches past the API does not', () {
      final dir = Directory.systemTemp.createTempSync('nex_bad_module_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'module.dart')).writeAsStringSync('''
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../platform/nex_services.dart';
import '../module_api.dart';

class BadModule extends NexStoredModule {
  @override
  Widget open({required services, required preferences}) => Text(services.toString());
}
''');
      final problems = moduleKitProblems(dir).join('\n');
      expect(problems, contains('dart:io'));
      expect(problems, contains('package:http'));
      expect(problems, contains('nex_services.dart'));
      expect(problems, contains('open('));
    });
  });

  group('words', () {
    final stored = [
      ...nexModules.whereType<NexStoredModule>(),
      const TallyModule(),
    ];
    for (final module in stored) {
      test('"${module.id}" has every word in both languages', () {
        final strings = module.strings;
        expect(strings.en.keys.toSet(), strings.fa.keys.toSet());
        for (final key in ['title', 'tagline', 'about', 'point1', 'point2']) {
          expect(strings.en, contains(key));
        }
        for (final value in [...strings.en.values, ...strings.fa.values]) {
          expect(value.trim(), isNotEmpty);
        }
        expect(module.id, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      });
    }

    test('arguments are filled, in Persian digits on the Persian side', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final fa = lookupAppLocalizations(const Locale('fa'));
      expect(tallyStrings.text(en, 'count', {'count': 12}), '12 so far');
      expect(tallyStrings.text(fa, 'count', {'count': 12}), 'تا اینجا ۱۲');
    });
  });

  group('a stored module, end to end', () {
    late NexTestHarness harness;

    setUp(() async => harness = await NexTestHarness.create(name: 'nex_kit_'));
    tearDown(() => harness.dispose());

    Future<BuildContext> pumpHost(WidgetTester tester, Widget home) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              captured = context;
              return home;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('added, used, removed keeping its data, then deleting it', (
      tester,
    ) async {
      const tally = TallyModule();
      final services = harness.services;
      final prefs = harness.preferences;
      expect(tally.isOn(prefs), isFalse);

      var context = await pumpHost(tester, const SizedBox());
      await tally.turnOn(context, services: services, preferences: prefs);
      expect(tally.isOn(prefs), isTrue);
      expect(prefs.isModuleOn('tally'), isTrue);

      await pumpHost(
        tester,
        tally.open(services: services, preferences: prefs),
      );
      expect(find.text('0 so far'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('tally-add')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('tally-add')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('2 so far'), findsOneWidget);

      // Another module's store cannot see these.
      expect(await services.moduleRecords('other', 'tap'), isEmpty);

      Future<bool> remove(String choice) async {
        context = await pumpHost(tester, const SizedBox());
        final off = tally.turnOff(
          context,
          services: services,
          preferences: prefs,
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove Tally?'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('module-tally-off-$choice')));
        await tester.pumpAndSettle();
        return off;
      }

      expect(await remove('keep'), isTrue);
      expect(tally.isOn(prefs), isFalse);
      expect(await services.moduleRecords('tally', 'tap'), hasLength(2));

      await tally.turnOn(context, services: services, preferences: prefs);
      expect(await remove('delete'), isTrue);
      expect(await services.moduleRecords('tally', 'tap'), isEmpty);
    });
  });
}

/// What keeps [folder] from being a module: one line per problem.
List<String> moduleKitProblems(Directory folder) {
  final problems = <String>[];
  final root = p.normalize(folder.absolute.path);
  const packages = {
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'package:flutter/foundation.dart',
    'package:flutter/animation.dart',
    'package:flutter/painting.dart',
    'package:flutter/gestures.dart',
    'package:flutter/rendering.dart',
    'package:nex_client/modules/module_api.dart',
  };
  const darts = {
    'dart:async',
    'dart:math',
    'dart:convert',
    'dart:collection',
    'dart:ui',
  };
  // What a module must leave to the platform, or must not touch at all.
  final forbidden = <RegExp, String>{
    RegExp(r'\bWidget\s+open\s*\('): 'overrides open( — use screen(store)',
    RegExp(r'\bturnOn\s*\('): 'overrides turnOn(',
    RegExp(r'\bturnOff\s*\('): 'overrides turnOff(',
    RegExp(r'\bisOn\s*\('): 'overrides isOn(',
    RegExp(r'\bNexServices\b'): 'names NexServices',
    RegExp(r'\bNexPreferences\b'): 'names NexPreferences',
    RegExp(r'\bMethodChannel\b|\bEventChannel\b'): 'opens a platform channel',
    RegExp(r'\bshowModalBottomSheet\b'): 'uses showModalBottomSheet',
    RegExp(r'(?<![A-Za-z_])showDialog\b'): 'uses showDialog',
  };
  final directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final files = folder
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final name = p.relative(file.path, from: folder.path);
    final source = file.readAsStringSync();
    for (final match in directive.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('dart:')) {
        if (!darts.contains(uri)) problems.add('$name imports $uri');
      } else if (uri.startsWith('package:')) {
        if (!packages.contains(uri)) problems.add('$name imports $uri');
      } else {
        final target = p.normalize(p.join(file.parent.absolute.path, uri));
        final api = p.normalize(
          p.join(folder.parent.absolute.path, 'module_api.dart'),
        );
        if (!p.isWithin(root, target) && target != api) {
          problems.add('$name imports $uri, outside its folder');
        }
      }
    }
    for (final MapEntry(key: pattern, value: why) in forbidden.entries) {
      if (pattern.hasMatch(source)) problems.add('$name $why');
    }
  }
  return problems;
}
