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
  // The page itself, light and dark. Null keeps the classic surfaces.
  Color? light,
  Color? dark,
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
    light: null,
    dark: null,
  ),
  (
    id: 'paper',
    en: 'Paper notebook',
    fa: 'دفتر کاغذی',
    enDescription: 'Warm cream, ink and quiet surfaces',
    faDescription: 'کرم گرم، جوهر و سطح‌های آرام',
    seed: Color(0xFF8A6A36),
    icon: Icons.menu_book_outlined,
    light: Color(0xFFF5EEDC),
    dark: Color(0xFF27231C),
  ),
  (
    id: 'autumn',
    en: 'Autumn',
    fa: 'پاییز',
    enDescription: 'Terracotta, amber and warm dusk',
    faDescription: 'سفالی، کهربایی و غروب گرم',
    seed: Color(0xFFAC4F2C),
    icon: Icons.eco_outlined,
    light: Color(0xFFFFF0E5),
    dark: Color(0xFF291D18),
  ),
  (
    id: 'blossom',
    en: 'Rose atelier',
    fa: 'شکوفهٔ رز',
    enDescription: 'Soft rose and lilac with a feminine touch',
    faDescription: 'رز لطیف و یاسی با حال‌وهوای دخترانه',
    seed: Color(0xFFAE497C),
    icon: Icons.local_florist_outlined,
    light: Color(0xFFFFF1F7),
    dark: Color(0xFF291D28),
  ),
  (
    id: 'forest',
    en: 'Forest retreat',
    fa: 'خلوت جنگل',
    enDescription: 'Sage green and deep woodland',
    faDescription: 'سبز مریم‌گلی و عمق جنگل',
    seed: Color(0xFF367568),
    icon: Icons.forest_outlined,
    light: Color(0xFFEDF4EB),
    dark: Color(0xFF172722),
  ),
  (
    id: 'turquoise',
    en: 'Isfahan turquoise',
    fa: 'فیروزهٔ اصفهان',
    enDescription: 'Tilework turquoise with a touch of lapis',
    faDescription: 'فیروزه‌ای کاشی با ته‌رنگ لاجورد',
    seed: Color(0xFF00838F),
    icon: Icons.mosque_outlined,
    light: Color(0xFFE8F6F5),
    dark: Color(0xFF0D2226),
  ),
  (
    id: 'saffron',
    en: 'Saffron',
    fa: 'زعفران',
    enDescription: 'Golden saffron on warm ivory',
    faDescription: 'زعفرانی طلایی روی عاج گرم',
    seed: Color(0xFFC77700),
    icon: Icons.spa_outlined,
    light: Color(0xFFFFF6E6),
    dark: Color(0xFF2A1F0E),
  ),
  (
    id: 'midnight',
    en: 'Midnight',
    fa: 'نیمه‌شب',
    enDescription: 'Deep indigo with a violet glow',
    faDescription: 'نیلی عمیق با درخششی بنفش',
    seed: Color(0xFF6750D8),
    icon: Icons.nights_stay_outlined,
    light: Color(0xFFF1EEFC),
    dark: Color(0xFF14112A),
  ),
  (
    id: 'ocean',
    en: 'Deep sea',
    fa: 'اعماق دریا',
    enDescription: 'Cool blues and sea glass',
    faDescription: 'آبی‌های خنک و شیشهٔ دریایی',
    seed: Color(0xFF1565A8),
    icon: Icons.waves,
    light: Color(0xFFEAF2FA),
    dark: Color(0xFF0B1A2A),
  ),
  (
    id: 'graphite',
    en: 'Graphite',
    fa: 'گرافیت',
    enDescription: 'Pure greys and nothing else',
    faDescription: 'خاکستری خالص، بی هیچ رنگ دیگری',
    seed: Color(0xFF5E6166),
    icon: Icons.contrast,
    light: Color(0xFFF1F1F1),
    dark: Color(0xFF151515),
  ),
];

/// The seed a palette brings with it, or null for the classic look, which
/// keeps the shipped accent.
Color? nexThemePresetSeed(String id) => id == 'classic'
    ? null
    : nexThemePresets
          .firstWhere((p) => p.id == id, orElse: () => nexThemePresets.first)
          .seed;

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
    // Graphite is the one palette that is about having no colour: its tones
    // are taken without chroma, so nothing turns faintly blue.
    dynamicSchemeVariant: id == 'graphite'
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
    surface: base.brightness == Brightness.light ? p.light : p.dark,
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
    // No colour for icons across the board. One set here won over the
    // foreground every filled button gives its own icon, so on every palette
    // but the classic one the capture arrow, the vault's add buttons, the
    // saved-messages send and the voice note's play button drew a grey icon
    // on a coloured button — about 1:1 in dark.
  );
}
