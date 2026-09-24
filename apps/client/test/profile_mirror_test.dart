import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('nex_profile_mirror_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'recovers profile details when preferences disappear but media survives',
    () async {
      final media = p.join(root.path, 'media');
      final original = await NexPreferences.load();
      await original.attachProfileMirror(media);
      await original.setDisplayName('Sany');
      await original.setProfileBirthday(DateTime(1998, 2, 7));
      await original.setProfileBio('A note about me');
      expect(
        File(p.join(media, 'profile', 'details.json')).existsSync(),
        isTrue,
      );

      SharedPreferences.setMockInitialValues({});
      final restored = await NexPreferences.load();
      await restored.attachProfileMirror(media);
      expect(restored.displayName, 'Sany');
      expect(restored.profileBirthday, DateTime(1998, 2, 7));
      expect(restored.profileBio, 'A note about me');
    },
  );

  test(
    'a deliberate clear is mirrored and does not resurrect old data',
    () async {
      final media = p.join(root.path, 'media');
      final original = await NexPreferences.load();
      await original.attachProfileMirror(media);
      await original.setDisplayName('Sany');
      await original.setProfileBirthday(DateTime(1998, 2, 7));
      await original.setProfileBio('Old bio');
      await original.setDisplayName(null);
      await original.setProfileBirthday(null);
      await original.setProfileBio('');

      SharedPreferences.setMockInitialValues({});
      final restored = await NexPreferences.load();
      await restored.attachProfileMirror(media);
      expect(restored.displayName, isNull);
      expect(restored.profileBirthday, isNull);
      expect(restored.profileBio, isEmpty);
    },
  );

  test('existing preferences win over a stale media mirror', () async {
    final media = p.join(root.path, 'media');
    final original = await NexPreferences.load();
    await original.attachProfileMirror(media);
    await original.setDisplayName('Old name');

    SharedPreferences.setMockInitialValues({'profile.name': 'Current name'});
    final restored = await NexPreferences.load();
    await restored.attachProfileMirror(media);
    expect(restored.displayName, 'Current name');
  });
}
