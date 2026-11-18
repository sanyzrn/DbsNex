import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// "Shared across modules" (`docs/18-module-kit.md`), held by a test so a
/// module added later cannot skip it (2.8.2).
///
/// The modules written before the rules are listed as pending. The lists
/// only shrink: a module that meets a rule must leave its list (the test
/// says so), and a module not on a list must meet the rule from its first
/// commit. Upgrading a module is when it leaves.
void main() {
  /// Modules with reminders or dates falling due that do not yet produce
  /// them through `duesBetween`.
  const duesPending = {'habits', 'occasions', 'warranty'};

  /// Modules without a `summarize` line per record yet.
  const summaryPending = {
    'converter',
    'gold',
    'habits',
    'occasions',
    'price_lens',
    'prompt_studio',
    'security_tools',
    'smoke_free',
    'warranty',
  };

  final folders = Directory(p.join('lib', 'modules'))
      .listSync()
      .whereType<Directory>()
      .toList();

  String sourceOf(Directory folder) => [
    for (final file
        in folder
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
      file.readAsStringSync(),
  ].join('\n');

  final dated = RegExp(r'\bNexModuleReminderControl\(|\bsetReminder\(');
  final dues = RegExp(r'\bList<ModuleDue>\s+duesBetween\(');
  final summary = RegExp(r'\bModuleSummary\?\s+summarize\(');
  // Money is a whole number of rials: a `…Rial` that can hold a fraction is
  // the start of a rounding bug.
  final fractionalRials = RegExp(r'\b(?:double|num)\??\s+\w*Rial\b');

  for (final folder in folders) {
    final id = p.basename(folder.path);
    final source = sourceOf(folder);

    test('module "$id" gives its dates falling due in the shared shape', () {
      final has = dues.hasMatch(source);
      if (duesPending.contains(id)) {
        expect(
          has,
          isFalse,
          reason: '$id now has duesBetween: take it off duesPending',
        );
      } else if (dated.hasMatch(source)) {
        expect(
          has,
          isTrue,
          reason:
              '$id sets reminders, so it gives its due dates through '
              '`List<ModuleDue> duesBetween(from, to)` (docs/18, rule 1)',
        );
      }
    });

    test('module "$id" has a line about each record', () {
      final has = summary.hasMatch(source);
      if (summaryPending.contains(id)) {
        expect(
          has,
          isFalse,
          reason: '$id now has summarize: take it off summaryPending',
        );
      } else {
        expect(
          has,
          isTrue,
          reason:
              '$id needs `ModuleSummary? summarize(ModuleRecord record)` '
              '(docs/18, rule 4)',
        );
      }
    });

    test('module "$id" keeps money in whole rials', () {
      expect(
        fractionalRials.allMatches(source).map((m) => m.group(0)).toList(),
        isEmpty,
        reason: 'docs/18, rule 2',
      );
    });
  }

  test('the pending lists name only modules that exist', () {
    final ids = folders.map((f) => p.basename(f.path)).toSet();
    expect(duesPending.difference(ids), isEmpty);
    expect(summaryPending.difference(ids), isEmpty);
  });
}
