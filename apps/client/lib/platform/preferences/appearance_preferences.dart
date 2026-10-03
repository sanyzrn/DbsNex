part of '../nex_preferences.dart';

/// How the app looks and reads: theme, palette, language, calendar, scale.
mixin _AppearancePreferences on _PreferencesStore {
  // Comfort Mode left Settings in 1.30.0 and nothing can turn it off any
  // more, so a stored `true` is no longer honoured. The whole-app palettes are
  // where a warmer look lives now.
  bool get comfortMode => false;

  // Temporarily disabled by the owner (1.70.0). Keep stored choice and
  // rendering code for a later redesign; do not silently re-enable it.
  bool get liquidGlass => false;

  String get themePreset =>
      _prefs.getString('appearance.theme_preset') ?? 'classic';
  Future<void> setThemePreset(String value) async {
    await _prefs.setString('appearance.theme_preset', value);
    notifyListeners();
  }

  // Background-only styles are retired in favour of whole-app themes.
  NexBackgroundPattern get backgroundPattern => NexBackgroundPattern.plain;

  /// The one accent colour a user actually picks — `#RRGGBB`, or null for
  /// the shipped default. The other three accent roles follow from it; see
  /// [NexAccentPalette].
  String? get accentSeed => _prefs.getString('appearance.accent_seed');

  /// The `#RRGGBB` colours most recently chosen in a colour picker, newest
  /// first.
  ///
  /// Tag colours are how a user encodes their own meaning (ADR-021), and
  /// meaning repeats: the second "urgent" tag wants the first one's red. The
  /// shipped swatches cannot carry that, because the colour someone settles
  /// on is by definition one the five did not anticipate — so the picker
  /// remembers what was actually picked.
  List<String> get recentColors =>
      _prefs.getStringList('appearance.recent_colors') ?? const [];

  /// A multiplier on top of the system's own text scale, not a replacement
  /// for it — someone who already runs a larger system font can still make
  /// Nex itself a little bigger or smaller on top of that. 1.0 is "as the
  /// device already asks for."
  double get uiScale => _prefs.getDouble('appearance.ui_scale') ?? 1.0;

  /// How much a timeline card holds (W7.2).
  NexCardDensity get cardDensity =>
      NexCardDensity.fromWire(_prefs.getString('appearance.card_density'));

  Future<void> setCardDensity(NexCardDensity value) async {
    await _prefs.setString('appearance.card_density', value.name);
    notifyListeners();
  }

  /// Whether Enter submits the note being typed on first capture, rather
  /// than starting a new line. Scoped to that one field on purpose — editing
  /// an existing note is a different moment, where a stray Enter should
  /// never end the session.
  bool get enterSubmitsCapture =>
      _prefs.getBool('capture.enter_submits') ?? true;

  bool get haptics => _prefs.getBool('accessibility.haptics') ?? true;

  Locale? get locale {
    final code = _prefs.getString('appearance.locale');
    return code == null || code == 'system' ? null : Locale(code);
  }

  bool get solarCalendar =>
      _prefs.getBool('appearance.solar_calendar') ?? false;
  Future<void> setSolarCalendar(bool enabled) async {
    await _prefs.setBool('appearance.solar_calendar', enabled);
    notifyListeners();
  }

  ThemeMode get themeMode => switch (_prefs.getString('appearance.theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setComfortMode(bool value) =>
      _setBool('appearance.comfort', value);

  Future<void> setLiquidGlass(bool value) =>
      _setBool('appearance.liquid_glass', value);

  Future<void> setBackgroundPattern(NexBackgroundPattern value) async {
    await _prefs.setString('appearance.background_pattern', value.wireName);
    notifyListeners();
  }

  /// Moves [color] to the front of [recentColors], keeping the list to
  /// [nexRecentColorLimit].
  ///
  /// Re-picking a colour already in the list promotes it rather than
  /// duplicating it, so the row stays eight *distinct* colours instead of
  /// filling up with the one being used most.
  Future<void> rememberColor(String color) async {
    final normalised = color.toUpperCase();
    final next = [
      normalised,
      ...recentColors.where((c) => c.toUpperCase() != normalised),
    ].take(nexRecentColorLimit).toList();
    await _prefs.setStringList('appearance.recent_colors', next);
    notifyListeners();
  }

  /// Null clears the setting back to the shipped default rather than storing
  /// an empty string — [accentSeed] only ever has to check for null.
  Future<void> setAccentSeed(String? value) async {
    if (value == null) {
      await _prefs.remove('appearance.accent_seed');
    } else {
      await _prefs.setString('appearance.accent_seed', value);
    }
    notifyListeners();
  }

  Future<void> setUiScale(double value) async {
    await _prefs.setDouble('appearance.ui_scale', value);
    notifyListeners();
  }

  Future<void> setEnterSubmitsCapture(bool value) =>
      _setBool('capture.enter_submits', value);

  Future<void> setHaptics(bool value) =>
      _setBool('accessibility.haptics', value);

  Future<void> setLocale(String value) async {
    await _prefs.setString('appearance.locale', value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _prefs.setString('appearance.theme', value.name);
    notifyListeners();
  }
}
