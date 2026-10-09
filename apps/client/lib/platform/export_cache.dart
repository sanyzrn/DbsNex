import 'dart:io';
import 'package:path/path.dart' as p;

/// The folder Android's file picker copies a chosen file into: the cache,
/// then a UUID (`file_selector`'s `FileUtils.getPathFromCopyOfFileFromUri`).
final _pickedCopyFolder = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Deletes the copy Android's file picker made of a file someone chose
/// (SEC-01): a password CSV or a backup, whole and unencrypted, which the
/// plugin leaves in the cache for good. Only that copy, never the person's
/// own file: nothing outside [cache] is touched.
Future<void> discardPickedCopy(String pickedPath, Directory cache) async {
  try {
    final folder = Directory(p.dirname(pickedPath));
    final root = cache.absolute.path;
    if (!p.isWithin(root, folder.absolute.path)) return;
    if (_pickedCopyFolder.hasMatch(p.basename(folder.path))) {
      await folder.delete(recursive: true);
    } else {
      await File(pickedPath).delete();
    }
  } on FileSystemException {
    // Gone already, or busy: the next cleanup takes it.
  }
}

/// Remove only old Nex-owned exports, allowing receiving apps a week to read,
/// and the file picker's copies of what was chosen once they are an hour old.
Future<void> cleanExportCache(Directory directory, {DateTime? now}) async {
  if (!await directory.exists()) return;
  final at = now ?? DateTime.now();
  final cutoff = at.subtract(const Duration(days: 7));
  final pickedCutoff = at.subtract(const Duration(hours: 1));
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is Directory &&
        _pickedCopyFolder.hasMatch(p.basename(entity.path))) {
      try {
        if ((await entity.stat()).modified.isBefore(pickedCutoff)) {
          await entity.delete(recursive: true);
        }
      } on FileSystemException {
        // Busy: the next cleanup takes it.
      }
      continue;
    }
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
      r'^Nex-[0-9a-zA-Z-]+\.(zip|nexbak|nexfull)(\.partial)?$',
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
