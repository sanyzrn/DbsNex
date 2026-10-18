import 'dart:convert';
import 'dart:io';
import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'note types and shared preference keys retain the cross-platform contract',
    () {
      final contract =
          jsonDecode(
                File('../../contracts/nex-portable-v1.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(NoteType.values.map((t) => t.wireName), contract['noteTypes']);
      expect(
        PortablePreferences.keys,
        unorderedEquals(contract['sharedPreferences'] as List),
      );
      expect(
      PortablePreferences.settingsVersion,
      contract['sharedSettingsVersion'],
    );
    PortablePreferences.validate(PortablePreferences.defaults);
    },
  );
}
