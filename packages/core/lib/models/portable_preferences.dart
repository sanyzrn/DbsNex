/// Platform-neutral appearance keys, using the existing Android wire names.
/// OS integration, credentials and private modules are deliberately outside it.
abstract final class PortablePreferences {
  static const defaults = <String, dynamic>{
    'appearance.theme': 'system',
    'appearance.theme_preset': 'classic',
    'appearance.locale': 'system',
    'appearance.card_density': 'standard',
    'appearance.ui_scale': 1.0,
    'appearance.recent_colors': <String>[],
  };

  static const keys = {
    'appearance.theme',
    'appearance.theme_preset',
    'appearance.accent_seed',
    'appearance.recent_colors',
    'appearance.locale',
    'appearance.card_density',
    'appearance.ui_scale',
    'appearance.solar_calendar',
  };

  static bool isColor(Object? value) =>
      value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

  static void validate(Map<String, dynamic> preferences) {
    for (final entry in preferences.entries) {
      final v = entry.value;
      final valid = switch (entry.key) {
        'appearance.theme' => const {'system', 'light', 'dark'}.contains(v),
        'appearance.theme_preset' =>
          v is String && RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(v),
        'appearance.accent_seed' => isColor(v),
        'appearance.recent_colors' =>
          v is List && v.length <= 32 && v.every(isColor),
        'appearance.locale' => const {'system', 'fa', 'en'}.contains(v),
        'appearance.card_density' => const {
          'compact',
          'standard',
          'readable',
        }.contains(v),
        'appearance.ui_scale' => v is num && v.isFinite && v >= 0.5 && v <= 3,
        'appearance.solar_calendar' => v is bool,
        _ => false,
      };
      if (!valid) {
        throw FormatException('Invalid shared preference: ${entry.key}');
      }
    }
  }

  static void validateScopedBackup(Map<String, dynamic> settings) {
    if (settings['version'] != 1 ||
        settings['scope'] != 'shared' ||
        settings['preferences'] is! Map ||
        settings['credentials'] is! Map ||
        (settings['credentials'] as Map).isNotEmpty ||
        settings.containsKey('vault')) {
      throw const FormatException('Invalid shared settings backup');
    }
    validate(Map<String, dynamic>.from(settings['preferences'] as Map));
    final cleared = settings['clearedPreferences'] ?? const <String>[];
    if (cleared is! List ||
        cleared.any((key) => !keys.contains(key)) ||
        cleared.any(
          (key) => (settings['preferences'] as Map).containsKey(key),
        )) {
      throw const FormatException('Invalid cleared shared preferences');
    }
  }
}
