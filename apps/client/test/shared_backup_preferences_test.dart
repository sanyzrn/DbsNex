import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> backup(
    Map<String, dynamic> preferences, {
    List<String> cleared = const [],
  }) => {
    'version': 2,
    'scope': 'shared',
    'preferences': preferences,
    'credentials': <String, String>{},
    'clearedPreferences': cleared,
    'desktopShell': {'hotkey': 'Q', 'windowMode': 'panel'},
  };

  test(
    'Windows appearance restore leaves Android identity, AI key and private preferences intact',
    () async {
      SharedPreferences.setMockInitialValues({
        'appearance.accent_seed': '#123456',
        'modules.cycle.enabled': true,
        'profile.display_name': 'Saeed',
        'backup_folder.uri': 'content://phone-only',
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      await prefs.setDisplayName('Saeed');
      final id = await prefs.stableDeviceId();
      await prefs.setAiProvider(
        const AiProviderConfig(
          provider: AiProvider.openai,
          apiKey: 'keep-private-key',
        ),
      );
      await prefs.restoreSettings(
        backup(
          {
            'appearance.theme': 'dark',
            'appearance.theme_preset': 'circuit',
            'appearance.locale': 'fa',
            'appearance.ui_scale': 1.2,
            'appearance.recent_colors': ['#B61615'],
          },
          cleared: ['appearance.accent_seed'],
        ),
      );
      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.themePreset, 'circuit');
      expect(prefs.accentSeed, isNull);
      expect(prefs.uiScale, 1.2);
      expect(prefs.locale, const Locale('fa'));
      expect(prefs.recentColors, ['#B61615']);
      expect(await prefs.stableDeviceId(), id);
      expect(prefs.configFor(AiProvider.openai).apiKey, 'keep-private-key');
      final raw = await SharedPreferences.getInstance();
      expect(raw.getBool('modules.cycle.enabled'), isTrue);
      expect(raw.getString('backup_folder.uri'), 'content://phone-only');
      expect(prefs.displayName, 'Saeed');
    },
  );

  test(
    'scoped transfer rejects credentials, vault and foreign keys before writing',
    () async {
      SharedPreferences.setMockInitialValues({
        'appearance.theme_preset': 'paper',
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      for (final invalid in [
        {...backup({'appearance.theme_preset': 'circuit'}), 'version': 1},
        {
          ...backup({'appearance.theme_preset': 'circuit'}),
          'credentials': {'openai': 'overwrite'},
        },
        {
          ...backup({'appearance.theme_preset': 'circuit'}),
          'vault': <String, dynamic>{},
        },
        backup({'nex.device_id': 'foreign'}),
        backup({
          'appearance.theme_preset': 'circuit',
          'appearance.ui_scale': 99,
        }),
        backup({}, cleared: ['profile.display_name']),
      ]) {
        await expectLater(
          prefs.restoreSettings(invalid),
          throwsFormatException,
        );
        expect(prefs.themePreset, 'paper');
      }
    },
  );
}
