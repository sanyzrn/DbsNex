import 'package:flutter/material.dart' show ThemeMode;

/// Temporarily paused; stored palette IDs and the gallery remain intact.
const nexThemePresetsAvailable = false;

/// Appearance is separate from Flutter's three brightness modes. Night keeps
/// the former Dark palette; System uses the new soft Dark when the OS is dark.
enum NexAppearanceMode {
  light,
  dark,
  night,
  system;

  /// A new wire value distinguishes an explicit new Dark choice from a backup
  /// or install that still carries the old `dark` value. No destructive rewrite.
  String get wireName => this == dark ? 'soft_dark' : name;

  ThemeMode get materialMode => switch (this) {
    light => ThemeMode.light,
    dark || night => ThemeMode.dark,
    system => ThemeMode.system,
  };

  static NexAppearanceMode fromWire(String? value) => switch (value) {
    'light' => light,
    'soft_dark' => dark,
    'dark' || 'night' => night,
    _ => system,
  };
}
