import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/profile_photo.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('nex_profile_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('recovers an avatar when its old absolute sandbox path is stale', () {
    final media = Directory(p.join(root.path, 'media'));
    final profile = Directory(p.join(media.path, 'profile'))
      ..createSync(recursive: true);
    final avatar = File(p.join(profile.path, 'avatar.jpg'))
      ..writeAsBytesSync([1, 2, 3]);

    expect(
      resolveProfilePhoto(
        media.path,
        '/old/sandbox/media/profile/avatar.jpg',
      )?.path,
      avatar.path,
    );
    expect(resolveProfilePhoto(media.path, null)?.path, avatar.path);
  });

  test('does not claim a missing image has been recovered', () {
    expect(resolveProfilePhoto(root.path, '/old/avatar.jpg'), isNull);
  });

  test('each new picture gets its own path, and both kinds are found', () {
    // One fixed name meant the image cache kept drawing the old picture.
    final media = Directory(p.join(root.path, 'media'));
    final profile = Directory(p.join(media.path, 'profile'))
      ..createSync(recursive: true);
    final first = nextProfilePhotoPath(media.path, '.png');
    final second = nextProfilePhotoPath(media.path, '');
    expect(first, isNot(second));
    expect(first, endsWith('.png'));
    expect(second, endsWith('.jpg'));
    File(first).writeAsBytesSync([1]);
    File(p.join(profile.path, 'avatar.jpg')).writeAsBytesSync([2]);
    File(p.join(profile.path, 'notes.txt')).writeAsBytesSync([3]);
    expect(profilePhotoFiles(media.path), hasLength(2));
    expect(resolveProfilePhoto(media.path, first)?.path, first);
  });
}
