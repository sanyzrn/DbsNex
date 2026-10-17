import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
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

/// The faint motif a theme draws up from the bottom of the screen. Every
/// palette has one but the plain Nex look, which stays plain on purpose.
NexThemeTexture nexThemeTexture(String presetId) => switch (presetId) {
  'paper' => NexThemeTexture.fibre,
  'autumn' => NexThemeTexture.leaves,
  'blossom' => NexThemeTexture.petals,
  'saffron' => NexThemeTexture.threads,
  'graphite' => NexThemeTexture.grid,
  'turquoise' => NexThemeTexture.girih,
  'forest' => NexThemeTexture.contours,
  'ocean' => NexThemeTexture.waves,
  'midnight' => NexThemeTexture.stars,
  'bauhaus' => NexThemeTexture.bauhaus,
  'porcelain' => NexThemeTexture.seams,
  'circuit' => NexThemeTexture.circuit,
  'afterimage' => NexThemeTexture.halftone,
  _ => NexThemeTexture.none,
};

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
  (
    id: 'bauhaus',
    en: 'Bauhaus',
    fa: 'باوهاوس',
    enDescription: 'Ink, vermilion and bold geometry',
    faDescription: 'جوهر، سرخ شنگرف و هندسهٔ جسور',
    seed: Color(0xFFBC352C),
    icon: Icons.category_outlined,
    light: Color(0xFFF6F3EB),
    dark: Color(0xFF231A18),
  ),
  (
    id: 'porcelain',
    en: 'Kintsugi',
    fa: 'کینتسوگی',
    enDescription: 'Cool porcelain stitched with gold',
    faDescription: 'چینی خنک با رگه‌های طلایی',
    seed: Color(0xFF8C6C22),
    icon: Icons.diamond_outlined,
    light: Color(0xFFF3F4FA),
    dark: Color(0xFF171D2C),
  ),
  (
    id: 'circuit',
    en: 'Circuit',
    fa: 'مدار الکترونیک',
    enDescription: 'Precise cyan routes on a midnight board',
    faDescription: 'مسیرهای فیروزه‌ای روی برد نیمه‌شب',
    seed: Color(0xFF007F86),
    icon: Icons.memory_outlined,
    light: Color(0xFFEAF7F9),
    dark: Color(0xFF071E27),
  ),
  (
    id: 'afterimage',
    en: 'Afterimage',
    fa: 'پس‌تصویر',
    enDescription: 'Electric lime and an optical rhythm',
    faDescription: 'لیمویی الکتریکی و ریتم خطای دید',
    seed: Color(0xFF637D00),
    icon: Icons.blur_circular_outlined,
    light: Color(0xFFF1F4E9),
    dark: Color(0xFF181B10),
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

/// The palette's one-line description, in the interface's language.
String nexThemePresetDescription(BuildContext context, String id) {
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  return nexLabel(context, p.enDescription, p.faDescription);
}

ThemeData nexApplyThemePreset(ThemeData base, String id, Color? accent) {
  if (id == 'classic') return base;
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  // An accent somebody picked, as opposed to the palette's own. The palette's
  // seed is laid out tonal-spot, muted to sit with its surfaces; a picked one
  // was turned brown by the same treatment — a red came out #904A45 — and
  // read as not applied at all. A picked accent keeps its own colour.
  final picked = accent != null && accent.toARGB32() != p.seed.toARGB32();
  final surface = base.brightness == Brightness.light ? p.light : p.dark;
  var colors = ColorScheme.fromSeed(
    seedColor: picked ? accent : p.seed,
    brightness: base.brightness,
    // Graphite is the one palette that is about having no colour: its tones
    // are taken without chroma, so nothing turns faintly blue.
    dynamicSchemeVariant: id == 'graphite'
        ? DynamicSchemeVariant.monochrome
        : picked ||
              const {
                'bauhaus',
                'porcelain',
                'circuit',
                'afterimage',
              }.contains(id)
        ? DynamicSchemeVariant.fidelity
        : DynamicSchemeVariant.tonalSpot,
    surface: surface,
  );
  if (picked && id == 'graphite') {
    // Grey everywhere but the accent: a colour picked on Graphite is the one
    // colour on the screen, rather than one Graphite quietly ignores.
    final tint = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: base.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    colors = colors.copyWith(
      primary: tint.primary,
      onPrimary: tint.onPrimary,
      primaryContainer: tint.primaryContainer,
      onPrimaryContainer: tint.onPrimaryContainer,
    );
  }
  final visual = base.extension<NexVisualStyle>();
  return base.copyWith(
    colorScheme: colors,
    // Transparent stays transparent. The base theme clears the scaffold
    // whenever the app's backdrop has something to show — glass, a pattern,
    // this theme's motif — and painting the palette's surface over it here
    // hid all three: 1.92.0's motifs were drawn and never seen. The backdrop
    // takes the palette's surface instead, below.
    scaffoldBackgroundColor: base.scaffoldBackgroundColor.a == 0
        ? Colors.transparent
        : colors.surface,
    extensions: [
      ...base.extensions.values.where((e) => e is! NexVisualStyle),
      ?visual?.copyWith(
        baseColor: colors.surface,
        glassOpaque: colors.surfaceContainerLow,
        floatingGlassWash: NexGlassWash(
          films: visual.floatingGlassWash.films,
          lift: visual.floatingGlassWash.lift,
          anchor: colors.surfaceContainerLow.withValues(
            alpha: base.brightness == Brightness.dark ? 0.10 : 0.30,
          ),
        ),
        glassWash: NexGlassWash(
          films: [
            colors.surfaceContainerLow.withValues(alpha: 0.72),
            (base.brightness == Brightness.dark ? Colors.white : Colors.black)
                .withValues(alpha: 0.035),
          ],
          lift: colors.surfaceContainerHigh.withValues(alpha: 0.2),
          anchor: colors.surfaceContainerLow.withValues(alpha: 0.15),
        ),
      ),
    ],
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        side: visual?.liquidGlass == true
            ? BorderSide.none
            : BorderSide(color: colors.outline),
      ),
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
    // Text fields, switches and outlined buttons were still drawn in the
    // classic palette's greys — a search box, the switch beside every
    // setting, a plain button — so on Saffron or Midnight they read as
    // pieces of another app. They take this palette's own tones.
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: colors.surfaceContainerHigh,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: BorderSide(color: colors.primary, width: nexFocusRingWidth),
      ),
    ),
    switchTheme: base.switchTheme.copyWith(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : colors.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : colors.surfaceContainerHighest,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onPrimary
            : colors.outline,
      ),
    ),
    // The base theme darkens the classic accent for quiet buttons' labels
    // (LOC-07); a palette's own primary is already a text tone, and the
    // classic one must not leak onto it.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
      ).merge(base.textButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ).merge(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: colors.outline)),
      ),
    ),
    // No colour for icons across the board. One set here won over the
    // foreground every filled button gives its own icon, so on every palette
    // but the classic one the capture arrow, the vault's add buttons, the
    // saved-messages send and the voice note's play button drew a grey icon
    // on a coloured button — about 1:1 in dark.
  );
}
