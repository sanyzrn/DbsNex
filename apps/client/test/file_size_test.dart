import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No file past 800 lines (REL-10; a condition for 2.0). The files that
/// had grown past it were split in 1.99.70 into part files by concern, so
/// there is no list of exceptions any more — and none is to be added.
void main() {
  const limit = 800;

  test('source files stay a readable size', () {
    final over = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/')) continue;
      final lines = entity.readAsLinesSync().length;
      if (lines > limit) over.add('$path: $lines lines (limit $limit)');
    }
    expect(over, isEmpty, reason: 'split the file instead of raising a limit');
  });
}
