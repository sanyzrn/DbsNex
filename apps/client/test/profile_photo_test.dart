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
}
