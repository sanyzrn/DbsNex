import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No new file past 800 lines, and the ones already past it do not grow
/// (REL-10). Splitting them is its own piece of work; until then they are
/// held where they are, each with a little room to the next fifty.
void main() {
  const limit = 800;
  const grandfathered = <String, int>{
    'lib/platform/db_worker.dart': 1550,
    'lib/platform/nex_services.dart': 1600,
    'lib/platform/os_capture_bridge.dart': 850,
    'lib/platform/reminders.dart': 1350,
    'lib/screens/backup_screen.dart': 850,
    'lib/screens/cycle_screen.dart': 1050,
    'lib/screens/local_model_screen.dart': 950,
    'lib/screens/note_detail_sheet.dart': 900,
    'lib/screens/settings_sheet.dart': 850,
    'lib/screens/timeline_screen.dart': 850,
  };

  test('source files stay a readable size', () {
    final over = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/')) continue;
      final lines = entity.readAsLinesSync().length;
      final allowed = grandfathered[path] ?? limit;
      if (lines > allowed) over.add('$path: $lines lines (limit $allowed)');
    }
    expect(over, isEmpty, reason: 'split the file instead of raising a limit');
  });
}
