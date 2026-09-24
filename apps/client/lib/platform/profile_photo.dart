import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds a locally kept profile picture after an in-place update or restore.
/// Older preferences store an absolute sandbox path; the picture itself lives
/// under media/profile and may still be there when that path has gone stale.
File? resolveProfilePhoto(String mediaDir, String? storedPath) {
  if (storedPath != null && storedPath.isNotEmpty) {
    final original = File(storedPath);
    if (original.existsSync()) return original;
  }

  final directory = Directory(p.join(mediaDir, 'profile'));
  if (!directory.existsSync()) return null;
  if (storedPath != null && storedPath.isNotEmpty) {
    final moved = File(p.join(directory.path, p.basename(storedPath)));
    if (moved.existsSync()) return moved;
  }

  // The preference can be missing while the media directory survives. A
  // profile image is always named avatar.<extension>; prefer the latest if an
  // older format was left behind by an interrupted replacement.
  final candidates =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith('avatar.'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  return candidates.isEmpty ? null : candidates.first;
}
