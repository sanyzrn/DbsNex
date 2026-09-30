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
  // profile image is named avatar-<time>.<extension> (avatar.<extension>
  // before 1.90); prefer the latest if an interrupted replacement left two.
  final candidates = profilePhotoFiles(mediaDir).toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return candidates.isEmpty ? null : candidates.first;
}

/// Every profile picture kept under media/profile.
Iterable<File> profilePhotoFiles(String mediaDir) {
  final directory = Directory(p.join(mediaDir, 'profile'));
  if (!directory.existsSync()) return const [];
  return directory.listSync(followLinks: false).whereType<File>().where((file) {
    final name = p.basename(file.path);
    return name.startsWith('avatar.') || name.startsWith('avatar-');
  });
}

/// A new name for the next picture, so it never shares a path with the last.
///
/// Every picture used to be `avatar.jpg`. The image cache is keyed by path, so
/// a replaced picture kept showing the old one, and a removed one lingered
/// until the cache let go of it.
String nextProfilePhotoPath(String mediaDir, String extension) => p.join(
  mediaDir,
  'profile',
  'avatar-${DateTime.now().microsecondsSinceEpoch}'
      '${extension.isEmpty ? '.jpg' : extension}',
);
