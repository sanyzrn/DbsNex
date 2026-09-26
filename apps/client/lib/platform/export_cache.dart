import 'dart:io';
import 'package:path/path.dart' as p;

/// Remove only old Nex-owned exports, allowing receiving apps a week to read.
Future<void> cleanExportCache(Directory directory, {DateTime? now}) async {
  if (!await directory.exists()) return;
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is Directory &&
        p.basename(entity.path).startsWith('.nex-portable-') &&
        p.isWithin(directory.absolute.path, entity.absolute.path)) {
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } on FileSystemException {
        // Interrupted portable exports can be retried at the next cleanup.
      }
      continue;
    }
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!RegExp(
      r'^Nex-[0-9a-zA-Z-]+\.(zip|nexbak)(\.partial)?$',
    ).hasMatch(name)) {
      continue;
    }
    try {
      if ((await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
      }
    } on FileSystemException {
      /* Busy files wait until next time. */
    }
  }
}
