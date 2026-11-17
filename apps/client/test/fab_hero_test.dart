import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every floating button says what hero it is (2.8.2).
///
/// A [FloatingActionButton] left to its default hero tag shares it with every
/// other one, so a page pushed over another flew one page's button into the
/// next: Home's + turned into a module's "New habit" on the way in, and back
/// on the way out. None of them is meant to travel between pages.
void main() {
  test('no floating button keeps the shared default hero tag', () {
    final pattern = RegExp(
      r'FloatingActionButton(\.extended|\.small|\.large)?\(',
    );
    final missing = <String>[];
    for (final root in ['lib', '../../packages/ui/lib']) {
      for (final file in Directory(root).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final match in pattern.allMatches(source)) {
          var depth = 1;
          var i = match.end;
          while (depth > 0 && i < source.length) {
            final c = source[i++];
            if (c == '(') depth++;
            if (c == ')') depth--;
          }
          if (!source.substring(match.end, i).contains('heroTag')) {
            final line =
                '\n'.allMatches(source.substring(0, match.start)).length + 1;
            missing.add('${file.path}:$line');
          }
        }
      }
    }
    expect(missing, isEmpty);
  });
}
