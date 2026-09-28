import 'package:flutter/material.dart';
import '../widgets/feature_label.dart';

typedef NexThemePreset = ({
  String id,
  String en,
  String fa,
  String enDescription,
  String faDescription,
  Color seed,
  IconData icon,
});
const nexThemePresets = <NexThemePreset>[
  (
    id: 'classic',
    en: 'Nex',
    fa: 'نکس',
    enDescription: 'Clean and familiar',
    faDescription: 'ساده و آشنا',
    seed: Color(0xFF287EC0),
    icon: Icons.auto_awesome,
  ),
  (
    id: 'paper',
    en: 'Paper notebook',
    fa: 'دفتر کاغذی',
    enDescription: 'Warm cream, ink and quiet surfaces',
    faDescription: 'کرم گرم، جوهر و سطح‌های آرام',
    seed: Color(0xFF8A6A36),
    icon: Icons.menu_book_outlined,
  ),
  (
    id: 'autumn',
    en: 'Autumn',
    fa: 'پاییز',
    enDescription: 'Terracotta, amber and warm dusk',
    faDescription: 'سفالی، کهربایی و غروب گرم',
    seed: Color(0xFFAC4F2C),
    icon: Icons.eco_outlined,
  ),
  (
    id: 'blossom',
    en: 'Rose atelier',
    fa: 'شکوفهٔ رز',
    enDescription: 'Soft rose and lilac with a feminine touch',
    faDescription: 'رز لطیف و یاسی با حال‌وهوای دخترانه',
    seed: Color(0xFFAE497C),
    icon: Icons.local_florist_outlined,
  ),
  (
    id: 'forest',
    en: 'Forest retreat',
    fa: 'خلوت جنگل',
    enDescription: 'Sage green and deep woodland',
    faDescription: 'سبز مریم‌گلی و عمق جنگل',
    seed: Color(0xFF367568),
    icon: Icons.forest_outlined,
  ),
];
String nexThemePresetLabel(BuildContext context, String id) {
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  return nexLabel(context, p.en, p.fa);
}

ThemeData nexApplyThemePreset(ThemeData base, String id, Color? accent) {
  if (id == 'classic') return base;
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  final colors = ColorScheme.fromSeed(
    seedColor: accent ?? p.seed,
    brightness: base.brightness,
    surface: switch ((id, base.brightness)) {
      ('paper', Brightness.light) => const Color(0xFFF5EEDC),
      ('autumn', Brightness.light) => const Color(0xFFFFF0E5),
      ('blossom', Brightness.light) => const Color(0xFFFFF1F7),
      ('forest', Brightness.light) => const Color(0xFFEDF4EB),
      ('paper', _) => const Color(0xFF27231C),
      ('autumn', _) => const Color(0xFF291D18),
      ('blossom', _) => const Color(0xFF291D28),
      _ => const Color(0xFF172722),
    },
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    cardTheme: base.cardTheme.copyWith(color: colors.surfaceContainerLow),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: colors.surface,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: colors.surfaceContainerHigh,
    ),
    dividerTheme: base.dividerTheme.copyWith(color: colors.outlineVariant),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    iconTheme: base.iconTheme.copyWith(color: colors.onSurfaceVariant),
  );
}
