import 'package:flutter/material.dart' show ThemeMode;

/// Rebuilt as Nex 2.6.25 and switched back on. Every palette kept its
/// identity through the rebuild, so a choice stored under
/// `appearance.theme_preset` returns with the gallery, wearing the new
/// material — a stored ID is honoured, never rewritten.
const nexThemePresetsAvailable = true;

/// Paused again in 2.6.26 (owner's decision): the material was too heavy on
/// the owner's phone, and the switch is gone from Appearance until it is
/// reworked. Nothing is cleared: someone who had it on keeps the stored
/// choice under `appearance.liquid_glass_v3`, and it applies again once this
/// is true. Rebuilt as 2.6.21; each earlier generation was a fresh opt-in.
const nexLiquidGlassAvailable = false;

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
